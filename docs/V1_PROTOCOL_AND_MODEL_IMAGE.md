# FPGA NPU V1 — UART transport, binary model image and integer semantics

**Status: precise design specification, NOT IMPLEMENTED.** Golden byte-level vectors and HDL tests must validate this contract before claiming a completed model loader. This document supersedes conceptual JSON-only examples elsewhere in the repository.

## 1. UART frame format

Transport target: 115200 baud, 8N1; all multi-byte numbers **little-endian**; only one outstanding command (stop-and-wait).

| Field | Width | Meaning |
|---|---|---|
| SOF | 2 bytes | `A5 5A` |
| version | 1 byte | `01` |
| opcode | 1 byte | Request code; response = opcode OR `0x80` |
| sequence | 2 bytes | u16 echoed in response |
| payload length | 2 bytes | u16 in 0..128 |
| payload | 0..128 bytes | opcode-specific |
| CRC16 | 2 bytes | CRC-16/CCITT-FALSE, polynomial `0x1021`, init `0xFFFF`, non-reflected, xorout 0, applied from **version through last payload byte**, excluding SOF and CRC |

Response payload starts with a status byte: `0 OK; 1 BAD_CRC; 2 BAD_LEN; 3 BAD_VERSION; 4 UNSUPPORTED; 5 BUSY; 6 NO_MODEL; 7 MODEL_INVALID; 8 OUT_OF_RANGE; 9 BAD_SEQUENCE; 10 INPUT_INCOMPLETE; 11 RESULT_NOT_READY; 12 INTERNAL`. Retry/timeout policy must be explicit in the host driver. Packet CRC detects accidental errors, not malicious changes.

| Opcode | Name | Purpose |
|---|---|---|
| `0x01` | GET_CAPS | Actual hardware/build limits, clock, precision, lane count and version |
| `0x10` | MODEL_BEGIN | Invalidate previous model; declare total image bytes u32 and CRC32 u32 |
| `0x11` | MODEL_WRITE | Offset u32 + <=124 image bytes, strictly contiguous with ACK |
| `0x12` | MODEL_COMMIT | Check all bytes, CRC32, descriptors/bounds/quant and bias overflow invariants |
| `0x13` | MODEL_STATUS | Valid/loading/error, committed image fingerprint |
| `0x20` | INPUT_BEGIN | Set exact expected input length u16; clear old staged input |
| `0x21` | INPUT_WRITE | Offset u16 + <=126 signed INT8 bytes, strictly contiguous |
| `0x22` | RUN | Start one inference, reject busy/missing/incomplete input |
| `0x23` | RESULT_READ | Offset u16 + requested count u8, return bounded signed INT32 logits |
| `0x30` | GET_STATS | Result readiness, compute cycles, active issues, stalls and errors |
| `0x7F` | SOFT_RESET | Invalidate model/input/result states and restart control |

A 128-byte response cannot contain 256 logits: `RESULT_READ` must page the final vector (e.g. <=30 logits after response metadata). The host must never interpret UART round-trip as core-only processing latency.

## 2. Binary model image, exactly specified

Image sections in order: **32-byte header → L×32-byte layer descriptors → packed weights → packed INT32 biases → L×8-byte quant records**. No FPGA JSON parser. Model CRC32/IEEE (reflected polynomial `0xEDB88320`, init `0xFFFFFFFF`, final XOR `0xFFFFFFFF`) covers **all bytes including header and row padding**. `MODEL_BEGIN` supplies expected CRC and total image length.

### Header (32 bytes)

| Byte offset | Type | Name and acceptance rule |
|---|---|---|
| `0x00` | 4 ASCII bytes | `NPU1` |
| `0x04` | u8 | major=1 |
| `0x05` | u8 | minor=0 |
| `0x06` | u8 | layer_count L, 1..4 |
| `0x07` | u8 | flags=0 |
| `0x08` | u16 | first input_dim, 1..256 |
| `0x0A` | u16 | final output_dim, 1..256 |
| `0x0C` | u32 | descriptor_bytes = 32×L |
| `0x10` | u32 | weight_bytes <=16,384 and divisible by 8 |
| `0x14` | u32 | bias_bytes <=4096 and divisible by 4 |
| `0x18` | u32 | quant_bytes=8×L |
| `0x1C` | u32 | reserved=0 |

Total image length must equal `32 + descriptor_bytes + weight_bytes + bias_bytes + quant_bytes`, with overflow-safe arithmetic.

### Layer descriptor (32 bytes per layer)

| Offset | Type | Meaning |
|---|---|---|
| `0x00` | u8 | `0x01=DENSE_RELU_Q8` (hidden); `0x02=DENSE_LOGITS_I32` (last) |
| `0x01` | u8 | flags=0 |
| `0x02` | u16 | reserved=0 |
| `0x04` | u16 | input_dim 1..256 |
| `0x06` | u16 | output_dim 1..256 |
| `0x08` | u32 | weight_offset **bytes into weight section**, 8-aligned |
| `0x0C` | u32 | bias_offset **bytes into bias section**, 4-aligned |
| `0x10` | u32 | quant_offset **bytes into quant section**, 8-aligned |
| `0x14` | u16 | row_stride_words = ceil(input_dim/8) |
| `0x16` | u16 | reserved=0 |
| `0x18` | u32 | reserved=0 |
| `0x1C` | u32 | reserved=0 |

Require first input_dim and last output_dim to match header, every adjacent layer's dimensions to chain, no op other than dense/ReLU hidden + logits final. Weight bytes per layer = `output_dim * row_stride_words * 8`; bias bytes = `output_dim * 4`; quant bytes = 8. Sections must be in-bounds, aligned, non-overlapping and densely packed in layer order. Disallow tied tensors and gaps in V1.

**Weight layout:** output-neuron-major, consecutive signed INT8 weights per input element; pad each neuron row with zeros to 8-byte boundary. Identical binary package works on P=1/4/8 builds. **Bias:** signed INT32 little-endian, one per output neuron. **Quant record:** u32 multiplier at byte 0, u8 shift at byte 4, 3 reserved zero bytes. Hidden layers require M in 1..0x7FFFFFFF and S in 0..31; final quant record must be eight zero bytes.

## 3. Exact arithmetic (symmetric signed INT8)

For each layer output neuron j, `dot = Σ_i int32(x[i]) * int32(w[j,i])`, ignoring padded lanes. `v = dot + signed_int32(bias[j])`; no INT32 overflow is permitted. A conservative loader guard is `abs(bias_j) + 16384*input_dim <= 2147483647`, with **64-bit magnitude evaluation** to handle INT32_MIN. This may reject some numerically safe models, intentionally simplifying the V1 guarantee.

Hidden layer: `r = max(v,0)` (ReLU), `u = int64(r) * uint32(M)`; for S=0, `q=u`; for S>0, `q = (u + 2^(S-1)) >> S` (nearest, ties **away from zero**, with nonnegative ReLU input). Output = `clip(q, -128,127)` as signed INT8 (hidden ReLU implies 0..127). The final layer stores full signed INT32 `v` as a logit, **no final requantisation or softmax**. If argmax is implemented, lowest numerical index wins any tie; labels remain host-defined.

The independent reference must test −128×−128, signed bias corners, 8-byte tail masks, layer swaps, ties, saturation, invalid M/S, dimension mismatch, invalid offsets and incomplete/CRC-corrupt reloads. The host exporter must accept only models fitting these math and operator restrictions.

## 4. Runtime loading and model lifecycle

`MODEL_BEGIN` clears the previous `model_valid` immediately. Accepted MODEL_WRITE chunks advance one expected offset; CRC/sequence-invalid frames do not advance the loader. A model becomes executable **only** after COMMIT verifies full length, CRC32, all descriptors and bounds, every required bias/quant record, and conservative no-overflow bounds. On failure model_valid stays zero and the previous model is *not* preserved (single model-memory bank). Inference and model writes cannot overlap. Model input/output dimensions are opaque to applications.

Minimum reconfiguration proof: load fixture A (8→16→4), infer and compare all four logits; load fixture B (12→8→3), compare all three; reload A, compare again **without any bitstream modification**. Repeat with invalid packet/model/reset, and record source SHA, model CRC, bitstream SHA, compiler/tool version and raw UART evidence.

# Model portability, quantisation and binary-interface contract

**This document defines a proposed V1 contract; exact byte offsets, opcodes, CRC coverage and version fields must be frozen in M0 and checked against golden test vectors before releasing code.**

## 1. Model sources and training

A neural network can be trained locally in Python or obtained from an appropriately licensed source. The on-FPGA engine **does not know the training data or application**. Only the independently exported, compatible model package is used. Do not imply any third-party model or benchmark is present until it is named, acquired, licensed, exported and tested.

Host-side pipeline: `PyTorch / supported ONNX subset or test fixture → operator validation → quantisation/calibration → deterministic model package → independent integer oracle → FPGA model loader → inference`.

**V1 import scope:** sequential `Linear/Gemm` + `ReLU`, subject to shape and quantisation restrictions. No promise to execute arbitrary ONNX models, PyTorch graphs, or CNNs. Unsupported operations must fail clearly.

## 2. Proposed model manifest (conceptual; no implementation claim)

```json
{
  "schema": "fpga-npu-model-v1",
  "model_id": "test-8x16x4",
  "precision": "signed_int8_symmetric",
  "input_dim": 8,
  "max_input_dim": 256,
  "layers": [
    {"op": "dense_relu", "input_dim": 8, "output_dim": 16, "weight_offset": 0, "bias_offset": 0, "M": 12345, "S": 16},
    {"op": "dense_logits", "input_dim": 16, "output_dim": 4, "weight_offset": 128, "bias_offset": 64}
  ],
  "layout": "output_major",
  "rounding": "nearest_ties_away_from_zero",
  "payload_crc32": "set_by_exporter",
  "exporter_version": "planned"
}
```

The JSON is a human-readable representation. The FPGA receives a **compact binary descriptor and tensor image**, not JSON parsing. Example M/S integers are **illustrative placeholders only**, not a trained model. The executable binary descriptor schema must specify each field's type, width, endian and validation rule. Offsets/lengths must be bounds-checked against the advertised SRAM capacity.

## 3. Fixed-point numerical definition

- Activation and weight: 8-bit **two's-complement signed** integer, zero point 0.
- Multiply: signed INT8 × INT8, sign-extend product before accumulation.
- Accumulation: signed INT32 and aligned INT32 bias. Exporter rejects any model with a mathematically unbounded accumulation including bias within supported input range.
- Intermediate hidden layer: optional ReLU, then integer requantisation `Q = saturate_int8(round_ties_away_from_zero((acc * M) / 2^S))` for positive integer M and nonnegative integer S; 64-bit intermediate or rigorously proven equivalent shift sequence is required. The exporter validates M, S and intermediate range. **For negative values**, ties-away-from-zero is applied to magnitude then sign restored; mathematical semantics are written into golden tests.
- Final layer: signed INT32 logits (no mandatory softmax or argmax); optional class selection on FPGA but logits must remain available for bit-exact validation.
- Per-layer quantisation parameters are required in V1; per-output-channel scales can be a subsequent supported extension.
- Input vector length must match model descriptor; no silent zero padding, truncation or shape adaptation.

A `model_id` is for tracing; source SHA/hash and manifest hash are recorded by the host. Model integrity is checked at loader time; we cannot claim cryptographic authentication merely because packets use CRC.

## 4. Minimum two-model same-bitstream test

| Fixture | Layer shape | Purpose |
|---|---|---|
| `fixture_a` | `8 → 16 → 4` | Short dense two-layer model; tests hidden activation |
| `fixture_b` | `12 → 8 → 3` | Different input, hidden, output sizes; tests reconfiguration, memory reuse and previous-model invalidation |

Fixtures use deterministic explicitly documented **synthetic integer weights**, not external trained models. They prove programming and inference correctness but **not classification accuracy**. Later separate model trials can train on a public dataset and report source, preprocessing, seeds, accuracy and licensing.

Pass: with a **single unchanged source commit, FPGA bitstream and lane-count configuration**, load A, infer and bit-compare every output; load B, infer and bit-compare; reload A, infer and compare; include reset, invalid model, incomplete load and overflow rejection tests. Document the bitstream hash before/after.

## 5. Proposed host/FPGA command protocol

Commands (names proposed): `GET_CAPS`, `BEGIN_MODEL`, `WRITE_MODEL_CHUNK`, `COMMIT_MODEL`, `GET_MODEL_STATUS`, `INFER`, `READ_RESULT`, `GET_STATS`, `SOFT_RESET`. Use sequence IDs, maximum length, timeout, CRC and error enumeration. Binary package assembly uses exact deterministic byte offsets and little-endian integers, with no dependency on Python object serialisation. A model commit must ensure all required bytes are present and checksummed before `model_valid` goes high.

For initial low-speed USB-UART, transfer may be slow; **do not use UART wall time as NPU core performance**. If later models outgrow on-chip SRAM or need real-time streaming, the design must add a memory interface / DMA and revalidate the architecture.

## 6. Rejection cases

Unsupported graph op, excess layer count, invalid dimension/stride/offset, total byte count overflow, invalid requant parameters, checksum mismatch, incomplete model, model change while busy, wrong input length, stale model ID, payload truncation, reset during load, hidden-layer accumulation overflow. Every rejection requires explicit status with no partially valid inference.

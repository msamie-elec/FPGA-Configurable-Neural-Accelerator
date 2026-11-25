# RTL Module Contracts V1 — detailed implementation handoff

**Status: design contracts.** See [implemented RTL](V1_IMPLEMENTATION.md) for module consolidation, memory prefetch, and verified behaviour.

## 1. Clock, reset and handshakes

- Single system clock `clk`. `rst` is **active-high synchronous** internally. An asynchronous external reset is synchronised/deasserted by the board wrapper. RX serial input passes through a 2-FF synchronizer. Every module has defined reset output values.
- Streaming interfaces use `valid/ready`: transfer at rising edge when both are asserted; a sender retains payload and `valid` until accepted. Output BRAM reads use `rd_en`, `rd_addr`, and a **registered** `rd_data_valid` after the specified read latency (V1 target: 1 clock).
- Every compute transaction carries (or can reconstruct unambiguously) layer number, neuron number, input-group index, final-group flag and valid-lane mask. These tags follow memory operands and products to prevent mixing neuron sums.
- All widths use explicit SystemVerilog `logic signed`. Product signed 16 b, group sum signed 19 b (for P≤8), neuron accumulator/bias signed 32 b, requant multiply signed 64 b.

## 2. Contract table

| Module | Principal ports / interface | Contract and assertions |
|---|---|---|
| `board_top_a7`, `board_top_s7` | oscillator, reset, uart_rx, uart_tx, status LEDs | Separate confirmed FPGA part/XDC/clock; no application semantics |
| `uart_rx_byte_engine`, `uart_tx_byte_engine` | 8N1 serial and byte valid/ready | Target 115200 baud; framing/overrun detection; no non-serial timing assumptions |
| `frame_parser_crc16` | UART byte stream → complete command | SOF/version/len/CRC validated before dispatch; 128-byte max payload; reset/timeout recovery |
| `frame_builder_crc16` | response opcode/sequence/status/payload → UART bytes | Deterministic response/CRC; no reply corruption under Tx stall |
| `command_dispatcher` | decoded frames ↔ loader/input/engine/result/caps | At most one outstanding command; BUSY when required; no forbidden state mutation |
| `caps_status_registers` | GET_CAPS, GET_STATS | Advertise exact lane count, dimensions, memory sizes, version and supported ops |
| `model_load_controller` | BEGIN/WRITE/COMMIT, image data, expected CRC | Clears old valid on BEGIN; monotonic offsets; sets valid only after complete image + checks |
| `image_crc32_checker` | ordered image bytes | CRC32/IEEE with exact coverage; integrity only, not cryptographic signature |
| `descriptor_validator` | 32B header and 32B layer descriptors; quant, bias | Bounds, dimension chain, operator and memory-region checks; bias overflow guard |
| `memory_ownership_mux` | loader and inference memory requests | Exclusive owner; no simultaneous writes/reads to forbidden banks |
| `weight_bram64` | 64-b word address, write mask/data, read result | 2048 packed words; synchronous read; no out-of-range address |
| `bias_ram32` | element address, signed 32-b data | 1024 entries; little-endian byte import; bounds checked |
| `descriptor_ram`, `quant_parameter_ram` | 4 entries each | Exact records from binary package; read only committed data during RUN |
| `activation_sram_a64`, `_b64` | 32 packed words, 8 byte-enables | Ping-pong by layer; current bank read and other bank write; never in-place conflict |
| `output_logit_ram32` | index + signed 32-bit result | 256 result words; host sees valid outputs only after job complete |
| `inference_controller_fsm` | model_valid/input_complete/start → busy/done/error | One active job; reset invalidates; no early done |
| `layer_scheduler` | descriptors; layer, neuron/group counters | Correct activation-bank swap; layer dimension chaining; exact output count |
| `address_generator` | layer/neuron/group and row_stride | `weight_base + j*stride + floor(i/8)` and `a_addr=floor(i/8)`; masks padded tail |
| `operand_fetch` | registered 64-b weight and activation words | Correct byte selection for P=1/4/8, sync BRAM and group tags |
| `multiply_pe` | two signed INT8 operands, valid | Product signed INT16; −128 × −128 = 16384; invalid lanes zero |
| `parallel_pe_array` | P operand pairs and lane mask | Exactly P PEs, all lane valid alignment verified |
| `signed_reduction_tree` | P signed INT16 products with tags | Deterministic group sum, no sign-extension error; pipeline follows tag |
| `accumulator_int32` | signed group sum, per-neuron clear, group_valid | Each accepted sum added once, no overlap across neurons, final drain before bias |
| `bias_add_int32` | accumulator + signed INT32 bias | No overflow for valid models; assert and error for invalid states |
| `relu_requant_int8` | biased INT32, unsigned M, unsigned S | ReLU then 64-bit multiply, ties-away shift, signed INT8 saturation |
| `hidden_activation_writeback` | result INT8 and neuron index | Correct packed byte lane, one write/output; swap only when all stored |
| `final_logit_writeback` | signed result and index | Stores all final INT32 scores; optional argmax lowest-index tie |
| `performance_counters` | start, issue, stall, done | Count compute cycles separately from UART/model-transfer time |
| `result_response_controller` | result RAM and READ_RESULT paging | No stale results, sequence/model ID coherent, bounded payload frames |

## 3. Processing-element containment and timing

```text
npu_inference_engine
  ├── operand_fetch                [64-bit packed BRAM words]
  ├── parallel_pe_array #(P)
  │   ├── multiply_pe 0            [INT8 a × INT8 w → INT16 product register]
  │   ├── ...
  │   └── multiply_pe P−1          [valid, lane-mask, neuron tag]
  ├── signed_reduction_tree        [P products → signed 19-bit group sum]
  ├── accumulator_int32            [sum all groups of current output neuron]
  ├── bias_add_int32
  ├── relu_requant_int8             [hidden; INT64 intermediate]
  ├── hidden_activation_writeback  [INT8 ping-pong]
  └── final_logit_writeback        [final; INT32]
```

Target latency per arithmetic group: registered SRAM access (1) + multiplier (1) + registered reduction levels `ceil(log2 P)` + accumulator (1). This is an *RTL stage plan*; overall cycles include setup, drains, bias/postprocess, writes and stalls. Optimisation must preserve tags/handshake correctness.

For `P<8`, reuse a latched 64-bit word across P-byte groups. For `P=8`, read one packed activation word and one packed weight word for each group. Tail lanes `i>=input_dim` contribute **zero**, and no weight access crosses into another output row. Output-neuron boundary is a hard drain barrier in V1, making accumulator correctness easier to prove.

## 4. External transaction order

- `GET_CAPS` → `MODEL_BEGIN(length,crc32)` → sequential `MODEL_WRITE(offset,bytes)` / ACK → `MODEL_COMMIT` → `MODEL_STATUS`.
- `INPUT_BEGIN(length)` → sequential `INPUT_WRITE(offset,bytes)` → `RUN` → poll `GET_STATS`/read-ready → paged `RESULT_READ`.
- Model memory is loader-owned until successful commit, then engine-owned during inference. Any model upload clears previously committed validity and is forbidden while inference busy. Input staging must match the loaded model's first layer.
- On external/SOFT_RESET, clear `model_valid`, input_complete, result_valid, busy and command state; RAM bytes may remain physically unchanged but must not be used until reloaded.

## 5. Minimum formal/assertion set

1. Producer's `valid && !ready` implies stable payload until accepted (unless reset).
2. No inference `start` unless model committed, input complete, idle and dimensions exact.
3. Weight/activation/bias addresses always in-bounds; no padding treated as a real element.
4. A neuron emits exactly `ceil(input_dim/P)` product groups; all tags traverse stages without loss/duplication.
5. Exactly one accumulator reset and one postprocess output per neuron.
6. Hidden activation banks only swap after all writes have completed; never read stale values.
7. Final results preserve signed INT32 logits, not rounded INT8 final scores.
8. `model_valid` cannot rise on malformed, partial, CRC-mismatched or overflowing models.
9. No load-and-run memory-ownership overlap; no stale result after reset or new RUN.
10. Run fixture A→B→A using one **identical** bitstream; all logits match an independently coded integer oracle.

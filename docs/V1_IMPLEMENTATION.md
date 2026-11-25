# V1 implementation notes

The implementation supports one to four sequential dense layers with signed INT8 operands, INT32 bias/accumulation, ReLU/requantisation in hidden layers and full INT32 final logits. Model images and inputs are loaded at runtime. Lane count is fixed at synthesis. The [protocol specification](V1_PROTOCOL_AND_MODEL_IMAGE.md) defines the model bytes and numerical contract.

| RTL module | Responsibility |
|---|---|
| `arty_a7`, `npu_top` | Arty clock/reset/USB-UART pins and integration |
| `uart`, `packet_link` | Asynchronous receive synchronizer, 8N1 transport, CRC-16, command/reply framing, parser timeout |
| `npu_commands` | Descriptor and bounds validation, CRC-32, command dispatch, load ownership and result paging |
| `packed_ram` | Synchronous byte-write memory for weights, bias, activations and logits |
| `dense_engine` | Layer/neuron scheduling, bank selection, weight and activation prefetch, bias, requantisation and performance counters |
| `dot_pipeline` | Registered parallel signed products with tail masking and registered reduction levels |

The engine holds one neuron in flight. Each weight and input word is fetched synchronously, then reused for 8, 2, or 1 issues at P=1, 4 or 8. It prefetches the next packed word during the last issue for the current word, so successive groups can issue every cycle once a neuron starts. At the end of each neuron, the last-group flag drains with the data before bias is applied. The pipeline requires no backpressure from writeback. The valid/last flags and the single-neuron ownership barrier supply the identity required for accumulation.

The requant multiplier is split into four registered unsigned partial products after ReLU. A subsequent stage reconstructs the 64-bit result before rounded shift and INT8 saturation. Software should supply zeroed row padding. The hardware mask makes unused lanes inert regardless of stored padding bytes.

An accepted `RUN` consumes the staged input. Each subsequent job requires a fresh upload, since hidden layers may overwrite the original bank. During inference, status queries remain available, mutation commands return BUSY and results remain unavailable until the final write. The single model bank is invalidated immediately on accepted `MODEL_BEGIN`. Hard reset aborts an active run. Soft reset is accepted while idle and invalidates model, input and results.

The exporter accepts **already quantised parameters** as JSON. Each layer requires `weights` (output-major rows) and `bias`. Hidden layers also require integer `multiplier` and `shift`. Supported precision and arithmetic match V1 exactly. The optional digits fixture includes its own training and quantisation procedure.

```bash
python -m host.npu pack layers.json model.bin
python -m host.npu run COM4 model.bin input.json
```

## Response layouts

All payloads start with a status byte. Successful responses append these little-endian fields. Model and input writes must be strictly contiguous. The host uses the frame sequence for response correlation and the board checks chunk offsets for write ordering. Maximum receive-frame inter-byte gap is 100 ms at the board clock; the parser resynchronises after a timeout or a UART framing error.

| Command | Successful response fields after status |
|---|---|
| GET_CAPS | Protocol version u8, clock Hz u32, lanes u8, max layers u8, max input u16, max output u16, weight bytes u16, bias bytes u16, supported-op bitmap u8 (bits 0/1 = hidden/final dense) |
| MODEL_STATUS | Flags u8 (valid, loading, commit error at bits 0–2), committed CRC32 u32 |
| GET_STATS | Flags u8 (busy, result valid, model valid, input staged at bits 0–3), last dispatched status u8, core cycles u32, issue groups u32, weight-word reads u32, committed model CRC32 u32, job ID u32 |
| RESULT_READ | Offset u16, count u8 (1–30), count signed INT32 values |
| Others | Status only |

`core_cycles` counts active engine cycles including the final store. `word_reads` counts actual packed weight reads, including the initial fetch and prefetches. The counters hold their most recent values until the next engine start or hardware reset. Model and result validity flags determine whether a previously counted job has accessible output.

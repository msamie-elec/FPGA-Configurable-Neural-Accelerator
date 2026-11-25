# FPGA Configurable Neural Accelerator — RTL System Design V1

**Status: implementation architecture specified, RTL NOT YET IMPLEMENTED OR VERIFIED.** These documents define the design to implement, not measured performance. The final FPGA poster must be derived from this hierarchy, not drawn independently.

## 1. Product boundary

The product is reusable NPU-style **FPGA inference IP**, independent of motors, cameras, handwriting or other applications. The laptop imports or trains a compatible network, quantises its parameters, generates a binary model image, sends the image and inputs to the board, and checks returned results against an **independent** integer reference. The FPGA **does not** train models or extract application features; it performs the complete supported neural-network inference calculation.

**V1 operator set:** 1–4 sequential fully connected (dense) layers. Each non-final layer uses signed INT8 input and weights, signed INT32 bias/accumulator, ReLU and deterministic INT8 requantisation. The final layer produces the **full signed INT32 logits vector** with optional argmax index. All application labels and pre/postprocessing belong to host adapters, not accelerator RTL. No convolution, attention, softmax, pooling, arbitrary ONNX, DDR/AXI DMA or training in V1.

**Crucial reusability contract:** the *same programmed bitstream* must load and run model A (8→16→4), model B (12→8→3), then A again, without changing RTL or bitstream; complete logits must match an independent software oracle. Different MAC-lane counts (1/4/8) require **separate** bitstreams, but use the same model package format.

## 2. FPGA hierarchy — physical containment tree

```text
board_top_a7 / board_top_s7               board-specific clock, reset, pins
├── board_clock_and_reset
├── uart_rx_input_sync                    async RX synchronizer
└── npu_soc_top                           portable inference IP
    ├── host_bridge
    │   ├── uart_rx_byte_engine
    │   ├── uart_tx_byte_engine
    │   ├── frame_parser_crc16            sync, length, CRC, seq, timeout
    │   ├── frame_builder_crc16
    │   ├── rx_fifo / tx_fifo
    │   ├── command_dispatcher            model/input/infer/read/status
    │   └── caps_status_registers
    ├── runtime_model_manager
    │   ├── model_load_controller         BEGIN / WRITE / COMMIT
    │   ├── image_crc32_checker
    │   ├── descriptor_validator          shapes, ops, bounds, integrity
    │   └── model_memory_write_router
    ├── npu_memory_subsystem
    │   ├── descriptor_ram                 4 × 32 B
    │   ├── quant_parameter_ram            4 × 8 B
    │   ├── weight_bram64                  2048 × 64 b = 16 KiB
    │   ├── bias_ram32                     1024 × 32 b = 4 KiB
    │   ├── activation_sram_a64            32 × 64 b = 256 B
    │   ├── activation_sram_b64            32 × 64 b = 256 B
    │   ├── output_logit_ram32             256 × 32 b = 1 KiB
    │   └── memory_ownership_mux           loading OR inference owner
    ├── npu_inference_engine
    │   ├── inference_controller_fsm
    │   ├── layer_scheduler               layer/neuron/input loops
    │   ├── address_generator              aligned weight/activation addresses
    │   ├── operand_fetch                  synchronous 64-b memory reads
    │   ├── parallel_pe_array #(LANES)     1, 4 or 8 compute lanes
    │   │   └── multiply_pe[LANES]          signed INT8 × INT8 => INT16
    │   ├── signed_reduction_tree          P products => group sum
    │   ├── accumulator_int32              sum groups for one output
    │   ├── bias_add_int32
    │   ├── relu_requant_int8               hidden layers only
    │   ├── hidden_activation_writeback     byte-enable scratchpad writes
    │   ├── final_logit_writeback           32-b output words
    │   ├── optional_argmax
    │   └── performance_counters            compute-only cycles and stalls
    └── result_response_controller         chunked logits / status
```

**Terminology:** The 1D PE array is an architecture-conscious **parallel MAC vector engine**, not a 2D TPU-like systolic array. A multiply PE contains signed multiplier and pipeline registers; accumulation for a neuron takes place in the shared post-reduction accumulator. A real systolic mesh with PE-to-PE wavefront links would be a separately designed future milestone.

## 3. Build-time and run-time configuration

| Parameter | Design target | Classification |
|---|---:|---|
| Clock | 100 MHz candidate on Arty A7 | board/build-time; actual routed timing TBD |
| Parallel multiply lanes | 1, 4, 8 | build-time, different bitstreams |
| Layers | 1..4 | runtime descriptor |
| Each layer input and output dimension | 1..256 | runtime descriptor |
| Weight memory | 16,384 bytes **including row padding** | hardware capacity; runtime image must fit |
| Bias memory | 1024 signed INT32 elements (4 KiB) | hardware capacity |
| Activation ping/pong | 2 × 256 INT8 values | hardware capacity |
| Final logits | 256 signed INT32 words | hardware capacity |
| Quant records | 4 × 8 bytes | hardware capacity |
| UART payload | maximum 128 bytes/frame | hardware transport capacity |

**Weights are output-major and padded to 8 bytes per neuron row.** All builds use one identical 8-byte-packed model format. `row_stride_words = ceil(input_dim/8)`. The core reads 64-bit activation and weight words and selects P bytes per arithmetic issue. P=1 reuses a fetched word for eight issues; P=4 uses two; P=8 uses one. All padding and tail lanes are masked to zero. An apparent 256×256 supported dimension **does not imply** 256×256 weights fit: one such layer needs 65,536 weight bytes and must be rejected by the default loader.

Examples: A 8→16→4 requires **192 padded weight bytes**; B 12→8→3 requires **152 bytes**; a 196→32→10 MLP uses **6720 bytes** (first 196-byte row padded to 200). The last is a possible application workload, not embedded FPGA logic.

Memory blocks are logical requirements. Actual BRAM36/BRAM18/LUTRAM mapping and DSP48 utilisation must be determined from Vivado implementation; neither is assumed from this specification.

## 4. Ownership, buffering and interconnect

- One FPGA internal clock domain in V1. Asynchronous UART RX uses an input synchronizer. Reset is synchronous and active-high inside IP; board wrappers supply clock/reset implementation and correct board-specific XDC.
- **Weight RAM** is 2048×64 b: loader write ownership during model load; compute read ownership during inference. **Bias RAM** is 1024×32 b. Descriptors and per-layer quant parameters have independent read access under scheduler/postprocess control.
- **Activation A/B** are packed 64-b words with byte write-enable. Initial host input is written into A. Layer L reads A and writes B; the controller swaps roles only after all outputs of L have been committed. Supports multiple sequential dense layers without in-place read/write conflicts.
- **Final logits RAM** holds up to 256 signed 32-b outputs. UART returns chunks because a complete output vector may exceed the 128-byte frame limit.
- Memory access valid/data timing is explicit: synchronous RAM read target = 1 cycle. Use registered valid/neuron/group tags through the multiply/reduce/accumulate pipeline. Read and write ownership must never overlap accidentally.
- No external DDR access or DMA engine exists in V1. The local SRAM address generator is not an AXI/DDR DMA engine.

## 5. Computation sequence (one output neuron)

1. Validate `model_valid` and a full correctly sized input vector; freeze model during RUN.
2. Fetch layer descriptor; initialise layer, neuron and input-group counters.
3. Compute `weight_word_addr = weight_base_words + neuron * row_stride_words + floor(input_index/8)`. Fetch matching activation word; align one-cycle SRAM returns.
4. Mask tail lanes. For each active PE, calculate signed `int8 activation × int8 weight → int16 product`, registering product and group/neuron tag.
5. Reduce up to P signed products with an explicitly pipelined balanced tree; group sum must support at least 19 signed bits for P=8. Add each valid group sum exactly once to an INT32 per-neuron accumulator.
6. After the last group, **drain all pipeline stages** before bias/postprocess. Compute `biased = accumulator + signed INT32 bias`; overflow is prohibited by model validity constraints.
7. For hidden layers, compute `saturate_int8(round_ties_away(relu(biased) × M / 2^S))` using signed 64-bit intermediate arithmetic; write to the opposite activation scratchpad with byte-enable.
8. For final layer, retain **signed INT32 biased logits**, write all outputs to final result RAM, optionally derive an argmax index (lowest index wins ties).
9. Emit `result_ready`, model and job IDs, compute-cycle counts, and readable result chunks; no result can be read as current while a newer job is unfinished.

**Planned pipeline:** one SRAM read stage, one signed multiply stage, `ceil(log2(LANES))` registered reduction levels (0 for one lane), one accumulation stage. Tags and valid flags follow data. Target issue interval is one group per cycle after startup if memory is ready; physical timing and stalls may lower throughput. Each neuron has a drain/wrap phase, so theoretical issue counts **are not measured cycle counts**.

For dense 196→32→10, arithmetic group-issue lower bounds (excluding all overhead) are P=1: **6592**, P=4: **1648**, P=8: **840**. RTL and physical measurements must report the actual counts separately.

## 6. Control state hierarchy

| Controller | States and responsibilities |
|---|---|
| RX/parser | `SEARCH_SOF → HEADER → PAYLOAD → CRC → DISPATCH` or `DROP/RESYNC` |
| Model | `INVALID → BEGIN → WRITE → VALIDATE → COMMIT` or `FAIL`; invalidate old model on BEGIN |
| Input staging | `EMPTY → WRITING → COMPLETE`; enforce exact model input length |
| Inference | `IDLE → LAYER_SETUP → NEURON_SETUP → ISSUE → DRAIN → BIAS → POST → STORE → NEXT_NEURON → NEXT_LAYER → DONE` |
| Result | `EMPTY → READY → CHUNK_READ → RELEASE`; associate outputs with model/job identity |
| Recovery | Reset invalidates model/input/result validity; RAM bytes need not be cleared |

No layer executes before complete descriptor/weight/bias/quant validation. No new model upload or input write can modify memories while inference is busy. No second inference is accepted during an active job.

## 7. Core limits, reference models, verification and project boundaries

- All models require **host-side training or a licensed compatible external source**. The accelerator RTL does not include a pretrained model. A host compiler handles operator checking, quantisation, padding, model packing and numerical validation; runtime loader validates model structure/integrity in hardware.
- Synthetic fixtures A/B/A prove programming and numerical correctness, **not AI classification accuracy**. A later independent trained model demonstrates functional use; record model author/source, dataset, split, preprocessing, licence, quantisation and measured accuracy.
- Verify unit multiply/reduction/rounding, memory packing and byte enables, controller state, UART CRC, invalid model and reset, multi-layer inference, A/B/A same bitstream, 1/4/8-lane parity, hardware A7 route/timing and S7 portability. Full verification scope lives in `docs/VERIFICATION.md`.
- The source tree should separate `hardware/rtl/{host,control,memory,compute,post,top}`, `hardware/boards/{arty_a7,arty_s7}`, `hardware/vivado`, `verification/{unit,integration,system,physical}`, `host/{compiler,protocol,reference,cli}`, `models/{fixtures,manifests}` and `docs`. Vivado-generated `.runs`, caches and bitstreams belong to ignored `hardware/build`, with only intentional release evidence published.

## 8. Conditions for finishing the architecture posters

Prepare **three distinct figures only after the RTL module/port contract is consistent**: (1) laptop↔FPGA system context; (2) FPGA RTL architecture with physical memory ports, scheduler, loader, control vs data arrows; (3) nested inference engine PE→product reduction→accumulator→activation/writeback. Figures must faithfully reflect **implemented RTL** when claimed as implementation, otherwise label as *planned*. The current document is the prerequisite design freeze, **not evidence of implementation**.

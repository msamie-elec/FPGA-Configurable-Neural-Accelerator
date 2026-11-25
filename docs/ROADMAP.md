# Architecture-first development roadmap and project boundaries

## Strategic decision

This is a **new, independent repository for reusable FPGA AI accelerator IP**. The older `FPGA-Edge-AI-Inference-Accelerator` repository remains untouched and can later become a separate **application and demonstrations** repository consuming a tagged, validated engine release. No coupling or cross-repo dependency is required to understand this hardware project.

## Phases and exit criteria

| Phase | Work | Deliverable / acceptance |
|---|---|---|
| M0 — architecture baseline | Freeze model/runtime capability matrix; arithmetic contract; descriptors; memory organisation; lane pipeline; interfaces; board assumptions | Reviewed docs, no unresolved contradictory field/clock/math definitions |
| M1 — arithmetic foundations | RTL signed MAC, partial sum, bias/activation/requant; independent Python oracle and coverage | Directed and random bit-exact unit regression |
| M2 — true NPU core | Runtime descriptors, configurable dense-layer scheduler, scratchpads, banked weights, output vector, cycle counters | Full multi-layer tests, distinct shapes, no model-specific logic |
| M3 — runtime programmable model | Binary model-package compiler, CRC-bounded UART model loader, status/protocol/CLI | Load A→B→A using one RTL build, no re-synthesis |
| M4 — physical board proof | A7 board wrapper, exact part/XDC, Vivado reproducible Tcl, timing/DRC, hardware validation | Measured A7 end-to-end tests with bitstream/model fingerprints |
| M5 — architecture study | 1/4/8 lane implementations, cycle/BRAM/DSP trade-off, S7 port | Comparative metrics and actual validated boards clearly labelled |
| M6 — trained-model proof and publication | Export and validate at least one actual trained compatible model (with provenance), improve docs, source audit, annotated waveforms and independent benchmark report | Strong standalone GitHub + Upwork hardware-IP case study |
| M7 — optional research | AXI4-Stream/Lite, external DMA, CNN/conv engine, pooling, true 2D systolic array, quant format variants | Separate requirements, simulations and measurement gates |

Do not rush M7 until M0–M4 work. A small, genuinely programmable and fully verified NPU core is stronger portfolio evidence than many untested application GUI features.

## Engineering work split

**FPGA:** model and activation SRAM, loader, descriptors, scheduler, MAC lanes, fixed-point operations, control and debug counters.

**Laptop:** model preparation/training or approved external model import, quantisation/exporter, integrity checking, host commands, reference inference, test collection and analysis. Laptop must not secretly compute inference when the GUI claims hardware mode.

**Applications:** Separate adapter layers convert an application input (image, sensor, maritime features) into a compatible fixed-point vector and interpret the returned result. These are proof-of-reuse demonstrations later. No application-specific logic goes into core RTL.

## Minimum portability / reuse story

1. Build once for a chosen FPGA/configuration.
2. Load generic signed-INT8 model A, request inference, verify complete INT32 output against oracle.
3. Without changing a bitstream or RTL, load differently shaped model B, send matching input, verify output.
4. Test memory/descriptor boundary handling, model replacement and recovery, then repeat on physical board.
5. Make a separately built application adapter that can plug its model and data into the same accelerator.

## Risks / constraints

| Risk | Decision or mitigation |
|---|---|
| Overclaiming general purpose | Promise only **supported operator subset**, dimensions and memory limits; report `GET_CAPS` |
| Hardcoded weights per FPGA image | Prohibit in V1 release; require runtime loading |
| Model change invalidates pipeline | Validated manifest + descriptor FSM + exact layer-length/quant checks |
| Weight memory read bandwidth bottleneck | Bank/pack SRAM and compare effective MAC utilisation |
| DSP/synthesis mismatch | Inspect actual inferred implementation, signed widths and pipeline mapping |
| Different A7/S7 clocks/pins | Dedicated board wrappers and exact XDC; record part/revision |
| Host transport dominates measurements | Distinguish compute cycles from UART RTT and loading overhead |
| Inconsistent training vs integer reference | Versioned deterministic model exports, frozen rounding/quant contract |
| Too broad operator support | Treat conv/pool/attention/AXI as optional M7 separate proof |
| Portfolio claims without evidence | No measured result until physical/test artifact present; all gates explicit |

## Public release / portfolio positioning

Candidate Upwork title after hardware verification: **“Configurable FPGA Neural-Network Accelerator (NPU-Style IP) — INT8 RTL, Runtime Model Loading and Hardware Validation.”** Lead with accelerator block diagram, hardware RTL hierarchy, bit-exact verification and resource/performance comparison; show applications only as optional add-ons. State exactly which operators and model sizes run.

## External sources (reference only)

- Digilent Arty A7 master constraints: https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-35-Master.xdc
- Digilent Arty S7 master constraints: https://github.com/Digilent/digilent-xdc/blob/master/Arty-S7-25-Master.xdc
- Digilent Arty A7 documentation: https://digilent.com/reference/programmable-logic/arty-a7/start
- Digilent Arty S7 documentation: https://digilent.com/reference/programmable-logic/arty-s7/start
- AMD Vivado manuals: https://docs.amd.com/

The exact 7-series board variant must be confirmed from the actual physical hardware. No third-party board XDC or dataset is copied into this planning package.


## 2026-11-25 external GitHub benchmark review and flagship extension

The three review repositories have been inspected. See [competitor code/evidence audit](COMPETITOR_REVIEW_AND_DIFFERENTIATION.md) and [flagship acceptance and reproducible benchmarks](FLAGSHIP_ACCEPTANCE_AND_BENCHMARK_PLAN.md).

**Scope decision:** preserve M0–M6 as the immediate priority; do not swap proven dense MAC/loader work for a speculative “universal GPU.” Add a dedicated *post-V1* CNN milestone: Conv2D + pooling with real line/window buffers, multichannel INT8 data handling, runtime model package extension and new board verification. Only after it works should we study an alternate 2D systolic tile and compare area, timing and actual board throughput using the same workload. The eventual Upwork case study must distinguish proposed, simulated, routed and measured capabilities.

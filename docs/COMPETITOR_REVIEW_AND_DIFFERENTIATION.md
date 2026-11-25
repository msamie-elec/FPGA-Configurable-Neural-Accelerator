# Three GitHub FPGA-AI accelerator references — technical audit and differentiating strategy

**Reviewed:** 2026-11-25. **Basis:** repository default branches, actual READMEs, top-level project trees and selected RTL/testbench/training files. External claims are attributed to the authors, not independently reproduced. Repositories may change. This is a planning benchmark, not a claim that our proposed RTL currently outperforms theirs.

## References and traceable evidence

| Project | Architectural evidence | What it teaches us | Limits of the comparison |
|---|---|---|---|
| [AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-](https://github.com/AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-) | [README](https://github.com/AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-/blob/main/README.md), [4×4 VHDL matrix multiplier](https://github.com/AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-/blob/main/rtl/mm4x4.vhd), [CFS top](https://github.com/AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-/blob/main/rtl/cfs_top.vhd), [VHDL testbench](https://github.com/AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-/blob/main/testbenches/tb_cfs_top.vhd), [Python training](https://github.com/AbdulrahmanGhaleb/FPGA-Based-AI-Accelerator-/blob/main/scripts/train.py) | Strong full-stack example: NEORV32 RISC-V + custom memory-mapped CFS, 4×4 int16 matrix tile, firmware, training, and FPGA evaluation. README **reports** 480/500 (96%) synthetic weather-comfort classification and 2.47× CPU-vs-accelerator speedup. | Not directly comparable: Intel Cyclone IV, RISC-V control path, other precision, model and dataset. Its fixed weather model is exported to C header; no proof of arbitrary compatible topology loading into same bitstream from reviewed artifacts. |
| [halalboro/fpga-accelerators](https://github.com/halalboro/fpga-accelerators) | [README](https://github.com/halalboro/fpga-accelerators/blob/main/README.md), [DPU flow](https://github.com/halalboro/fpga-accelerators/blob/main/dpu_solution.md), platform/tutorial directories | Strong AI deployment and documentation pattern using existing Vitis AI / DPU-PYNQ / HLS workflows, with YOLO deployment examples on Ultra96v2/Kria/ZCU platforms. Includes vendor/third-party source trees. | Primarily an integration/toolchain/tutorial collection rather than evidence of an entirely custom-from-RTL neural MAC IP. README explicitly says not actively maintained; models/platforms and source attribution differ substantially. |
| [Mattjesc/Efficient-FPGA-CNN-Accelerator](https://github.com/Mattjesc/Efficient-FPGA-CNN-Accelerator) | [README](https://github.com/Mattjesc/Efficient-FPGA-CNN-Accelerator/blob/main/README.md), [top-level RTL](https://github.com/Mattjesc/Efficient-FPGA-CNN-Accelerator/blob/main/E_FPGA_ACCELERATOR_CNN.srcs/sources_1/new/accelerator.v), [convolution RTL](https://github.com/Mattjesc/Efficient-FPGA-CNN-Accelerator/blob/main/E_FPGA_ACCELERATOR_CNN.srcs/sources_1/new/convolver.v), [testbench](https://github.com/Mattjesc/Efficient-FPGA-CNN-Accelerator/blob/main/E_FPGA_ACCELERATOR_CNN.srcs/sim_1/new/accelerator_tb.v) | Useful RTL breakdown into convolution/window buffers, quantisation, ReLU, pooling, control FSM and waveform documentation. | Testbench describes expected-result checking as a **placeholder** and primarily prints results; the README's one synthesis summary lists **0 DSP/0 BRAM**, demanding scrutiny of arithmetic mapping and observability before accepting power/throughput assertions. There is no demonstrated full runtime model-package loader in reviewed sources. |

**Caution:** These are not head-to-head benchmarks. Statements such as “better throughput,” “lower power” and “more accurate” require the same hardware configuration, task definition, model, numerical precision, methodology and independently verifiable logs. Do not infer proof of hardware from a repository README or a simulation screenshot alone. Do not copy third-party RTL or vendor libraries into this repository without explicit license compliance.

## Our intended differentiation (planned, not achieved)

1. **Own our neural compute IP**, not only a vendor DPU overlay. Written, explained, verified SystemVerilog multiplier PEs, reduction/accumulation pipeline, scratchpads, scheduler, loader and backpressure.
2. **Reprogrammable at runtime:** same real FPGA bitstream accepts two structurally different dense networks and A→B→A reload; versioned binary graph/weights/bias/quant image, model provenance and bounds-checked errors.
3. **Bit-exact verification:** independent integer Python reference; directed/random signed corner cases; per-layer end-to-end scoreboards; assertions; reset, corrupted packet, incomplete transfer and model replacement testing; test result logs under evidence/.
4. **Reproducible hardware:** board-specific Tcl/XDC for actual Arty A7 and S7 parts, documented tool version, release bitstream hash, post-route setup/hold, CDC/DRC checks and physical transcriptions.
5. **Fair PPA measurements:** physical inference cycles, latency, LUT/FF/DSP/BRAM and actual routed Fmax across P=1/4/8 builds; inferred/estimated vs measured power kept separate; quantify throughput and MAC utilization; differentiate transport RTT.
6. **Real ML workflow:** run at least one actually trained compatible model with recorded dataset/licence, training seed, export, quantisation, host reference accuracy and FPGA bit-exact agreement; not merely synthetic weights or a GUI simulation.
7. **Extensible to CNNs:** after V1 proven, implement **real** INT8 convolution and pooling kernels, line/window buffering, channel scheduling and offload in one common descriptor/host framework. A second model family differentiates reusable IP from a one-case demo.
8. **Career-grade design documentation:** complete FPGA containment hierarchy + true data/control/memory interfaces + PE pipeline/valid tags + timing annotated waveforms and reproducibility commands. Diagrams must match actual RTL, not preceding illustrations.
9. **Research-grade architectural exploration:** compare P-lane inner-product dataflow to a genuine 2D weight-stationary systolic PE array on a **common verified workload**, only if resources allow; isolate gains from changes to BRAM bandwidth, buffers and pipeline utilization.
10. **Useful developer experience:** simple Python CLI (list/probe serial devices, show caps, load model, run, compare oracle, export log) and optional generic model/inference GUI, clearly distinguishing host preview from FPGA hardware mode.

## Scorecard / acceptance gates

| Category | Evidence needed before saying “complete” |
|---|---|
| RTL functionality | All design modules exist; lint + simulations pass; synthesis elaborates named top |
| Model portability | Two different shapes and a trained model run on the **same** programmed bitstream, bit-exact oracle results |
| Memory integrity | Every illegal address/length/offset rejected; read latency and BRAM banking verified, no partial model validity |
| Arithmetic correctness | Full INT8 signed products, INT32 accumulation, 64-bit requant temp, per-layer postprocess, overflow policy; edge/random tests |
| Performance | Routed reports plus board measurements for P=1/4/8; PPA comparison includes clocks/precision/frames/counters |
| Host integration | CRC/timeout/recovery, deterministic CLI, USB-UART I/O, provenance of every recorded result |
| CNN extension | A real, separately verified convolution/pooling engine, not merely applying a flattened vector to the dense engine |
| Publication | Architecture is readable in five minutes; complete repo clone→simulation→bitstream guide; no build garbage or unproven numbers |

## Sequencing: meaningful superiority without scope explosion

**Phase A — prove the core:** finish V1 dense accelerator as documented, with runtime model loading, independent tests and one Arty A7 board. **Phase B — prove portability and quantified architecture:** implement P=1/4/8, A7/S7 variants, trained model and toolchain. **Phase C — extend the computational capability:** optional CNN-INT8 conv+pool with real line/window buffering, then selective 2D systolic research; accept only after V1 is complete and quantitatively characterized.

The result we seek is not “more modules than competitor X”; it is an **inspectable, novel-for-this-repo, measured, defensible FPGA neural-accelerator implementation** suitable for RTL/FPGA, hardware IP, embedded AI and architectural feasibility portfolios.

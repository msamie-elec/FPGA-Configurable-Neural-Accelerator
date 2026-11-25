# Flagship engineering acceptance & benchmark plan

**Status: planned tests, not measurements.** The repository does not yet have validated accelerator RTL. This plan defines how we will earn stronger claims than an unverified demo.

## Test-driven release milestones

| Gate | Build artifact | Minimum evidence | Claim allowed on portfolio |
|---|---|---|---|
| G0 specification | Versioned model format + interfaces + memory map | Golden CRC16/CRC32 example vectors, model-image examples and design review | Detailed hardware design |
| G1 compute foundation | Synthesizable P=1/4/8 PE, reduction, accumulation, ReLU/requant | Independent Python and HDL bit-exact tests, signed corners, reset/stall/tail-masking | Verified RTL components |
| G2 end-to-end NPU | Scheduler + ping/pong scratchpads + descriptor parser | 1-, 2-, 4-layer randomized models, nonmultiple-of-P shapes, full logits comparison | Configurable simulated engine |
| G3 model-loader | UART packet/frame, runtime-memory writer, validators | CRC corruption/timeout/reload/error tests, A→B→A in same HDL elaboration | Runtime model loading verified in simulation |
| G4 FPGA hardware | Arty A7 bitstream + Python driver | A→B→A on same **bitstream hash**, ≥100 deterministic extra cases, captured logs, source SHA, routed timing, DRC/CDC report | Real A7 hardware validation |
| G5 PPA study | 1-,4-,8-lane A7 builds; S7 if correct board available | Table of LUT/FF/DSP/BRAM/WNS/WHS, clock, core cycles, board latency, useful MACs, stalls, estimated vs measured power | Resource/latency architectural trade-off |
| G6 real network | Licensed source dataset + trained/exported supported network | Training provenance/seeds, accuracy before/after quant, FPGA-vs-reference vectors; no hidden host inference in hardware mode | End-to-end trained AI inference on FPGA |
| G7 CNN expansion (separate version) | INT8 Conv2D + pooling + line/window buffers + multi-channel scheduler | Bit-exact padded/unpadded/stride/tail tests; compiler rejects unsupported model graphs; physical board revalidation | Dense + CNN reusable accelerator IP |
| G8 optional microarchitecture research | Weight-stationary 2D systolic PE array **or** specialized tiling option | Same workload, quant format, board, constraints, clock methodology; inter-PE wavefront trace + measured PPA | Quantified comparison of dataflow architectures |

## Benchmark matrix (record rows for every experiment)

| Field | Definition / provenance |
|---|---|
| Board & bitstream | Exact device part/revision, board ID, clock, Vivado version, bitstream SHA256, Git SHA |
| Workload | Model image hash, trained/synthetic label, layer shapes, op set, number of useful INT8 MACs |
| Correctness | N/total *full output-vector* bit-exact matches, training/test accuracy only for labeled datasets |
| Core cycles | FPGA counter from accepted RUN to output-vector valid, excluding UART and model load |
| Core time | Cycles / achieved clock frequency; measured clock settings, not host RTT |
| Throughput | Sustained jobs/s over named continuous test interval, separately from finite burst peak |
| Utilization | Useful scalar MACs / (MAC lanes × active engine issue cycles) with stall and padding attribution |
| Resources | Post-place/route LUT/FF/DSP/BRAM and routing WNS/WHS; exact XDC |
| Power | Vivado estimated dynamic/static with activity assumptions, clearly labeled; never a physical power value without instrumentation |
| Baseline | Independent integer CPU implementation same input, quant, model; measure compute-only and end-to-end separately |

**Performance accounting:** A P-lane dot product's lower bound is ceil(N/P) compute *issue* opportunities. Pipeline fill/drain, per-neuron setup, BRAM read and writeback must be measured, not hidden. Do not advertise nominal DSP × clock as sustained TOPS.

## Failure-to-release conditions

- Printed testbench messages that merely say PASS without oracle comparisons.
- Same source file used to implement both DUT and independent expected-output oracle.
- Changing bitstreams between supposedly runtime-loaded models.
- No physical board trace but implying FPGA validation.
- Reporting GUI/software prediction as accelerator output.
- Missing unconstrained-path/hold/CDC qualifications or assigning arbitrary clock rate.
- Comparing resource counts, accuracy or speed with another repository's *different* devices/network/precision as a head-to-head win.
- Training provenance missing for claimed pretrained model.
- Claiming a 1D parallel lane array is a 2D systolic mesh.
- Shipping Vivado caches, machine-specific generated paths or huge third-party vendored IP without need/licensing.

## Architecture poster publication gate

The public diagrams must correspond to the actual named RTL modules and interfaces: (1) host vs FPGA boundary, (2) FPGA's control, compute, memory, and data links, (3) nested PE compute datapath with one-neuron timing trace, (4) model reload and neuron/layer FSM sequence. Mark each gate *Planned*, *Simulated*, *Synthesised* or *Board Verified*.

# FPGA Configurable Neural Accelerator

**Reusable, application-independent INT8 neural-network accelerator IP** targeting the Digilent **Arty A7-35T (XC7A35T-1L)**. This repository is dedicated to **RTL architecture, correctness, FPGA implementation, interface verification and reproducible performance assessment**.

## Overview

| Feature | Implementation |
|---|---|
| Model format | Runtime-configurable dense multilayer neural network (MLP) |
| Maximum topology | 32 inputs → 32 → 32 → 32 → 8 outputs |
| Computational neurons / weights at maximum | 104 / 3,328 |
| Arithmetic | Signed INT8 weights/activations, INT32 accumulated products/bias |
| Physical compute | Eight reused multiplier lanes and pipelined reduction/activation |
| Weight memory | Eight synchronous RAM banks, mapped to RAMB18 in prior Vivado implementation |
| Host protocol | 115200 baud USB-UART with command/reply and XOR detection |
| PC tool | Interactive Tkinter input GUI, reference model and board-level benchmark |
| FPGA | Arty A7-35T with 100 MHz oscillator |

This is an **inference engine**, not a neural-network trainer. The shipped test weights are deterministic arithmetic test fixtures; they do not imply classification accuracy. The host can update supported topology, INT8 weights, INT32 biases and inputs at runtime without rebuilding the bitstream.

## Verification evidence so far

- Automated Python-reference vs RTL simulations for **4→8→4→2**, **8→16→8→2** and **32→32→32→32→8**, with directed and seeded input vectors.
- UART bit-level simulation covers framed packets, weight/bias/model configuration, inference, checksum rejection and reply. CI tests also check Python protocol and source hierarchy.
- **User-reported physical Arty A7 smoke test:** PC UART ping, 272-weight load and one **8→16→8→2** inference matching Python scores and class.
- **User-provided routed Vivado implementation reports:** setup slack **+1.437 ns** at 100 MHz, hold slack **+0.036 ns**, **0 failing setup/hold endpoints**; **1,235 LUT**, **1,581 FF**, **8 RAMB18**, **12 DSP48E1**. These are measurements/reports from one build, not a guarantee for other placements or variants.
- Remaining methodology advisories for DSP and RAM pipelining plus unconstrained asynchronous/signal-display I/O require review; physical power has not been measured.

See [industrial verification plan](docs/INDUSTRIAL_VERIFICATION.md) and [release acceptance checklist](docs/RELEASE_ACCEPTANCE.md). This repository does **not** claim certification, MLPerf compliance or production-readiness.

## Reproduce simulation

Linux/WSL with Python 3 and Icarus Verilog:

```bash
bash scripts/test.sh
python3 scripts/check_structure.py
```

## Vivado 2025.2 — complete UART/NPU project

From project root in Tcl Console:

```tcl
source vivado/create_uart_npu_project.tcl
open_project build/uart_npu_project/uart_npu.xpr
```

Or batch flow:

```tcl
source vivado/build_uart_npu.tcl
```

Generated project, checkpoints, bitstreams and timing/utilisation reports stay beneath ignored `build/`. The original smaller 4→2 board top remains available independently.

## Hardware UART and GUI

With the **integrated UART/NPU bitstream** programmed on the Arty A7:

```powershell
py -m pip install -r host/requirements.txt
py host/smoke_uart.py --port COM4 --model 8
py host/gui.py
```

Use the real Windows COM port. GUI controls drive signed INT8 features, not physical sensors; outputs are mathematical classes for the selected test weights.

## Reproducible physical FPGA benchmark

```powershell
py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5
```

This loads all three model sizes, compares every FPGA score against the independent Python reference, and writes per-transaction CSV and aggregate JSON under `build/benchmarks/`. It reports p50/p95/p99 **PC–UART–FPGA round-trip latency**, model load time and observed single-stream transaction rate.

**It does not claim intrinsic accelerator inference cycles or device power.** To measure those, a clock-cycle counter or trigger signal in FPGA RTL and external measurement instrumentation must be added.

## Repository guides

- [Architecture and fixed-point model contract](docs/SCALABLE_NPU_V0_3.md)
- [UART/GUI/Vivado integration](docs/UART_GUI_INTEGRATION.md)
- [Industrial verification and benchmark plan](docs/INDUSTRIAL_VERIFICATION.md)
- [Release evidence and acceptance criteria](docs/RELEASE_ACCEPTANCE.md)
- [Timing optimisation rationale](docs/PIPELINED_NEURON_TIMING.md)

All source code is in `rtl/`; no duplicate generated Vivado project is committed.

# FPGA Configurable Neural Accelerator

Clean-room FPGA Edge AI project for Digilent **Arty A7-35T**. The long-term target is a **runtime-configurable INT8 multilayer NPU with a Python GUI**. This repository tracks verified milestones rather than claiming unfinished features.

## V0.1 — baseline under hardware validation

A 4-input / 2-output signed INT8 dense classifier with one time-multiplexed multiplier, signed INT32 output scores and idle-state weight writes. One source of truth exists for all RTL: `rtl/`. The Arty demo uses four slide switches (each represents either 0 or +8), BTN0 to start, BTN1 for reset and four user LEDs (class 0, class 1, result seen, busy).

```text
rtl/           npu_core.sv, arty_a7_top.sv
tb/            directed and deterministic extended RTL regressions
constraints/   arty_a7_35t.xdc
vivado/        create_project.tcl (GUI .xpr), build.tcl (batch timing/bitstream)
scripts/       test.sh, check_structure.py
docs/          ARCHITECTURE.md, ROADMAP.md
.github/       workflow running both simulations + structure guard
```

## Test in WSL / Linux

Requires `iverilog` and `vvp`.

```bash
bash scripts/test.sh
python3 scripts/check_structure.py
```

Includes known-answer tests, signed extremes, runtime weight changes, latched-input checks, valid/busy protocol checks and 128 deterministic pseudo-random inputs.

## Open the complete Vivado project in GUI

From the repository root, in a terminal with Vivado on PATH:

```bash
vivado -mode batch -source vivado/create_project.tcl
```

Then open **`build/vivado_project/neural_accelerator.xpr`** using Vivado. This generated .xpr includes the RTL hierarchy and pin/timing constraints. It is not checked in because it is reproducibly generated; the generated project can be explored in Vivado and built with its normal GUI flow.

## Fully scripted implementation

```bash
vivado -mode batch -source vivado/build.tcl
```

Target part: `xc7a35ticsg324-1L`. Outputs including `timing_summary.rpt`, `utilization.rpt`, `drc.rpt` and `arty_a7_npu.bit` are written under ignored `build/`.

**Status**: CI simulation and source-hierarchy checks are automated. Hardware timing closure, bitstream and board behaviour must still be checked on the real target; they are not yet validated here.

## Roadmap

See [Architecture](docs/ARCHITECTURE.md) and [Roadmap](docs/ROADMAP.md). Multi-lane MAC, BRAM-backed layer scheduling, runtime model loading, UART, GUI and performance benchmarking are subsequent separately verified stages.

The prior experiment is retained in the archive branch. Its timing/performance reports are **not** evidence for this rebuild.


## New configurable multilayer accelerator — V0.2 experimental

In addition to the existing 4→2 Arty board demonstration, `rtl/mlp_engine.sv` implements up to three dense layers with configurable widths up to eight, signed INT8 multiply/activations, INT32 accumulation, hidden-layer ReLU and output saturation. Example **4→8→4→2** has 14 computational neurons and 72 weights. `LANES=1,4,8` chooses the compile-time MAC parallelism.

The MLP core has its own testbench and has passed GitHub CI with 64 deterministic **independent Python reference vectors per lane** plus directed topology-change cases. Run `bash scripts/test.sh`. See [MLP architecture and validation](docs/MLP_V0_2.md).

For standalone 1/4/8 synthesis exploration, run `vivado -mode batch -source vivado/synth_mlp.tcl`. **This new MLP is not yet part of the Arty board top**, and no DSP/BRAM mapping, routed 100 MHz timing, UART integration or PC GUI has yet been verified for this subsystem.

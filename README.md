# FPGA Configurable Neural Accelerator

A clean-room rebuild of an INT8 FPGA inference accelerator, targeting the Digilent Arty A7-35T. The project is designed to grow into a **runtime-configurable multilayer NPU with a PC GUI**, while keeping one source of truth for every RTL module.

## Current state — clean baseline (v0.1)

The first baseline is a **two-output, four-feature dense classifier** using signed INT8 weights and inputs, signed 32-bit accumulators, and one time-multiplexed multiplier. Weights can be changed through a write port; the board demo initially uses the default weights. This is **not yet** a complete runtime-loaded multilayer accelerator, a UART-based demonstration, or a measured 100 MHz hardware success.

### Repository layout

```text
rtl/
  npu_core.sv          # sole authoritative inference RTL
  arty_a7_top.sv       # physical board top, button + switches + LEDs
tb/
  tb_npu_core.sv       # deterministic self-checking simulation
constraints/
  arty_a7_35t.xdc     # board I/O and 100 MHz timing
vivado/
  build.tcl            # reproducible out-of-tree batch build
scripts/
  test.sh              # Icarus Verilog regression
docs/
  ARCHITECTURE.md      # design boundary and module contract
  ROADMAP.md           # staged industrial-grade deliverables
.github/workflows/
  rtl.yml              # CI simulation and repository structure guard
```

There is **no second RTL directory** and no committed Vivado build products. No empty placeholder folders.

## Quick test

On Linux/WSL with `iverilog` and `vvp` installed:

```bash
bash scripts/test.sh
```

The script compiles the DUT/testbench and checks three classifications, including a runtime weight update.

## Vivado batch build

Open a terminal with Xilinx Vivado on PATH, then from the repository root:

```bash
vivado -mode batch -source vivado/build.tcl
```

The script targets `xc7a35ticsg324-1L` and writes reports and the bitstream into ignored `build/`. Verify your physical board part and I/O constraints before programming. A successful build and timing closure must be demonstrated on the user's machine; it is **not asserted** here.

For a GUI and full runtime neural-network configuration, see [Roadmap](docs/ROADMAP.md).

## Board demonstration

After programming, use the four slide switches to choose four binary sensor channels (0 or 8) and press BTN0 to run one inference. LEDs show the winning class, a sticky result-ready indication and the busy flag. BTN0 has synchronisation/edge detection but no mechanical debouncer; press it once per inference. BTN1 resets the system.

## Scope and validation

Current baseline demonstrates integration mechanics; full model compiler, per-layer scaling, UART, GUI, memory architecture, error handling and application-specific datasets are explicit later milestones. Do not reuse metrics from the archived implementation as evidence for this clean design.

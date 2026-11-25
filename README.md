# FPGA Configurable Neural Accelerator

## Bearing model: source-to-FPGA training/export workflow (V0.6)

**The existing Arty A7 FPGA arithmetic and UART are physically verified.** A healthy-vs-damaged *bearing classifier* is **not yet trained** because original measured bearing recordings have not been acquired/processed here. We do not substitute generated feature values for real physical measurements.

New modules in `bearing/` support conservative MATLAB waveform import, eight measured signal features, an official 32-specimen label manifest, grouped-bearing train/validation/test partitioning, small 8→16→8→2 MLP training, integer-exact FPGA weight/bias export, UART model programming and a separate bearing-case GUI. CI tests only synthetic code fixtures, not real bearing performance.

Obtain the official Paderborn dataset and choose a meaningful set of distinct healthy and damaged bearing recordings. Store extracted `.mat` files in `data/bearing/raw/` (Git-ignored). Then:

```powershell
py -m pip install -r bearing/requirements.txt
py -m bearing.convert_mat --input data/bearing/raw --labels bearing/paderborn_labels_official.csv --output build/bearing/features.csv
py -m bearing.train_export --features build/bearing/features.csv --output build/bearing/trained
py -m bearing.gui
```

**The MATLAB reader must be verified on a genuine sample before processing a whole dataset.** If the source uses a different MAT structure it raises an error rather than guessing. The `bearing_model.json` and `held_out_examples.csv` outputs stay under ignored `build/`. Real held-out results must be inspected before calling the model useful.

Documentation: [Bearing application and operating procedure](docs/BEARING_APPLICATION.md).
Source: [Paderborn University Bearing DataCenter](https://mb.uni-paderborn.de/en/kat/research/bearing-datacenter/data-sets-and-download). Raw measurements are CC BY-NC 4.0 and are not redistributed.

---


## Application focus — real bearing-condition monitoring (work in progress)

Our **first targeted application is healthy vs damaged rolling bearings**, not a general electric-motor or IGBT inverter diagnosis system. The existing FPGA GUI still loads *deterministic demonstration weights* and does **not** contain a trained bearing model.

A new reproducible measured-signal preparation pipeline is under `bearing/`: paired synchronous vibration/current data become eight signal features, while preserving source recording and physical bearing ID. Only real labelled experimental recordings will be used for training and validation; synthetic signals appear exclusively in numerical unit tests. The raw Paderborn recordings are independently obtained from the university and must not be committed because of their non-commercial research licence.

See [Bearing condition-monitoring scope, feature definition, data origin and validation protocol](docs/BEARING_APPLICATION.md). Training, quantisation of a trained model and bearing-specific GUI labels are not yet implemented.

---


## V0.4 — UART + scalable NPU + interactive GUI (integration milestone)

The experimental integrated top `arty_a7_uart_npu_top` connects the previously verified 104-neuron-capacity NPU to an 8N1, 115200-baud USB-UART interface. The board accepts runtime weight/bias writes, topology configuration, 32 signed INT8 sensor inputs and returns eight INT8 scores with an argmax class. The FPGA top uses **E3 100 MHz, UART A9/D10, BTN1 reset, four user LEDs**.

A Windows/Python Tkinter GUI lets users choose among 14-, 26-, and 104-neuron networks, load example weights and change sensor inputs with mouse sliders or keyboard-arrow spinboxes before running FPGA inference. The weights are *demonstration values only* — they are not trained sensor-fault models.

**Automated CI:** all pre-existing NPU numeric regressions plus a serial bit-level UART transaction test, integrated top elaboration and host Python protocol tests. **Not yet validated:** integrated Vivado post-route timing/bitstream and real board communication.

### Quick start: integrated Arty A7 design

From project root in Vivado Tcl console:

```tcl
source vivado/create_uart_npu_project.tcl
open_project build/uart_npu_project/uart_npu.xpr
```

Or use `source vivado/build_uart_npu.tcl` for a complete *attempted* synth/place/route/bitstream with reports under `build/uart_npu/`. Do not consider the physical implementation passed until the resulting timing/DRC reports have been checked.

After a successful hardware build and board programming:

```powershell
py -m pip install -r host/requirements.txt
py host/smoke_uart.py --port COM4 --model 8
py host/gui.py
```

Use your actual COM port. See the complete [UART, GUI and Vivado integration guide](docs/UART_GUI_INTEGRATION.md) and [scalable NPU architecture](docs/SCALABLE_NPU_V0_3.md).

---


## V0.3 — Scalable eight-lane INT8 NPU (experimental, simulation-tested)

The new **`rtl/npu_scalable_core.sv`** and **`rtl/npu_weight_bank.sv`** implement a reusable time-multiplexed neural processor with up to 32 inputs, up to three 32-neuron hidden layers and up to eight output neurons. Maximum network: **32 → 32 → 32 → 32 → 8**, requiring 104 computational neurons and 3,328 INT8 weights. Eight reusable multiplication lanes compute one neuron at a time.

Eight synchronous banked weight memories (512 bytes each, with a BRAM inference hint), an INT32 accumulator, bias, shift/saturation, hidden-layer ReLU, activation ping-pong buffers and argmax are implemented. Topology, weights, biases and inputs can be changed between inferences; the current loading interface is parallel RTL writes, **not UART**.

**GitHub simulation:** 48 Python-golden cases across 4→8→4→2, 8→16→8→2 and 32→32→32→32→8 are run as part of `bash scripts/test.sh`. Run `vivado -mode batch -source vivado/synth_scalable.tcl` to inspect DSP/BRAM mapping. See [V0.3 architecture, register contract and limitations](docs/SCALABLE_NPU_V0_3.md).

**Not yet completed:** New core is not integrated into `arty_a7_top`, nor has it completed new Vivado synthesis, routed 100 MHz timing, physical FPGA checks, UART transport or interactive GUI. The existing baseline board top stays unchanged.

---


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

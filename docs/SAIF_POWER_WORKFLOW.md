# Three-phase SAIF activity-aware power evaluation (experimental)

This is the next step after the routed **80 mW vectorless** Vivado result. It is an engineering *estimate refinement*, NOT a physical power measurement, and the Tcl/XSim flow **has not yet been executed on Windows Vivado 2025.2.1**.

## Scope

The testbench `tb/tb_npu_power_activity.sv` drives the existing `npu_scalable_core` at a **100 MHz** simulated clock, with three nonoverlapping windows:

1. **Idle:** 1,000 clocks after reset release, no model writes or inference.
2. **Loading:** programming all 4,096 weight-bank locations and 128 bias slots.
3. **Inference:** 16 maximum-size `32→32→32→32→8` requests with changing inputs.

The testbench has an intentionally matching RTL hierarchy `u_bridge/accelerator`. **Only core-level signal activity is collected.** It does *not* simulate the board UART transport, its 115200 baud framing, Arty regulator losses, or full-chip physical switching. After synthesis and routing, signal names may differ. Matched activity and unmatched-net reports are essential.

The XSim script uses `$stop` simulation markers to start and end each SAIF window. This requires testing in the actual Vivado simulator; CI compiles the HDL but does **not** execute XSim. AMD UG900/UG835 document `open_saif`, `log_saif`, `close_saif` and `read_saif`.

## Stage A — capture actual RTL switching (Vivado Tcl Console)

Download updated `main` and enter its repository root, e.g.:

```tcl
cd {C:/Mohammad/Electronics/FPGA/Projects/FPGA-NN-Accelerator/FPGA-NN-Accelerator-IP-6}
source vivado/run_npu_power_saif.tcl
```

This creates a **simulation-only** project under `build/power_activity/sim_project`; it does not modify either working FPGA bitstream. The script sets `xsim.simulate.custom_tcl` to capture three files:

```text
build/power_activity/idle.saif
build/power_activity/loading.saif
build/power_activity/inference.saif
```

Expected final message: `THREE POWER ACTIVITY WINDOWS COMPLETED`.

If XSim pauses on a `$stop` marker unexpectedly, check the simulator Tcl Console. **Do not report new power figures until the three SAIF files are nonempty and phase-separated.**

## Stage B — annotate the *existing routed* UART/NPU netlist

You previously built the UART demo in **`FPGA-NN-Accelerator-9`**. The new source checkout may have no routed UART project of its own. Set the full path to the actual existing project before running the annotation script:

```tcl
set ::NPU_UART_XPR {C:/Mohammad/Electronics/FPGA/Projects/FPGA-NN-Accelerator/FPGA-NN-Accelerator-9/build/uart_npu_project/uart_npu.xpr}
source vivado/analyze_npu_saif_power.tcl
```

The script opens the `impl_1` routed implementation, measures a fresh vectorless baseline, then independently applies each activity file using `read_saif -strip_path tb_npu_power_activity`. It resets activity before each import to prevent mixing windows.

Expected reports in the **IP-6 checkout**:

```text
build/power_activity/reports/power_vectorless.rpt
build/power_activity/reports/power_idle_saif.rpt
build/power_activity/reports/power_loading_saif.rpt
build/power_activity/reports/power_inference_saif.rpt
build/power_activity/reports/{idle,loading,inference}_unmatched.txt
build/power_activity/reports/activity_{idle,loading,inference}.rpt
```

**Important:** There may be substantial unmatched nets because RTL is transformed at synthesis. Inspect `Design Nets Matched`, `Confidence Level`, unmatched counts and whether useful core state/data registers were annotated. If matching is poor, we must improve hierarchy mapping or use a post-implementation simulation netlist rather than interpreting the estimates as high-confidence.

## Stage C — summarise and review estimates (Windows PowerShell)

From the IP-6 project root:

```powershell
py scripts/summarize_saif_power.py --reports build/power_activity/reports --output build/power_activity/power_phase_summary.json
```

The summary explicitly marks **comparative claims as requiring review**, even when a SAIF file is identified. Do not derive measured joules/inference, physical watts or physical GOPS/W from the reported figures.

## Existing independent evidence

The uploaded **25 November 2026** post-route UART/NPU vectorless report says: **0.080 W total**, **0.018 W dynamic**, **0.062 W static**, **Medium confidence**. Its `Simulation Activity File` is `---` and `Design Nets Matched` is `NA`. The summary is recorded in `docs/results/uart_npu_vectorless_power_2026-11-25.json`; it is a Vivado tool estimate, not a physical meter reading.

The separately implemented IP-consumer design previously estimated approximately 0.078 W; this difference is not a fair isolated UART power delta unless both designs use matched switching and operating assumptions.

For actual measured electrical energy, see [physical rail-measurement protocol](POWER_MEASUREMENT.md).

## Engineering sign-off criteria

- Three correct, nonempty SAIF files, generated from clearly labelled nonoverlapping simulation phases.
- Valid `read_saif` annotation summary and interpreted matched/unmatched coverage.
- Clock 100 MHz, exact routed design/revision and report environmental assumptions logged.
- Separate idle, loading and inference estimates with activity coverage disclosed.
- **No physical power claim unless a calibrated meter has been used**.

The best next improvement if mapping coverage is low is a matching netlist-level simulation and a calibrated board/FPGA rail measurement; neither is automatically supplied by these scripts.

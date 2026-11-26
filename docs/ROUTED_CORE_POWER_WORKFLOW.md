# Post-route neural accelerator power verification (experimental)

## Aim and boundary

The 25-Nov-2026 integrated UART/NPU Arty A7-35T power estimate was **80 mW vectorless**. First RTL SAIF → routed UART analysis gave **99/3664 nets = 2.7%** matched, too little for confident phase comparisons. The subsequent matched **post-synthesis out-of-context NPU** study reported **1471/2771 = 53.1%** nets matched, **High** Vivado overall confidence and the following estimated phase totals: **74 mW idle, 76 mW loading, 78 mW inference**. These values came from a *synthesised, not routed* NPU core.

This new experiment produces a **routed, out-of-context NPU core** with a matching *post-route* functional Verilog netlist and design checkpoint. It feeds the same 100 MHz core stimulus into XSim, captures individual idle/loading/inference SAIF files, and imports them into the **exact routed checkpoint** to estimate placement/routing-sensitive power.

**This is not the complete UART/NPU board implementation** and is not an electrical measurement. It is deliberately separated from the existing verified FPGA bitstream, standalone packaged IP and UART benchmarks. Vivado's device-static power term models the full target FPGA, even for an OOC core.

### Scope of workload

- **Idle:** 1,000 clocks after reset, no model programming or computation.
- **Model loading:** write all 4,096 available INT8 weight slots and 128 INT32 bias addresses.
- **Inference:** 16 consecutive maximal-network (32→32→32→32→8) inference jobs with changing signed INT8 input features.
- **Clock:** constrained and simulated at 100 MHz.
- The model weights are deterministic example data, *not trained industrial inference weights*.

## Reproducible flow

Download updated GitHub `main` into your existing current checkout, or create one clean checkout. There is **no need to rebuild the already verified UART bitstream**.

Use the following in the **Vivado 2025.2.1 Tcl Console** from a *fresh Vivado session*:

```tcl
cd {C:/Mohammad/Electronics/FPGA/Projects/FPGA-NN-Accelerator/FPGA-NN-Accelerator-IP-8}
source vivado/run_npu_routed_power.tcl
```

The three stages can also be executed independently, which is recommended for troubleshooting:

```tcl
source vivado/build_npu_routed_power.tcl
source vivado/simulate_npu_routed_power.tcl
source vivado/analyze_npu_routed_power.tcl
```

The build stage runs `synth_design -mode out_of_context`, `opt_design`, `place_design`, `phys_opt_design`, and `route_design`; exports a **functional** post-route Verilog netlist and routed DCP; and writes route/timing/utilisation reports.

The simulation stage creates a separate Vivado XSim project containing only the *post-route netlist* and existing testbench. It does not compile `rtl/npu_scalable_core.sv` as behavioral RTL. Three phase-boundary `$stop` markers control SAIF recording. **This is functional post-route simulation without SDF**. Glitch and delay-related power may be underestimated.

The analysis stage opens the **matching routed DCP**, applies each phase SAIF with `-strip_path tb_npu_power_activity/u_bridge/accelerator`, and generates three power reports plus a vectorless baseline. The checkpoint, netlist, and SAIF must be from the same run.

The output directory is self-contained:

```text
build/routed_core_power/
├── core_synth.dcp
├── core_routed.dcp
├── core_routed_func.v
├── route_status.rpt
├── timing_routed.rpt
├── utilization_routed.rpt
├── idle.saif
├── loading.saif
├── inference.saif
├── sim_project/
└── reports/
    ├── power_vectorless.rpt
    ├── power_idle_saif.rpt
    ├── power_loading_saif.rpt
    ├── power_inference_saif.rpt
    ├── idle_unmatched.txt
    ├── loading_unmatched.txt
    └── inference_unmatched.txt
```

After **all three** phases have completed in Vivado, run in **PowerShell** from the *same repository*:

```powershell
py scripts/assess_routed_power.py --reports build/routed_core_power/reports
```

It generates `build/routed_core_power/routed_power_assessment.json` and reports matched-net coverage, total/dynamic/static power, confidence, and estimated dynamic differences from idle. It refuses to pass screening if match coverage is unreported or below an explicitly provisional **30% threshold**. That threshold is not an industry standard and no matching percentage alone qualifies power measurements.

## Interpretation and decision criteria

Compare **core OOC post-synthesis against core OOC post-route** as a *methodological study*, not as if they were identical implementations. Use the matching source revision, clock, temperature/voltage assumptions, and activity conditions. Do **not** equate core OOC results to the routed UART/NPU board's 80 mW estimate.

Before including any routed-power values in the technical datasheet, review SAIF coverage, per-resource DSP48E1/BRAM/clock activity, routing status and timing. Power reports use vectorless estimates for unmatched nets. High overall Vivado confidence is necessary but not sufficient.

A further **full integrated UART/NPU post-route simulation** would require realistic 115200-baud UART transactions to be stimulated against its routed netlist; this experiment is limited to the NPU core. A timing/SDF simulation or external electrical measurement is a separate future step. No physical joules/inference or measured GOPS/W is claimed.

## Status

- [x] Independent routed core power pipeline and Python screening tool implemented.
- [x] Automated Python parser/quality-gate tests included in GitHub CI.
- [ ] Local Vivado 2025.2.1 placement/routing of OOC core verified.
- [ ] Local post-route functional XSim simulation and three SAIF windows verified.
- [ ] Local matched SAIF `report_power` and timing reports reviewed.
- [ ] Real electrical measurements performed.

The scripts have **not** been run inside Vivado by the developer; unexpected tool-version/placement constraints must be diagnosed from your actual Tcl output.

Reference: AMD [UG907, Vector (SAIF) Based Power Analysis](https://docs.amd.com/r/2025.1-English/ug907-vivado-power-analysis-optimization/Vector-SAIF-Based-Power-Analysis), [UG900, Post-implementation Simulation](https://docs.amd.com/r/2024.1-English/ug900-vivado-logic-simulation/Running-Post-Synthesis-and-Post-Implementation-Simulations).

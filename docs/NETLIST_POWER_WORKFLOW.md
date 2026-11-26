# NPU core — matched post-synthesis netlist power characterisation

## Why this experiment exists

The previous Vivado 2025.2.1 **RTL-core SAIF → routed UART/NPU implementation** produced only **99 matched nets of 3,664 (~2.7%)**, with tens of thousands of unmatched simulation signals. The phase-specific 73/73/92 mW total estimates (idle/loading/inference) therefore remain **provisional**, not sound evidence of the accelerator's true dynamic or electrical power.

The improved experiment uses **one source-identical post-synthesis functional Verilog netlist and its matching Vivado synthesis checkpoint**, both produced by the same synthesis invocation. The netlist is simulated with the existing three-phase stimulus, and each SAIF is back-annotated onto the *matching* checkpoint. This should avoid most RTL-to-implementation signal-name mismatch; actual match rates must still be checked.

**Crucial distinction:** this is a **core-only, post-synthesis, out-of-context** power estimate for XC7A35T at a 100 MHz specified clock. The device-static part of Vivado's report still describes the **full FPGA device**, not the static consumption uniquely attributable to the NPU. It is NOT the post-route power of the UART board top, a physical rail meter reading, a trained model, or a standalone measurement of FPGA board power. For board-level power, the existing routed UART report remains separately identified.

## One-command workflow (Vivado Tcl Console)

In your **current single GitHub checkout**, from a fresh Vivado session, run:

```tcl
cd {C:/FPGA/NPU}
source vivado/run_npu_netlist_power.tcl
```

Replace the directory with the actual checkout holding the new scripts. Do **not** source these files in PowerShell. The script does **not** rebuild or overwrite the working UART bitstream, packaged IP or UART hardware results.

This performs three stages:

1. `build_npu_netlist_power.tcl`: Vivado syntheses `rtl/npu_scalable_core.sv` and `rtl/npu_weight_bank.sv` as an out-of-context core for `xc7a35ticsg324-1L`. It writes `npu_core_post_synth_func.v` (using `write_verilog -mode funcsim`) and `npu_core_post_synth.dcp` with 100 MHz clock constraints.
2. `simulate_npu_netlist_power.tcl`: a **new XSim project** uses the structural functional Verilog netlist, not the core RTL file, with `tb/tb_npu_power_activity.sv` and Vivado UNISIM simulation primitives. It writes separate `idle.saif`, `loading.saif` and `inference.saif`.
3. `analyze_npu_netlist_power.tcl`: opens the **matching** synthesis checkpoint, imports each SAIF using `-strip_path tb_npu_power_activity/u_bridge/accelerator`, then writes a vectorless baseline and three phase-specific `report_power` outputs, with unmatched-net files.

The simulation stimulus covers 1,000 idle clocks, all 4,096 weight addresses and 128 bias addresses, and 16 maximum-size `32→32→32→32→8` inferences using deterministic but **untrained** weights and varied inputs.

## Outputs

```text
build/netlist_power/
├── npu_core_post_synth_func.v       generated structural UNISIM netlist
├── npu_core_post_synth.dcp          matching NPU synthesis checkpoint
├── utilization_core_synth.rpt
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

Then use **PowerShell** in the same checkout:

```powershell
py scripts/assess_netlist_saif.py --reports build/netlist_power/reports --output build/netlist_power/netlist_power_assessment.json
```

This script refuses to pass a provisional activity-quality screening when fewer than 30% of reported nets match **or** coverage is unreported. **30% is merely a conservative diagnostic screening threshold, not a scientific acceptance standard or Vivado-specific recommendation.** A matching percentage alone is not proof of credible DSP/BRAM clock or control activity. Engineering signoff remains false until the primitive activity and assumptions are reviewed.

## If a stage fails

Run the failed step **only**, after correcting its error:

```tcl
source vivado/build_npu_netlist_power.tcl
source vivado/simulate_npu_netlist_power.tcl
source vivado/analyze_npu_netlist_power.tcl
```

The one-command wrapper simply runs them in order. Check the preceding outputs exist before skipping a stage. For example, if XSim elaboration fails because an UNISIM primitive cannot be resolved, fix the Vivado simulator setup, not the accelerator RTL. If a simulation reports an inference failure, do not use partial SAIF results.

Unlike the previous routed-UART power script, **this core-only flow intentionally compares activity against its own OOC checkpoint**. Do not load these SAIF files into `arty_a7_uart_npu_top` and report the result as if it were the same implementation. A future full-UART gate-level capture would require a separately designed serial traffic testbench and would include UART duty cycle.

## Verification status

- [x] Source scripts and Python quality-gate unit tests added to GitHub.
- [x] Existing core testbench structure used with an unchanged RTL/port contract.
- [x] Vivado **post-synthesis functional netlist** generated in the user IP-8 run.
- [x] XSim functional netlist simulation completed all three phases (user IP-8 run).
- [x] Post-synthesis core SAIF matched **1,471/2,771 nets (53.1%)**, overall High Vivado confidence.
- [x] Phase activity reviewed: BRAM rises in loading, DSP rises in inference; **44–47% of nets remain unannotated**.
- [ ] Physical device power and energy/inference measured.

The **Vivado-specific stages were executed by the user in Vivado 2025.2.1**, not by the GitHub Linux regression. They remain bounded by incomplete net matching and no physical rail measurement. Please return the Tcl Console outputs and `build/netlist_power/netlist_power_assessment.json`, plus the unmatched files. Only then should the final datasheet incorporate improved phase power figures.

## Source references

- [AMD UG900, generating functional Verilog netlists](https://docs.amd.com/r/2025.1-English/ug900-vivado-logic-simulation/Generating-a-Functional-Netlist).
- [AMD UG900, power analysis using Vivado Simulator](https://docs.amd.com/r/2025.1-English/ug900-vivado-logic-simulation/Power-Analysis-Using-Vivado-Simulator).
- [AMD UG835, read_saif](https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/read_saif).

The scripts are experimental until run and inspected in the reference Vivado version. This is an engineering study, not production or safety qualification.


**Latest status:** The post-synthesis IP-8 OOC core activity estimates were **74/76/78 mW** for idle/loading/inference, with 53.1% SAIF net matching and High overall Vivado confidence. The subsequently completed **post-route** IP-9 OOC core method reports 55.4% mapping and the same rounded phase totals. Neither is a physical power measurement. See [canonical datasheet](TECHNICAL_DATASHEET.md).

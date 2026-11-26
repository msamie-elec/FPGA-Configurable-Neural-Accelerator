> **Historical investigation of a superseded failing implementation.** Later corrected implementations met 100 MHz timing; the negative slack here must not be quoted as the final design status. See [Verification Report](VERIFICATION_REPORT.md).

# UART-NPU integrated 100 MHz implementation: first timing investigation

The first integrated Arty A7-35T GUI implementation in Vivado 2025.2.1 **routed but failed setup timing**:

| Metric | Observed |
| --- | --- |
| Clock period | 10.000 ns (100 MHz) |
| Setup WNS | -1.931 ns |
| Setup TNS | -62.496 ns |
| Failing setup endpoints | 234 |
| Hold WHS | +0.015 ns |
| Hold failing endpoints | 0 |
| Placed LUTs / FFs | 1,110 / 1,579 |
| RAMB18 / DSP48E1 | 8 / 12 |
| DRC warnings | 24 DPIP-1 input-pipelining advisories on DSP arithmetic |

**Source of evidence:** user-provided Vivado screenshots and `arty_a7_uart_npu_top_drc_routed.rpt`, `arty_a7_uart_npu_top_utilization_placed.rpt`. Routed timing's **critical startpoint / endpoint details were not supplied**, so no particular RTL arithmetic expression has been established as the cause of the -1.931 ns path.

## Confirmed stale XDC issue

The initial GUI build used `set_false_path -from [get_ports {btn[1]}]`, although integrated RTL exposes scalar `btn_reset`. That produced `[Vivado 12-4739] No valid object(s)`. The source XDC has been corrected to target `btn_reset`. This removes a bad constraint but **does not guarantee improved setup timing**, which is internal to the FPGA.

Avoid marking internal synchronous datapath endpoints as false paths solely to make timing pass. Fix failing RTL path(s) or routing architecture after identifying them.

## Extract the missing setup critical paths from the already-routed GUI

In Vivado open the **implemented** design (not synthesised design), navigate to the source repository's root using `cd`, then run:

```tcl
source vivado/diagnose_uart_timing.tcl
```

This writes `build/uart_npu/timing_diagnostics/critical_setup_paths.rpt`, `timing_summary.rpt`, `hold_paths.rpt`, and `methodology.rpt`. Send the first two reports to the developer, or extract their first 10 failing paths with startpoints, endpoints, path delays and logic levels.

Alternatively, directly from any opened implementation design:

```tcl
report_timing -delay_type max -max_paths 30 -nworst 1 -path_type full_clock_expanded -file critical_setup_paths.rpt
```

## Planned RTL optimisation based on measured paths

- If **accumulation** dominates: add a registered group-sum reduction step and then a single INT32 accumulator addition per clock; rerun numeric golden vectors.
- If **memory/address decode** dominates: register and pipeline bank addresses, simplify mux fanout, preserve synchronous RAM inference.
- If **activation+bias+saturation** dominates: stage bias addition and output quantisation, paying one extra cycle per neuron; verify output equality.
- If **DSP pair sum** dominates: constrain DSP inference to multipliers / explicitly implement a balanced pipelined LUT adder tree, and review DPIP-1 warnings with exact paths.
- If **UART control response** dominates: pipeline or register XOR checksum generation and packet dispatch.

These are conditional candidates, not established root causes.

## Acceptance gates

1. Restore constraints integrity; re-create or refresh project constraints so the stale `btn[1]` reference is gone.
2. Fix actual critical setup paths, preserving RTL numerical correctness and host protocol tests.
3. Run Vivado full place/route at 100 MHz: WNS >= 0; WHS >= 0; inspect unconstrained paths, DRC and methodology.
4. Only then program and test the Arty A7 using `host/smoke_uart.py` and `host/gui.py`.

The existing old 4→2 top and its demonstrated timing closure do not validate the new UART-NPU's timing.

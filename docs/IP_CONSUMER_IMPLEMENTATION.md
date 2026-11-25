# Independent Vivado IP consumer: post-route verification

## Purpose

Assess the `npu_accelerator_ip` as a **reusable Vivado Catalog IP in a separate integrating design**, independent of the already-verified UART demonstration. This is stronger than OOC synthesis alone.

The consumer top `rtl/arty_a7_ip_consumer_top.sv` instantiates the **catalog-generated `npu0`** (from `msamie-elec.github.io:user:npu_accelerator_ip:1.0`), not copied sources. It loads all 4096 weight-memory addresses (8 × 512 × 8 bits), all 128 bias addresses (128 × 32 bits), and continuously runs the maximum **32→32→32→32→8** MLP using evolving deterministic test inputs. All eight score bytes affect registered LED digest logic to limit optimisation of otherwise-unused output paths.

The data is **a deterministic workload fixture, not a trained model**. The constrained consumer uses only CLK100, BTN1 reset and four LEDs on the Arty A7-35T; it is **not** the UART demonstration and its bitfile must not replace the latter.

## Create packaged IP and implement consumer

Use the latest repository checkout, Vivado 2025.2.1, in Tcl Console:

```tcl
source vivado/package_npu_ip.tcl
source vivado/build_ip_consumer_impl.tcl
```

The script creates a separate full Vivado project:
`build/ip_consumer_implementation/npu_ip_impl.xpr`.

The reports are written to `build/ip_consumer_implementation/reports/`:

| File | Evidence |
|---|---|
| `implementation_summary.txt` | FPGA target, 100 MHz slack, DSP and BRAM count |
| `utilization_synth.rpt` | Integrated consumer pre-route hardware |
| `utilization_routed.rpt` | Routed total consumer hardware |
| `utilization_hierarchical.rpt` | Resource attribution for IP and consumer logic |
| `timing_routed.rpt` | Routed setup/hold, unconstrained path checks |
| `critical_setup_paths.rpt` | 30 slowest setup paths |
| `hold_paths.rpt` | Worst hold paths |
| `drc_routed.rpt` | Physical DRC |
| `methodology_routed.rpt` | Vivado methodology advisories |
| `power_estimated.rpt` | Estimated, not measured, FPGA power |
| `npu_consumer_routed.dcp` | Inspectable routed design checkpoint |

The script fails if WNS/WHS are negative or an unexpectedly low DSP/BRAM count suggests the NPU was optimised out. All reports are created even if timing fails. **This flow has not yet been executed in Windows Vivado and must not be advertised as passing until the results are returned.** The script may need adjustment for Vivado tool-specific issues.

## Simulator smoke for consumer control (CI)

```bash
bash scripts/test.sh
```

The software-only consumer test compiles the original IP wrapper via `NPU_CONSUMER_SIM` and checks that two maximum-topology inferences complete without error after full memory programming.

This does not replace the IP's independent **48-golden-vector** functional regression, and neither test replaces post-route timing sign-off.

## Interpretation and limitations

- IP-only OOC synthesis performed previously in Vivado inferred **12 DSP48E1**, **8 RAMB18E1** and 22 RAM64M; consumer design may use additional LUTs/FFs for stimulus generation.
- Post-route slack is that of the *consumer plus IP*, not a standalone ASIC-style macro maximum Fmax.
- Model configuration is selected to maximise hardware participation, not to demonstrate runtime topology changes. Runtime topologies are tested by the existing UART and core regressions.
- Direct LED results are on-chip computation digests, not a classification accuracy metric. Never claim task accuracy from this example.
- IP has **no AXI ports** and is not an AXI4 IP until a genuine adapter is designed/verified.
- On-chip power is a Vivado estimate; test vectors and SAIF/power-meter readings are required for robust energy results.

## Next evidence request

After running, provide `implementation_summary.txt`, `timing_routed.rpt`, `utilization_hierarchical.rpt`, `drc_routed.rpt`, and `methodology_routed.rpt`. Keep the old Arty A7 UART bitstream and previous 300/300 benchmark evidence intact.

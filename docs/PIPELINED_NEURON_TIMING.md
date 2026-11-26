> **Historical debug note (25 Nov 2026).** The negative WNS below describes an earlier superseded RTL implementation. Subsequent UART, consumer and standalone routed-core builds have achieved positive 100 MHz setup/hold slack; see [Verification Report](VERIFICATION_REPORT.md).

# 100 MHz correction — registered neuron post-processing

Vivado's routed timing summary (25 Nov 2026, 17:39:50) identified worst setup slack **-1.931 ns**, with the path:

- Start: `u_bridge/accelerator/neuron_idx_reg[0]_replica_9/C`
- End: `u_bridge/accelerator/peak_value_reg[0]/CE`
- Logic depth: **19 levels**; **11 CARRY4**; route delay **6.718 ns**; logic delay **4.857 ns**

The path traversed bias RAM selection, a 32-bit accumulator+bias addition, signed quantisation, and peak-score update. In V0.5 the `npu_scalable_core` output scheduling introduces:

1. `BIAS_ADD`: register `acc + biases[...]` as a signed INT32 value.
2. `QUANTIZE`: shift, saturate, hidden-layer ReLU, register signed INT8 neuron value.
3. `STORE`: activation write and argmax comparing the registered INT8 value.

This adds **two cycles per computed neuron** and preserves mathematical ordering and signedness; existing Python golden tests must pass for all network sizes and the UART protocol.

**Simulation passing is not evidence of 100 MHz timing closure.** Re-open/recreate the `uart_npu` GUI project from updated sources, rerun synthesis and implementation, check WNS/TNS/WHS and methodology warnings. Routed timing must improve and WNS must be nonnegative for a 100 MHz pass.

The fixed reset XDC refers to `btn_reset`, not the obsolete `btn[1]`. The separately added `vivado/diagnose_uart_timing.tcl` can extract 30 fully detailed paths for follow-up.

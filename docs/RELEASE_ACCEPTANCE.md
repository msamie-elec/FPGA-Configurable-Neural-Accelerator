# Engineering release acceptance — FPGA Configurable Neural Accelerator

**Date:** 26 November 2026 · **Release type:** verified development demonstrator; **not production qualified**.

This checklist distinguishes tests actually completed from requirements whose absence prevents an industrial production claim. The release does **not** warrant that all RTL bugs are absent.

| Acceptance area | Result | Evidence / limitation |
|---|---|---|
| Reproducible source regression | **PASS in GitHub CI** | `scripts/test.sh`, Icarus Verilog and Python; test scope finite |
| Signed fixed-point numerical oracle | **PASS** | 48 Python-golden cases via scalable core and IP wrapper |
| Directed corner cases | **PASS in CI** | `tb/tb_npu_corner_cases.sv`: signed scores, tie, invalid topology, busy writes, reset |
| UART packet and negative cases | **PASS in CI** | `tb/tb_npu_uart_robustness.sv`; no partial-frame timeout without reset |
| Host protocol tests | **PASS in CI** | `tests/test_npu_serial.py`, CLI/GUI parsing |
| IP-XACT packaging/catalog discovery | **Observed PASS in user Vivado** | `vivado/package_npu_ip.tcl`; catalog VLNV `…:npu_accelerator_ip:1.0` |
| Independent IP consumer routed at 100 MHz | **Observed PASS** | WNS +2.006 ns / WHS +0.043 ns; IP 811 LUT, 709 FF, 8 BRAM18, 12 DSP |
| Physical score comparisons | **300/300 archived summary PASS** | `docs/results/arty_a7_benchmark_2026-11-25.json` |
| Larger physical repeatability | **3,000/3,000 reported PASS** | Full raw per-transaction records **not archived** |
| FPGA compute latency | **Measured by FPGA telemetry** | 114 / 250 / 2,394 cycles at 100 MHz; host UART delay separate |
| Power SAIF methodology | **Completed as EDA estimate** | Routed OOC core IP-9 55.4% net match; High overall confidence |
| Routed OOC-core timing / resource review | **Observed PASS** | WNS +2.017 ns, WHS +0.181 ns; 959 LUT, 770 FF, 8 BRAM18, 12 DSP |
| Model-image integrity / atomic update | **NOT IMPLEMENTED** | Integrating application must handle partial programming |
| UART CRC and incomplete-frame timeout | **NOT IMPLEMENTED** | XOR checksum only; incomplete frame can wait indefinitely until reset |
| Physical electrical power and energy/inference | **NOT MEASURED** | No rail meter; do not quote metered GOPS/W |
| Extended stress, EMI, multiple-board environment | **NOT ESTABLISHED** | No field reliability or safety assurance claim |
| Real bearing model accuracy | **NOT ESTABLISHED** | Separate [bearing application repository](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring) |

**Decision:** suitable for publication as **application-independent, hardware-demonstrated FPGA NPU reference IP** provided the known limitations remain visible. **Do not call it production-ready, functionally safe, fault-tolerant, bug-free or trained for bearing failure detection.**

## Reproducibility rules for future runs

Record the exact Git commit, tool versions, reference board/FPGA and hardware revision, intended top/bitstream, bitstream SHA256, constraints, weight-image ID, test seed, number of cases, failures, raw UART transactions, implementation reports, temperature/voltage assumptions and any meter calibration.

Generated artifacts remain under `build/` and are Git-ignored. Selected attributable evidence may be published in `docs/results/`; do not silently turn screenshots or reported totals into fictitious raw-case files.

**Source of truth:** [Technical Datasheet](TECHNICAL_DATASHEET.md) · [Verification Report](VERIFICATION_REPORT.md) · [Start Here](START_HERE.md).

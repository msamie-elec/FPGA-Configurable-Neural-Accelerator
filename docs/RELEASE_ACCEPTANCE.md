# FPGA accelerator release gate and evidence manifest

This document is a **portfolio-ready acceptance checklist**, not a certification statement. Do not mark a gate PASS without archived, reproducible evidence.

| Evidence | Goal | Status | File |
|---|---|---|---|
| Software functional reference | Signed fixed-point outputs match RTL for multiple networks | Existing tests PASS | `bash scripts/test.sh` |
| Full UART regression | Correct programming, packet/checksum/reply | Existing directed tests PASS | `tb/tb_npu_uart_bridge.sv` |
| Host protocol regressions | Encoded requests/replies, errors | Existing tests PASS | `tests/test_npu_serial.py` |\n| UART negative testing | Checksum-corrupt write, invalid commands/topology, reset parser | New simulation regression (CI PASS required); not a physical stress test | `tb/tb_npu_uart_robustness.sv` |\n| Hardware endurance tool | Serialized reference comparisons, reprogramming, durable logs | Tool added; not run on board | `host/reliability_campaign.py` |
| Constrained timing closure | 100 MHz WNS >= 0, WHS >= 0 | UART integration and IP consumer PASS; consumer +2.006/+0.043 ns | Prior uploaded routed timing report |
| FPGA resource metrics | LUT/FF/BRAM/DSP | Routed IP hierarchy: 811 LUT / 709 FF / 8 BRAM18 / 12 DSP | Prior uploaded Vivado reports |
| Physical UART proof | Write model, run inference, Python parity | 3,000/3,000 user-reported hardware comparisons PASS | User hardware test screenshot |
| Benchmark 3 model sizes | 100+ correct inferences each | PASS; 300 detailed JSON, later 3,000/3,000 user-reported | `build/benchmarks/benchmark_summary.json` |
| Stability under repeated load | 1,000+ per topology with reset/reconnect | 1,000+ inference repeatability PASS; physical reset/recovery NOT RUN | docs/RELIABILITY_TESTS.md |
| FPGA dispatch-to-valid cycle timing | Cycle counter over FPGA inference handshake | Hardware telemetry PASS: 114/250/2394 cycles | `--fpga-cycles` benchmark after reprogramming |
| Power & energy | Physical rail measurement, power under activity | PENDING (78 mW Vivado estimate only) | docs/POWER_MEASUREMENT.md |
| Reproducible deliverables | Independent build, GUI and measured results table | Demonstrated; full raw 3,000-case CSVs not archived | docs/START_HERE.md, docs/VERIFICATION_REPORT.md |

**Release definition:** "Verified development demonstrator" can be claimed after reliable hardware multi-model tests and reviewed reports. "Industrial-grade / production-ready" requires further fault robustness, complete constraints, reset/CDC and long-run evidence, plus requirements for the target application. These labels are not interchangeable.

## Evidence capture template

For each run record:
- Date and test operator, Git commit SHA and bitstream SHA256.
- Hardware: Digilent Arty A7-35T, revision, clock, supply configuration.
- Tools: Vivado, Icarus, Python, pyserial versions and host OS.
- Topology, weight-pattern/model identifier, fixed-point shift, random seed.
- Sample count, expected/actual outputs, error logs and UART round-trip latency statistics.
- Vivado reports: routed timing, methodology, DRC, utilization and power estimate.
- Instrument and measurement method if reporting FPGA core latency or electrical power.

Raw build reports/logs belong under ignored `build/` until curated, de-identified examples are deliberately added to a dedicated `docs/results/` location.

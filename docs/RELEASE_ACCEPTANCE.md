# FPGA accelerator release gate and evidence manifest

This document is a **portfolio-ready acceptance checklist**, not a certification statement. Do not mark a gate PASS without archived, reproducible evidence.

| Evidence | Goal | Status | File |
|---|---|---|---|
| Software functional reference | Signed fixed-point outputs match RTL for multiple networks | Existing tests PASS | `bash scripts/test.sh` |
| Full UART regression | Correct programming, packet/checksum/reply | Existing directed tests PASS | `tb/tb_npu_uart_bridge.sv` |
| Host protocol regressions | Encoded requests/replies, errors | Existing tests PASS | `tests/test_npu_serial.py` |
| Constrained timing closure | 100 MHz WNS >= 0, WHS >= 0 | One implementation PASS; +1.437/+0.036 ns | Prior uploaded routed timing report |
| FPGA resource metrics | LUT/FF/BRAM/DSP | Measured one build: 1235/1581/8/12 | Prior uploaded Vivado reports |
| Physical UART proof | Write model, run inference, Python parity | One medium-size example PASS | User hardware test screenshot |
| Benchmark 3 model sizes | 100+ correct inferences each | PENDING hardware run | `build/benchmarks/benchmark_summary.json` |
| Stability under repeated load | 1,000+ cycles, reset/reconnect | PENDING | future soak log |
| Compute-only cycle timing | Register/ILA/counter measured | PENDING RTL instrumentation | future benchmark |
| Power & energy | Physical rail power measurement | PENDING | power lab worksheet |
| Reproducible deliverables | Clean clone, launch GUI, results table | In progress | `README.md`, reports directory |

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

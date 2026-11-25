# FPGA accelerator industrial-completion roadmap

This repository focuses **exclusively on reusable neural-network inference hardware and verification**.

| Stage | Evidence required | Current |
|---|---|---|
| A. Numeric oracle | Signed INT8 reference agreement for small/medium/large MLP | PASS directed+deterministic RTL simulation |
| B. Architecture resources | 8 MAC lanes, banked BRAM, routed 100 MHz timing and DSP counts | PASS one Vivado build (LUT 1235, FF 1581, RAMB18 8, DSP 12, WNS +1.437 ns) |
| C. Serial FPGA demonstration | Real USB-UART programming and valid bit-exact inference | PASS one medium-sized network case |
| D. Hardware benchmark | Three network sizes, 100+ transactions each, per-case CSV and percentiles | BENCHMARK TOOL ADDED; real run pending |
| E. Reliability | Randomized long-run 1,000+ operations, malformed commands and reset/recovery | Pending |
| F. Inference timing | FPGA UART dispatch-to-valid cycle counter and optional benchmark telemetry | Implemented in RTL/host; new bitstream physical measurement pending |
| G. Power methodology | Vivado estimate separated from measured power and energy | Pending |
| H. Portfolio release | Evidence table, architecture, screenshots, limitations, clean clone/rebuild | In progress |

Rebuild: `source vivado/create_uart_npu_project.tcl` or `source vivado/build_uart_npu.tcl`.
Regression: `bash scripts/test.sh`.
Board benchmark: `py host/benchmark_npu.py --port COM4 --model all --count 100`.

See [industrial verification](INDUSTRIAL_VERIFICATION.md) and [release acceptance](RELEASE_ACCEPTANCE.md).

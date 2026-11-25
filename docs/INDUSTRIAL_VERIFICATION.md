# Industrial verification and assessment — FPGA configurable neural accelerator

**Scope:** Reusable, application-independent INT8 MLP inference IP, host protocol and Arty A7 board reference integration. An industrial-grade portfolio should distinguish proof of arithmetic correctness, hardware timing/resources, system-level transport and measured sustained behaviour. Passing a single demo is not full verification.

## 1. Specification and traceable acceptance requirements

| ID | Required behaviour | Evidence / gate |
|---|---|---|
| FUNC-01 | Valid 1–4 computational-layer topologies, final layer 1–8, all other widths 1–32 | Parameter sweeps and bit-exact golden reference |
| FUNC-02 | Signed INT8×INT8, signed INT32 accumulation/bias, right shift, saturate, hidden ReLU, argmax lowest-index tie | Unit tests for negative saturation, zero, sign extension, ties, minimum/maximum inputs |
| FUNC-03 | Runtime programming of weights, biases and topology; no rebuild for supported shapes | Repeat programming and inference across configurations on one bitstream |
| FUNC-04 | One `valid` completion, correct busy/idle protocol, clean reset, no model-memory uninitialised reads | RTL assertions and directed state-machine tests |
| IF-01 | 115200 8N1 frame parsing, reply correctness, XOR error reporting | Bit-level UART TB, host protocol tests |
| IF-02 | Recovery from malformed/partial command, reset during communication, back-to-back host transactions | Fault-injection regression; currently not fully automated |
| TIM-01 | 100 MHz routed setup and hold pass with reviewed constraints and zero unconstrained internal synchronous endpoints | Signed-off `timing_routed.rpt`, methodology and DRC reports |
| RES-01 | DSP, LUT, FF and BRAM resource allocation documented, plus reproducible synthesis seed/script | Utilisation and hierarchical primitive reports |
| HW-01 | All model sizes pass >100 repeated bit-exact FPGA transactions | CSV test evidence, seed, board, firmware/build commit, failures=0 |
| PERF-01 | Report distribution p50/p95/p99 of UART round-trip; separately measure *compute-only cycles* | Host benchmark, then instrumented FPGA cycle counter |
| REL-01 | Long-run repetitions, resets, reconnects and invalid inputs have defined recovery | Soak-test log with elapsed time, error count |
| PWR-01 | Explain Vivado estimate versus instrument-measured power | Report assumptions; optional rail current capture |
| REPRO-01 | A fresh clone builds and tests with documented tool versions | CI and one clean Windows Vivado/WSL reproduction |

Acceptance thresholds for latency/throughput should be **requirements-driven**, not invented. Present the measured performance, then assess against specific application budgets.

## 2. Verification pyramid

### Stage A — Design-time RTL correctness

- Directed self-checks: layer transitions, 1/4/8/32 inputs, signed boundaries, quantisation and saturation, tie-breaking.
- Deterministic pseudorandom vectors from a *separate* Python fixed-point implementation, comparing **all** outputs and class, not merely `valid`.
- Negative tests: invalid dimensions, simultaneous write/start, writes during busy, reset mid-inference, memory programming order.
- UART packet-level state transitions and frame corruption: wrong length, dropped byte, corrupted XOR, unsupported commands and reset. XOR does not provide robust error detection; upgrading to a CRC, versioned commands and receive timeout is a future robustness improvement.
- Track cases, random seeds, version, test names and failure logs. Optional formal properties can establish control invariants; 100% code coverage alone is not proof of correctness.

### Stage B — Synthesis and timing analysis

- Run constrained synthesis and routed implementation, capture `report_timing_summary`, `report_timing`, `report_drc`, `report_methodology`, `report_utilization`, `report_power`.
- Verify clock definition and review asynchronous UART input / pushbutton constraints and output port constraints instead of suppressing meaningful checks.
- Inspect DSP/BRAM mapping and post-route margins. Exercise a range of tool strategies/seeds if timing margin is small; report the **worst** validated seed, not only the best.
- Review RAM/DSP input/output pipeline advisories, and CDC/metastability synchronizer placement.
- Current known one-build reference: +1.437 ns WNS at 100 MHz, +0.036 ns WHS; 1,235 LUTs, 1,581 FFs, 8 RAMB18, 12 DSP48E1 (user-supplied Vivado reports). This does **not** certify unconstrained ports, power or future variants.
- Never confuse unconstrained synthesis timing with routed clock-period closure.

### Stage C — Board-level tests

- Confirm correct Artix-7 part, serial pins, bitstream SHA, 100 MHz oscillator and power/reset conditions.
- Program a known deterministic weight/bias image. Run Python oracle comparisons of output bytes and class for each network.
- Repeat UART communication after board reset, disconnect/reconnect, malformed frames, and runtime configuration switches.
- Run soak tests (e.g. 1,000 or 10,000 inferences per model) with per-transaction CSV; demonstrate **zero mismatches** or document every fault.
- The integrated UART bridge now implements an optional FPGA dispatch-to-valid cycle counter, readable through UART command 0x54. **This new RTL has simulation coverage but is not yet physically tested, synthesised or routed.** Use `--fpga-cycles` only after rebuilding/programming the firmware and rechecking timing. Repeat after warming; sample inputs must be fixed and reproducible.

### Stage D — Performance and design-space evaluation

For `4→8→4→2`, `8→16→8→2`, `32→32→32→32→8` record:
- MAC count: 72, 272 and 3,328 mathematical weight products respectively.
- Host load/program time separately from inference; bytes and transaction counts.
- UART end-to-end p50/p95/p99 ms; observed request throughput (1/mean observed transaction time).
- *Core compute-only cycles* and effective GOPS = `2 × number_of_MACs × inference_per_second / 1e9`, only when compute-only throughput is **actually measured**. Note multiply+add counted as 2 operations and sparse/idle lanes reduce effective utilisation.
- Quantisation accuracy: all scores and class must equal signed INT8/INT32 Python bit-level reference. Neural task accuracy is not evaluated by deterministic reference weights.
- LUT, FF, DSP, BRAM use, implementation WNS/WHS/TNS, estimated versus measured power, power per inference once physical power and event rate are measured.
- Compare architectures only at **identical functionality and clock constraints**. Prior v0.2 1/4/8-lane engine is structurally different from 8-lane v0.3; label comparisons accordingly.

Benchmarking on the host now:

```powershell
py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5
```

Outputs `build/benchmarks/{small,medium,large}_transactions.csv` and `benchmark_summary.json`. These are system-level UART timings, **not** FPGA cycles unless the optional new `--fpga-cycles` firmware telemetry mode is explicitly enabled.

## 3. Objective release-gate scorecard

| Gate | Current status |
|---|---|
| RTL functional comparisons | PASS for existing directed and deterministic tests; broaden for edge/fault cases |
| RTL UART protocol | PASS for checked testbench and host unit tests |
| 100 MHz Artix-7 routed implementation | PASS on user-provided one-build reports, +1.437 ns WNS |
| FPGA–host measured physical arithmetic | PASS for one medium-size example |
| Automated 3-model hardware benchmark | TOOL PROVIDED; results not collected |
| Long-running soak, reset/fault injection | NOT YET PERFORMED |
| FPGA dispatch-to-valid cycle telemetry | RTL/host implementation and simulated UART packet available; physical measurement pending |
| Hardware power instrumentation | NOT YET PERFORMED |
| Product/production qualification | NOT CLAIMED |

## 4. Relevant methodology context

AMD's **UG949** recommends checking clock and I/O constraints, methodology violations and timing paths through routed implementation; see https://docs.amd.com/r/en-US/ug949-vivado-design-methodology and timing analysis in **UG906**. Benchmark principles such as independent accuracy checks and separating latency from energy are also central to MLCommons MLPerf Tiny (https://mlcommons.org/benchmarks/inference-tiny/). **This repository is inspired by those practices; it does not claim formal MLPerf Tiny submission or benchmark compliance.**

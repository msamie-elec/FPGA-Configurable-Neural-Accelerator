# FPGA Configurable Neural Accelerator

**Reusable INT8 multilayer-neural-network FPGA IP + fully working Arty A7 UART/GUI benchmark demonstrator.**

<small>Reference target: Digilent Arty A7-35T (Artix-7 XC7A35T-1L), Vivado 2025.2.1, 100 MHz.</small>

## Choose what you want to run

| | **A. Complete FPGA demo — build, program and benchmark** | **B. Reusable IP — package, integrate and assess** |
|---|---|---|
| Purpose | Test model loading, GUI, UART, inference and physical speed | Reuse NPU in another FPGA design and measure routed resources |
| Top-level module | `arty_a7_uart_npu_top` | `npu_accelerator_ip` (example consumer `arty_a7_ip_consumer_top`) |
| Vivado entry point | `vivado/create_uart_npu_project.tcl` | `vivado/package_npu_ip.tcl` |
| Programming bitstream | **`build/bitstream/arty_a7_uart_npu.bit`** | Different internal consumer `.bit`, **no UART** |
| Python GUI/benchmark | **Yes** | **No** |

**[START HERE — complete build, bitstream selection, commands and troubleshooting](docs/START_HERE.md)**

The most common user error is trying `host/benchmark_npu.py` after programming `arty_a7_ip_consumer_top.bit`. That standalone IP demonstration has no UART receiver and will not answer serial requests. **For all Python GUI/benchmark tests, program `build/bitstream/arty_a7_uart_npu.bit`.**

## Quick start: full UART/NPU board

In **Vivado Tcl Console** from the downloaded repository root:

```tcl
source vivado/create_uart_npu_project.tcl
open_project build/uart_npu_project/uart_npu.xpr
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

Check routed timing, then **program via Vivado Hardware Manager** using `build/bitstream/arty_a7_uart_npu.bit`. The canonical location is generated locally (not included in the ZIP). The [alternative non-project Tcl flow](docs/BITSTREAM_LOCATION.md) is also provided.

In **Windows PowerShell**, replacing COM4 with the actual board port:

```powershell
py -m pip install -r host/requirements.txt
py host/smoke_uart.py --port COM4 --model 8
py host/gui.py
py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5 --fpga-cycles
```

Close the GUI before running the command-line benchmark so only one process owns the COM port. Benchmark results are saved under `build/benchmarks/`.

## Quick start: reusable Vivado IP

In Vivado Tcl Console:

```tcl
source vivado/package_npu_ip.tcl
source vivado/check_npu_ip_catalog.tcl
source vivado/check_npu_ip_consumer.tcl
```

To perform independent **100 MHz post-route IP-consumer assessment**, in a fresh Vivado session:

```tcl
source vivado/package_npu_ip.tcl
source vivado/build_ip_consumer_impl.tcl
```

This produces hierarchical IP/resource, timing, critical-path, DRC, methodology and estimated-power reports under `build/ip_consumer_implementation/reports/`. The IP exposes synchronous parallel input/configuration/status signals, **not AXI**, and can be added to your own Vivado IP Catalog.

[IP port contract and reuse](docs/IP_INTEGRATION.md) · [Independent consumer implementation](docs/IP_CONSUMER_IMPLEMENTATION.md)

## Architecture and capabilities

| Capability | Verified design contract |
|---|---|
| Network | Runtime-configurable dense MLP, up to `32→32→32→32→8` |
| Maximum logical network | 104 computational neurons and 3,328 active weights |
| Arithmetic | Signed INT8 weights/activations; signed INT32 accumulation and bias |
| Physical compute lanes | Eight shared INT8 MAC lanes |
| Activation | Hidden-layer ReLU, saturating signed INT8 output |
| Model storage | Eight synchronous BRAM-oriented weight banks |
| Model programming | Run-time via parallel IP write ports or board UART protocol |
| UI | Python Tkinter with adjustable signed INT8 input features |
| Target | Arty A7-35T (not Arty S7 or Arty A7-100T constraints) |

**The supplied weights are deterministic numerical test fixtures, not a trained industrial classifier.** This repository assesses FPGA architecture, correctness and performance. It is deliberately independent of individual applications.

## Activity-aware FPGA power-analysis workflow (experimental)

[Phase-separated SAIF power assessment — Vivado commands and evidence limits](docs/SAIF_POWER_WORKFLOW.md). In Vivado Tcl Console, from the repository root:

```tcl
source vivado/run_npu_power_saif.tcl
set ::NPU_UART_XPR {C:/path/to/your/previous/build/uart_npu_project/uart_npu.xpr}
source vivado/analyze_npu_saif_power.tcl
```

Then in PowerShell: `py scripts/summarize_saif_power.py --reports build/power_activity/reports`. The baseline routed Vivado UART/NPU vectorless estimate is **80 mW total, 18 mW dynamic, 62 mW static**, **Medium confidence**. The new SAIF flow has **not yet been executed in Vivado**; review matched/unmatched nets before comparing phases. This is not a measurement of board power.

## Industrial verification, reliability and power assessment

[Consolidated measured verification report](docs/VERIFICATION_REPORT.md) · [Hardware endurance protocol](docs/RELIABILITY_TESTS.md) · [Power measurement instructions](docs/POWER_MEASUREMENT.md) · [Technical datasheet draft](docs/TECHNICAL_DATASHEET_DRAFT.md)

Run a physical **endurance and repeated model-programming test** on the UART/NPU bitstream (not the IP consumer):

```powershell
py host/reliability_campaign.py --port COM4 --model all --count 1000 --reload-every 250
```

Outputs per-inference JSONL and per-model/overall evidence under `build/reliability/`. It is **not** a physical fault injector. The separate RTL regression adds malformed command, corrupt-weight, invalid-topology and parser-reset tests. For power, Vivado's ~78 mW is only a tool estimate; `scripts/assess_power.py` calculates power/energy **only** from externally measured same-rail voltage/current and measured sustained FPS. Physical power and extended fault recovery remain unverified.

## Verification evidence

- **RTL/CI:** standalone accelerator IP wrapper passed 48 Python-golden simulation cases; UART protocol and controller tests; consumer controller simulation wrote 4,096 weight and 128 bias addresses, then completed two maximum-topology inferences.
- **Physical FPGA UART:** original 300/300 reference comparisons passed; **later 3,000/3,000** user-reported sample run passed (1,000 small, 1,000 medium, 1,000 large). The later test's complete CSV/JSON is not yet archived in GitHub.
- **Compute latency measured on physical Arty A7:** 114, 250 and 2,394 clock cycles at 100 MHz, equivalent to **1.14, 2.50 and 23.94 µs**. Calculated effective **0.126, 0.218, 0.278 GOPS** (two operations per logical MAC).
- **Real UART round trip:** roughly **15–16 ms** typical per inference, including PC/USB/serial overhead; not to be confused with FPGA compute-only time.
- **Reusable Vivado IP:** IP-XACT packaging, IP Catalog discovery, consumer instantiation and out-of-context synthesis passed. Independent consumer implementation previously met 100 MHz: **+2.006 ns setup** and **+0.043 ns hold** slack. Reference packaged-IP hierarchy: **811 LUT, 709 FF, 8 RAMB18, 12 DSP48E1**.
- **Power:** routed Vivado on-chip estimates only; physical board power and energy/inference are not yet measured. Extended reset/recovery and long-duration soak tests remain.

See [benchmark source evidence](docs/results/arty_a7_benchmark_2026-11-25.json), [datasheet draft](docs/TECHNICAL_DATASHEET_DRAFT.md), [verification methodology](docs/INDUSTRIAL_VERIFICATION.md) and [release gates](docs/RELEASE_ACCEPTANCE.md). Results are build-dependent, and this design is a verified development demonstrator, **not a certified production IP**.

## Source tree

```text
rtl/          NPU core, BRAM banks, UART board top, standalone IP and consumer
tb/           Self-checking testbenches
constraints/  Arty A7-35T timing and GPIO constraints
vivado/       GUI/batch builds, IP-XACT packaging, consumer implementation
host/         Python serial driver, GUI, numerical reference and benchmark
scripts/      Software/RTL regression and benchmark analysis
docs/         Guides, datasheet draft, verification criteria and measured evidence
build/        LOCAL generated results only (Git-ignored)
```

To run source regression on Linux/WSL with Icarus Verilog installed:

```bash
bash scripts/test.sh
```

Contributions should preserve exact signed fixed-point results and distinguish simulator, tool-estimated and physically measured results.

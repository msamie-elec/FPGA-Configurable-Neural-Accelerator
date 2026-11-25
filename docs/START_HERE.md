# Start here — build, program, test, package and reuse the NPU

This repository provides **two distinct FPGA designs**, both built from the same numerical accelerator RTL. Choose **one track** according to what you want to do. They generate different bitstreams and must **not** be interchanged.

## Choose your track

| Question | Track A — UART/GUI board demo | Track B — reusable Vivado IP |
|---|---|---|
| Goal | Program Arty A7, run Python GUI and bit-exact tests | Integrate NPU into your own FPGA RTL |
| FPGA top | `arty_a7_uart_npu_top` | `arty_a7_ip_consumer_top` (example) |
| Host connection | USB-UART COM port, 115200 8N1 | No UART or host command interface |
| Project generator | `vivado/create_uart_npu_project.tcl` | `vivado/package_npu_ip.tcl` |
| Build | GUI synth/impl/bitstream or batch `build_uart_npu.tcl` | `build_ip_consumer_impl.tcl` |
| What to program | **`build/bitstream/arty_a7_uart_npu.bit`** | Optional autonomous demo: `.../impl_1/arty_a7_ip_consumer_top.bit` |
| Valid Python commands | `host/smoke_uart.py`, `host/gui.py`, `host/benchmark_npu.py` | **None**: no serial protocol |
| Timing & resources | Integrated UART + NPU | Packaged NPU in a consumer, with hierarchy report |

## Prerequisites

- Windows and AMD/Xilinx **Vivado 2025.2.1** (reference version).
- **Digilent Arty A7-35T** (part `xc7a35ticsg324-1L`). Check your actual board before programming. The provided constraints are not for the Arty S7 or A7-100T.
- Python 3 with `pyserial` for UART tests (`py -m pip install -r host/requirements.txt`).
- Optional WSL/Linux with Python 3 and Icarus Verilog (`iverilog`, `vvp`) for source-only regression.
- Extract GitHub's ZIP into **one project root** containing `rtl/`, `vivado/`, `host/`, `constraints/`, and `README.md`. Use a reasonably short local path. Every `build/` directory is **generated locally**, not present in a GitHub ZIP.

## Track A — UART/GUI demo: full build and physical verification

### A1. Generate a new project in Vivado Tcl Console

In Vivado, **replace the example path with the actual folder you extracted**:

```tcl
cd {C:/FPGA/FPGA-Configurable-Neural-Accelerator}
source vivado/create_uart_npu_project.tcl
open_project build/uart_npu_project/uart_npu.xpr
```

The generated GUI project uses `arty_a7_uart_npu_top` and the `constraints/arty_a7_uart_npu.xdc` clock/pins. Create it in a fresh extracted directory, not on top of another active Vivado project.

### A2. Build the new bitstream

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary
report_utilization
report_drc
```

Check positive setup/hold slack and inspect DRC/methodology warnings. The GUI project's **post-write bitstream hook** publishes the successful implementation to the **one official programming location**:

```text
build/bitstream/arty_a7_uart_npu.bit
build/bitstream/build_info.txt
```

If you have an older GUI project lacking the post-write hook, use `source vivado/publish_existing_gui_bitstream.tcl` after opening the corresponding implemented run. Never blindly copy bitstreams between RTL versions.

**Alternative, not in addition to GUI flow:** in a fresh Vivado session from the repo root, run `source vivado/build_uart_npu.tcl`. That builds without a .xpr and publishes to the **same** canonical location.

### A3. Program the board

Vivado **Hardware Manager → Open Target → Auto Connect → Program Device**. Select **exactly**:

```text
<your project root>/build/bitstream/arty_a7_uart_npu.bit
```

Bitstream generation does *not* program the FPGA automatically. The internal GUI bitstream `build/uart_npu_project/uart_npu.runs/impl_1/arty_a7_uart_npu_top.bit` is a managed implementation artifact; use the canonical path above for programming.

### A4. Smoke test, GUI and hardware benchmark

Open Windows PowerShell at the same repo root, identify the Arty UART port in Windows Device Manager (COM4 is an **example**), and run these **sequentially**; close GUI/other serial tools before starting a benchmark:

```powershell
py -m pip install -r host/requirements.txt
py host/smoke_uart.py --port COM4 --model 8
py host/gui.py
```

For raw FPGA cycles as well as PC round-trip time:

```powershell
py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5 --fpga-cycles
```

For repeatability:

```powershell
py host/benchmark_npu.py --port COM4 --model all --count 1000 --warmup 10 --fpga-cycles
```

`--fpga-cycles` requires a UART/NPU **firmware version implementing command 0x54**. Test fixtures are deterministic arithmetic examples, **not trained fault or application models**. Benchmark outputs are written to `build/benchmarks/benchmark_summary.json` and per-model transaction CSVs.

**What you are measuring:** FPGA dispatch-to-valid clock cycles and signed output scores separately from host/UART transaction milliseconds and model programming time. Do not equate USB serial p95 latency with the NPU's compute latency.

## Track B — package and integrate the NPU as IP

This path **does not build a UART interface**. Its purpose is to prove the accelerator is reusable in another FPGA project.

### B1. Package and check catalog

Start a fresh Vivado session at the project root:

```tcl
cd {C:/FPGA/FPGA-Configurable-Neural-Accelerator}
source vivado/package_npu_ip.tcl
source vivado/check_npu_ip_catalog.tcl
source vivado/check_npu_ip_consumer.tcl
```

Artifacts:

```text
build/ip_repo/npu_accelerator_ip_1_0/component.xml
build/ip_consumer_project/npu_ip_consumer.xpr
```

The packaged VLNV is `msamie-elec.github.io:user:npu_accelerator_ip:1.0`. It has **clock, reset, configuration, memory-write, start, busy, valid, error and result ports**. It is **not AXI/AXI-Lite**.

The consumer catalog check demonstrates the IP can be instantiated and generated as an `.xci`. It does not by itself prove timing.

### B2. Build a separately routed IP consumer

In a fresh Vivado session (or after the first project has closed), run:

```tcl
source vivado/package_npu_ip.tcl
source vivado/build_ip_consumer_impl.tcl
```

The script builds the packaged `npu0` in a representative board consumer at 100 MHz and generates:

```text
build/ip_consumer_implementation/npu_ip_impl.xpr
build/ip_consumer_implementation/reports/implementation_summary.txt
build/ip_consumer_implementation/reports/timing_routed.rpt
build/ip_consumer_implementation/reports/utilization_hierarchical.rpt
build/ip_consumer_implementation/reports/drc_routed.rpt
build/ip_consumer_implementation/reports/methodology_routed.rpt
build/ip_consumer_implementation/reports/power_estimated.rpt
```

**Demonstrated user Vivado result:** 100 MHz routed timing met on the representative consumer. Its hierarchical utilisation report can distinguish `u_npu` from stimulus/LED logic. Additional report files remain under the same reports directory.

### B3. What the autonomous consumer bitstream does

Vivado may produce:

```text
build/ip_consumer_implementation/npu_ip_impl.runs/impl_1/arty_a7_ip_consumer_top.bit
```

This runs an **internal stimulus generator → packaged NPU → LED digest**. It **has no UART RX/TX, no command decoder and no Python GUI connection**. This file can be retained for autonomous board experimentation but must **never** be used with `smoke_uart.py` or `benchmark_npu.py`:

```text
npu_serial.ProtocolError: Expected 13 response bytes; got 0
```

That error is expected if the *wrong* bitstream is programmed: `COM4` cannot reach a UART receiver that is absent from the design. Reprogram **Track A's** canonical bitstream before running the host tests.

### B4. Add the IP to your own FPGA project

```tcl
set_property ip_repo_paths [list {C:/FPGA/FPGA-Configurable-Neural-Accelerator/build/ip_repo}] [current_project]
update_ip_catalog -rebuild
```

Search the IP Catalog for `npu_accelerator_ip`. Connect the defined synchronous interface, initialise all model weights/biases before inference, and constrain the clock and relevant I/O paths in the **consuming project**.

See [IP integration/port contract](IP_INTEGRATION.md) for widths, addresses and operational limitations. Source-driven verification: `bash scripts/test.sh`.

## Extended physical reliability and power checks

Close the GUI, program **Track A UART/NPU** firmware, then run:

```powershell
py host/reliability_campaign.py --port COM4 --model all --count 1000 --reload-every 250 --output build/reliability
```

The tool preserves every comparison and records aborted UART transactions; hardware reset or malformed-wire injection is **not** included. See [reliability protocol](RELIABILITY_TESTS.md), [power measurement instructions](POWER_MEASUREMENT.md) and [consolidated verification report](VERIFICATION_REPORT.md).

## Common troubleshooting

| Symptom | Likely cause / action |
|---|---|
| `couldn't read file vivado/...tcl` | Current directory is not the extracted repository root, or files were nested one level deeper; use `pwd` and `file exists vivado/package_npu_ip.tcl` in Vivado Tcl Console |
| `Expected 13 response bytes; got 0` | No UART bitstream programmed, wrong COM port, busy port, cable/reset issue; check which top module's bitstream was programmed |
| `unknown command` when using `--fpga-cycles` | Outdated UART firmware lacking telemetry command 0x54; program current Track A bitstream |
| UART `PING` works but comparisons fail | Reprogram full model, validate bitstream/host source versions and use exact host reference |
| Unrouted or negative slack | Inspect reports before claiming 100 MHz; do not waive internal synchronous paths to fake closure |
| Vivado Windows long-path warnings | Extract under a shorter path, e.g. `C:/FPGA/NPU/`, or use a drive mapping |
| `build/` absent from GitHub ZIP | Expected: all build artifacts are regenerated from source and intentionally Git-ignored |
| Consumer IP produces only LED output | Expected: it is deliberately **not** the UART/GUI design |

## Provenance and limitations

- Published 25 Nov 2026 benchmark evidence: [300/300 original cases and cycle counts](results/arty_a7_benchmark_2026-11-25.json).
- A later **user-reported 3,000/3,000** physical hardware test also passed across all three topologies (1,000 each, telemetry enabled). Its complete JSON/CSV evidence has **not** yet been committed.
- Prior independent consumer placement and routing met 100 MHz with reported setup/hold slack; engineering reports are not bundled as a generated IP release.
- These tests demonstrate a working **development demonstrator**, not an ISO/IEC-certified product, commercial motor-health model or measured rail power.

Next reading: [industrial verification plan](INDUSTRIAL_VERIFICATION.md), [release acceptance](RELEASE_ACCEPTANCE.md), [bitstream publishing](BITSTREAM_LOCATION.md).

# FPGA Configurable Neural Accelerator

**Reusable signed INT8 multilayer-perceptron FPGA inference IP** with a validated Arty A7-35T UART/GUI demonstration, independent Vivado IP-XACT packaging, reproducible RTL regression and hardware/EDA performance evidence.

**Release classification:** engineering-verified *development demonstrator*, **not** production-certified IP, AXI IP or a trained industrial classifier.  
**Reference device:** Digilent Arty A7-35T / Artix-7 `xc7a35ticsg324-1L`. **Tools:** Vivado 2025.2.1, 100 MHz; Python 3 and optional Icarus Verilog.

[**Complete Technical Datasheet**](docs/TECHNICAL_DATASHEET.md) · [Build/program/test guide](docs/START_HERE.md) · [Engineering verification evidence](docs/VERIFICATION_REPORT.md) · [Release acceptance criteria](docs/RELEASE_ACCEPTANCE.md)

## Planned next application — bearing condition monitoring

**The next intended deployment of this reusable neural inference IP is [FPGA Bearing Condition Monitoring](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring).**

The accelerator remains **standalone and application-neutral**; the companion project supplies vibration and motor-current data processing, eight-feature extraction, external training/INT8 export, bearing-level evaluation and a monitoring GUI. The proposed application uses an **8→16→8→2** network, which fits this accelerator without changing the compute architecture.

```text
Bearing vibration/current → numerical feature extraction → INT8 model export
                                                       |
                                          NPU weights/biases + inputs
                                                       |
                                        Arty A7 accelerator inference
                                                       |
                                   logits / argmax → condition-monitoring GUI
```

**Not yet claimed:** a classifier trained/validated on original Paderborn recordings, field accuracy, measured bearing false-alarm rate, real-time acquisition-chain verification or a finished application deployment. These belong to the [bearing application project](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring), **not** to this reusable-IP verification repository.

## Choose a build — the two FPGA bitstreams are not interchangeable

| | A. UART/GUI reference demonstrator | B. Reusable Vivado IP + autonomous consumer |
|---|---|---|
| Goal | Load models, run Python GUI, measure physical inference and UART | Integrate bare synchronous IP and independently route a consumer |
| Top | `arty_a7_uart_npu_top` | `npu_accelerator_ip` inside `arty_a7_ip_consumer_top` |
| Vivado entry | `vivado/create_uart_npu_project.tcl` | `vivado/package_npu_ip.tcl` |
| Bitstream | **`build/bitstream/arty_a7_uart_npu.bit`** | `build/ip_consumer_implementation/npu_ip_impl.runs/impl_1/arty_a7_ip_consumer_top.bit` |
| UART/host benchmark | **Supported** (115200 8N1) | **Not supported**; no UART transceiver |
| Output | Framed UART scores, argmax, FPGA cycles; GUI | Autonomous LED digest; IP integration evidence |

Programming the autonomous **IP-consumer** bitstream and running `host/benchmark_npu.py` will fail to receive a UART response. That is a **wrong-bitstream selection**, not evidence that the accelerator arithmetic failed. `build/` artifacts are generated **locally**, never distributed as a source ZIP.

### Track A — build and test on an Arty A7-35T

In **Vivado Tcl Console** at the repository root:

```tcl
source vivado/create_uart_npu_project.tcl
open_project build/uart_npu_project/uart_npu.xpr
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary
report_utilization
```

Verify setup/hold constraints and hardware part before programming **`build/bitstream/arty_a7_uart_npu.bit`** via Vivado Hardware Manager. In **Windows PowerShell**, substitute the real serial port for `COM4` and run sequentially:

```powershell
py -m pip install -r host/requirements.txt
py host/smoke_uart.py --port COM4 --model 8
py host/gui.py
py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5 --fpga-cycles
```

Close the GUI and other serial applications before each command-line test. The board must have the **UART/NPU bitstream that supports cycle telemetry opcode 0x54**. See [Start here](docs/START_HERE.md) for the detailed workflow, bitstream publishing and troubleshooting.

### Track B — package and route reusable IP

In a fresh **Vivado Tcl Console** from the repository root:

```tcl
source vivado/package_npu_ip.tcl
source vivado/check_npu_ip_catalog.tcl
source vivado/check_npu_ip_consumer.tcl
```

To run the independent post-route consumer implementation:

```tcl
source vivado/package_npu_ip.tcl
source vivado/build_ip_consumer_impl.tcl
```

The catalog component's VLNV is `msamie-elec.github.io:user:npu_accelerator_ip:1.0`. The native IP exposes **unbundled synchronous control/data ports, not AXI4/AXI4-Lite**. See [IP integration and port contract](docs/IP_INTEGRATION.md) and [consumer implementation](docs/IP_CONSUMER_IMPLEMENTATION.md).

### Offline regression (no hardware)

On Linux/WSL with Python 3 and `iverilog`/`vvp` installed:

```bash
bash scripts/test.sh
```

GitHub Actions runs this RTL/Python suite. It includes 48 independent Python-golden IP vectors, UART/controller and corrupted-command tests, autonomous consumer stimulus, and **signed arithmetic, tie-breaking, invalid-configuration, write-during-busy and reset corner cases**. A passing finite suite does **not** prove absence of all bugs.

## Capabilities and limits

| Topic | Verified contract |
|---|---|
| MLP topology | 1–4 dense computational layers; largest **32→32→32→32→8** |
| Arithmetic | Signed INT8 weights/activations, INT32 accumulation/bias, shared shift and saturating INT8 logits |
| Architecture | Eight shared multiply lanes, registered reduction tree, activation ping-pong buffers |
| Network maximum | 104 computational neurons, **3,328 active weights**, 104 active biases |
| Weight storage | 4,096 programmable bytes in eight BRAM-oriented banks |
| Inference output | Up to 8 logits; lowest-index argmax; hidden-layer ReLU |
| Configuration | Runtime memory programming; no retraining on FPGA |
| Transport | Optional UART demo with simple XOR checksum; **no partial-frame timeout** |
| IP bus | Direct parallel synchronous pins; **no AXI, DMA or CDC bridge included** |
| Model | Deterministic arithmetic test weights; **not trained bearing-fault weights** |

FPGA model memory is **uninitialised after power-up** and must be fully programmed for the selected topology before inference. Integer width, interface timing and protocol limitations are detailed in the [datasheet](docs/TECHNICAL_DATASHEET.md).

## Selected engineering evidence

| Evidence | Result | Qualification |
|---|---|---|
| Archived physical benchmark | **300/300** matches (100/topology) | [Raw summary](docs/results/arty_a7_benchmark_2026-11-25.json) |
| Later physical repeated comparisons | **3,000/3,000 reported** | Terminal evidence; full raw per-case files not committed |
| UART/NPU compute telemetry | **114 / 250 / 2,394 cycles** | Small / medium / maximum at 100 MHz; excludes UART transfer |
| Derived compute latency | **1.14 / 2.50 / 23.94 µs** | FPGA dispatch-to-valid, not PC transaction |
| Useful effective computation | **0.126 / 0.218 / 0.278 GOPS** | Two ops per logical MAC, not peak throughput |
| Independent Vivado IP consumer | **811 LUT / 709 FF / 8 BRAM18 / 12 DSP** | Hierarchical IP instance, not entire consumer |
| Independent consumer 100 MHz timing | WNS **+2.006 ns**; WHS **+0.043 ns** | Routed; separate from UART build |
| Routed OOC core, IP-9 | **959 LUT / 770 FF / 8 BRAM18 / 12 DSP** | WNS +2.017 ns, WHS +0.181 ns |
| Routed-core SAIF matching | **1,471 / 2,653 nets = 55.4%** | High Vivado estimation confidence; unmatched nets remain |
| Routed-core estimated on-chip power | **74 / 76 / 78 mW** | Idle / loading / inference; **EDA estimates**, not metered watts |

The **routed standalone NPU-core power** study uses a matching functional netlist/checkpoint and excludes SDF glitch activity; it is **not** the complete UART board. Its ~59 mW device-static term models the target FPGA as a whole, and physical energy/inference or measured GOPS/W is unknown. See [power study](docs/ROUTED_CORE_POWER_WORKFLOW.md), [source-backed IP-9 values](docs/results/ip9_routed_core_power_2026-11-26.json) and [electrical measurement protocol](docs/POWER_MEASUREMENT.md).

## Repository layout

```text
rtl/           Source RTL and both board top-level implementations
tb/            Self-checking simulation benches and phase stimuli
host/          PySerial transport, GUI, reference and hardware tests
tests/         Python unit/regression tests
constraints/   Arty A7-35T reference XDC (not Arty S7 or A7-100T)
vivado/        Vivado project creation, IP packaging, routing and power flows
scripts/       CI regression, analysis, evidence validation
docs/          Datasheet, architecture, integration, verification and workflows
docs/results/  Selected source-attributed, qualified engineering evidence
build/         LOCAL generated bitstreams/reports only (Git-ignored)
```

**Release policy:** Present this as an **engineering-verified, application-independent FPGA inference demonstrator**. Do not claim production robustness, field failure rate, physical device power, certified safety, AXI compliance, or trained bearing-classification accuracy without additional corresponding evidence.

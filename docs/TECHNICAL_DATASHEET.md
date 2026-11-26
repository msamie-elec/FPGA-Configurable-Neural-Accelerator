# Configurable INT8 FPGA Neural Accelerator — Technical Datasheet

**Engineering release:** 1.0 reference design · **Evidence cut-off:** 26 November 2026  
**Maturity:** hardware-tested development IP / reusable Vivado IP-XACT package; **not production-qualified, safety-certified or a trained application model**  
**RTL source:** [`rtl/npu_scalable_core.sv`](../rtl/npu_scalable_core.sv), [`rtl/npu_weight_bank.sv`](../rtl/npu_weight_bank.sv)  
**Reusable wrapper:** [`rtl/npu_accelerator_ip.sv`](../rtl/npu_accelerator_ip.sv)  
**Reference platform:** Digilent Arty A7-35T, Artix-7 `xc7a35ticsg324-1L`, nominal 100 MHz; AMD Vivado 2025.2.1.

> **Scope:** This is an **inference compute IP** and its demonstration system. It does not train a neural network, detect bearing faults without a separately trained model, provide AXI, guarantee fault tolerance, or measure FPGA electrical power.

## 1. Overview and application context

A runtime-configurable, batch-one, fully connected multilayer perceptron (MLP) engine uses **eight shared signed INT8 multiplication lanes**. A layer/neuron/input-group FSM reuses the lanes across successive neurons and layers, reducing physical compute replication. The architecture includes signed arithmetic, pipeline registers, 8-bank synchronous weight memory, signed INT32 biases, ping-pong activation registers and classification output.

The reusable IP is **application-independent**. Its next intended system integration is [**FPGA Bearing Condition Monitoring**](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring), a separate repository that owns vibration/current data processing, feature extraction, training, quantisation, assessment and application GUI. The expected application architecture is:

```text
Bearing vibration + motor-current recordings
        |
Windowing + eight-feature extraction (application repository)
        |
Trained, validated and quantised 8 → 16 → 8 → 2 MLP
        |
Model weights/biases loaded into reusable NPU
        |
FPGA INT8 inference scores + argmax
        |
Application interpretation / user interface
```

**Deployment status:** intended next application, **not a completed validated bearing classifier**. The companion application currently uses software fixtures and does not include a classifier trained and validated on the original measured Paderborn recordings; test specimens, held-out bearing-level evaluation, false-alarm assessment and export-to-FPGA parity are separate acceptance gates.

## 2. Functional specification

| Property | Value / rule |
|---|---|
| Network family | Dense feed-forward MLP, **1–4 computational layers**, batch 1 |
| Inputs | 1–32 signed INT8 features |
| Hidden widths | 1–32 neurons per active hidden layer |
| Final width | **1–8 signed INT8 output logits** |
| Largest tested network | **32→32→32→32→8** (four computational layers) |
| Maximum active weights | **3,328**, for the largest tested network |
| Maximum neurons / biases | **104** / 104 active biases for largest network |
| Physical arithmetic lanes | Eight shared signed **INT8 × INT8** multipliers, one neuron processed sequentially |
| Arithmetic datapath | Registered 16-bit products, tree sums, signed **32-bit** accumulator and bias add |
| Quantisation | Arithmetic right shift `shift` = 0–15, then signed INT8 saturation to −128…127 |
| Hidden nonlinearity | ReLU after quantisation, **hidden layers only** |
| Final scores | Signed INT8, no softmax/probabilities; unused output byte lanes zeroed at a new inference |
| Class selection | Argmax of final logits, **lowest index on ties** |
| Programmed memories | 4,096 8-bit weights (8 × 512); 128 32-bit biases |
| Update policy | Weight/bias writes accepted only when NPU is idle; no atomic model image/version check |
| Reset | Resets control/datapath; **does not initialise model weights/biases** |
| Clock | One positive-edge synchronous clock; target 100 MHz |
| AXI / bus / DMA | **Not implemented**. Direct parallel command/status ports; board UART wrapper is separate |
| Floating point / CNN / training | Not implemented |

The signed 32-bit accumulation and bias arithmetic has **finite width**. Overflow outside the representable INT32 range is not handled by a separate accumulator saturation stage. Any deployed model must be quantisation-calibrated so its intermediate sums are within range; the signed INT8 saturation applies **after the final arithmetic right shift**. Final logits are **not calibrated probabilities**.

### 2.1 Memory map

**Weight byte address (12 bits):**

```text
weight_addr = layer_index × 1024 + neuron_index × 32 + input_index
layer_index: 0..3; neuron_index: 0..31; input_index: 0..31
bank = weight_addr % 8
row  = weight_addr // 8
```

Each bank stores 512 × 8 bits with synchronous read. **Bias address (7 bits)** is `layer_index × 32 + neuron_index`, stored as signed INT32. All *used* weights and biases for the configured network must be programmed after each FPGA configuration/power-up; unused memory addresses need not be initialised for correct selected-topology execution. Memory contents after reset are not guaranteed across FPGA power cycles.

### 2.2 External parallel IP interface

The packaged design is `npu_accelerator_ip`, catalog VLNV `msamie-elec.github.io:user:npu_accelerator_ip:1.0`.

| Port(s) | Direction | Width | Meaning |
|---|---|---:|---|
| `clk`, `rst` | Input | 1 each | Positive-edge 100 MHz clock; synchronous active-high control reset |
| `start` | Input | 1 | One-cycle inference request when idle, with write strobes low |
| `features` | Input | 256 | 32 × signed INT8, feature 0 in bits 7:0 |
| `layer_count` | Input | 3 | Number of computational layers, 1–4 |
| `input_size` | Input | 6 | Input width, 1–32 |
| `size0…size3` | Input | 6 each | Widths of active computational layers; last active width ≤ 8 |
| `shift` | Input | 4 | Shared arithmetic right shift, 0–15 |
| `weight_we`, `weight_addr`, `weight_data` | Input | 1 / 12 / 8 | Weight programming; idle only |
| `bias_we`, `bias_addr`, `bias_data` | Input | 1 / 7 / 32 | Bias programming; idle only |
| `busy` | Output | 1 | Computation in progress |
| `valid` | Output | 1 | One-cycle completion pulse (success or rejected configuration) |
| `error` | Output | 1 | Topology validation failure; check with `valid` |
| `predicted_class` | Output | 3 | Lowest-index argmax; meaningful on successful `valid` |
| `outputs` | Output | 64 | Eight signed INT8 logits, score 0 in bits 7:0 |

Model/configuration writes should be performed while idle with `start=0`; retain the output until completion. The core validates network dimensions on `start`, but **does not check that all required weights have been programmed**. Higher-level software must enforce model-image completeness and input/model consistency.

### 2.3 UART reference demonstrator (not part of IP)

Reference board top: `arty_a7_uart_npu_top`. Serial link: 115200 baud, 8N1. Request framing: `A5 | CMD | payload | XOR(CMD,payload)`. Response: `5A | CMD | STATUS | CLASS | 8 signed score bytes | XOR(CMD,STATUS,CLASS,scores)`, 13 bytes total.

| Opcode | Payload | Purpose |
|---|---:|---|
| `W` / 0x57 | 3 bytes | Write INT8 weight address and value |
| `B` / 0x42 | 5 bytes | Write INT32 bias |
| `C` / 0x43 | 7 bytes | Configure topology and shift |
| `I` / 0x49 | 32 bytes | Dispatch inference |
| `P` / 0x50 | 0 | Ping |
| `T` / 0x54 | 0 | Read previous inference dispatch-to-valid cycles (first four score bytes, little-endian) |

The host must **await each full response before sending another command**. Status: 0 OK, 1 checksum mismatch, 2 unknown command, 3 NPU configuration error. The checksum is only **bytewise XOR, not a CRC**; no incomplete-packet timeout or end-to-end model-integrity validation is implemented. This is a demonstration transport, not a robust industrial fieldbus.

## 3. FPGA implementation evidence

Reported implementation targets and boundaries are **different designs**. Resource totals must not be interchanged or added.

| Implementation | LUT | FF | BRAM18 | DSP48E1 | Timing evidence |
|---|---:|---:|---:|---:|---|
| Packaged NPU **hierarchical IP instance** inside independent routed consumer | 811 | 709 | 8 | 12 | Consumer setup WNS **+2.006 ns**, hold WHS **+0.043 ns** at 100 MHz |
| Entire independent IP consumer (stimulus + LEDs + NPU) | 862 | 1,025 | 8 | 12 | Same routed consumer timing |
| **OOC routed NPU core** for power assessment (IP-9) | 959 | 770 | 8 | 12 | Setup WNS **+2.017 ns**, hold WHS **+0.181 ns**, fully routed 1,436/1,436 routable nets |
| Earlier UART/NPU board-top build (different wrapper) | ~1,276 | ~1,645 | 8 | 12 | Prior routed 100 MHz setup/hold closure; approximate utilisation from separate run |

**Why resource counts differ:** wrapper logic, hierarchy, project context and synthesis/optimisation options differ. The core OOC result is *not* a whole-board bitstream. The independent consumer uses the packaged Vivado IP-XACT component; the UART build uses the equivalent RTL engine behind a serial bridge.

The reported 100 MHz closure is for the stated designs and tool/settings. **No statistically validated Fmax across implementation seeds, device speed grades or temperature corners** is claimed.

## 4. Observed physical-Arty benchmark

From the archived [25 November 2026 300-transaction user hardware summary](results/arty_a7_benchmark_2026-11-25.json) on an Arty A7-35T, 100 MHz UART/NPU bitstream:

| Metric | Small 4→8→4→2 | Medium 8→16→8→2 | Maximum 32→32→32→32→8 |
|---|---:|---:|---:|
| Logical MACs | 72 | 272 | 3,328 |
| Successful/checked physical comparisons | 100/100 | 100/100 | 100/100 |
| Reported FPGA dispatch-to-valid cycles | 114 | 250 | 2,394 |
| FPGA dispatch-to-valid time | 1.14 µs | 2.50 µs | 23.94 µs |
| Computed useful throughput at 100 MHz | 0.1263 GOPS | 0.2176 GOPS | 0.2780 GOPS |
| PC/UART mean transaction | 15.915 ms | 15.854 ms | 15.281 ms |
| PC/UART p95 | 16.285 ms | 16.477 ms | 15.774 ms |
| Reported model load | 1.391 s | 4.782 s | 54.925 s |

**Measurement conventions:** FPGA cycles are an on-board UART bridge counter from dispatch to NPU `valid`, not independent oscilloscope measurements of arithmetic-only pipeline delay. Each MAC counts as **two arithmetic operations** for the useful-GOPS calculation. The *theoretical* eight-lane multiply-add capacity at 100 MHz is **1.6 GOPS**, but this is **not measured sustained throughput**. Actual core effective throughput includes memory reads, sequential neuron scheduling and control overhead. The reciprocal core latency assumes non-overlapping jobs without host protocol overhead and is **not** a measured sustained frames-per-second rate.

**Later observation:** a separate user-reported 1,000-per-topology run yielded **3,000/3,000** exact comparisons. Its original per-transaction CSV/JSON and bitstream hash are not yet committed; treat this as supplementary reported evidence, **not 3,000 archived raw test cases**. Neither sample set proves a field failure probability.

## 5. Power characterisation — evidence and limitations

All values below are **Vivado EDA estimates of device on-chip power**, not board input power, instrument readings or application-level joules per inference.

| Distinct experiment | SAIF mapped nets | Idle total / dynamic | Loading total / dynamic | Inference total / dynamic |
|---|---|---|---|---|
| RTL core SAIF into a separately routed **UART/NPU** board top (diagnostic; weak matching) | 99 / 3,664 = **2.7%** | 73 / 11 mW | 73 / 11 mW | 92 / 30 mW |
| Matched **post-synthesis OOC core** checkpoint and netlist (IP-8) | 1,471 / 2,771 = **53.1%** | 74 / 15 mW | 76 / 17 mW | 78 / 19 mW |
| Matched **post-route OOC core** checkpoint and functional netlist (IP-9) | 1,471 / 2,653 = **55.4%** | **74 / 15 mW** | **76 / 17 mW** | **78 / 19 mW** |

IP-9 has **High** Vivado overall estimation confidence. Its reported **~59 mW static component models the entire target FPGA**, even though the NPU design is out-of-context. In the matching routed core experiment, estimated dynamic power increases about **2 mW loading vs idle** and about **4 mW inference vs idle**. BRAM reported dynamic rises 7→9 mW in model loading; DSP reported dynamic rises from rounded 0 mW to 2 mW during inference.

**Do not directly compare total power of these experiments as equivalent circuits.** In IP-9, **44.6% of nets lack direct switching annotation** and the post-route simulation was functional **without SDF timing/glitch simulation**. Rounding to milliwatts can conceal smaller differences between post-synthesis and post-route results. No FPGA supply-rail voltage/current measurement, board-consumption figure, measured energy/inference, measured GOPS/W or deployment temperature sweep is available. See [IP-9 report-derived metrics](results/ip9_routed_core_power_2026-11-26.json), [power workflow](ROUTED_CORE_POWER_WORKFLOW.md) and [measurement limitations](POWER_MEASUREMENT.md).

## 6. Functional verification and known limitations

| Evidence / requirement | Status | Limit |
|---|---|---|
| Reproducible Icarus RTL regression, Python numerical oracle, 48 golden IP vectors | **PASS (GitHub CI)** | Deterministic finite set; not exhaustive verification |
| Directed signed, tie, invalid configuration, busy-write and reset tests | **PASS (GitHub CI)** | Does not cover all protocol or timing interleavings |
| UART packet framing, checksum rejection, command handling, recovery after reset in simulation | **PASS (GitHub CI)** | No live partial-frame timeout; XOR not CRC |
| IP-XACT packaging, catalog discovery and independent consumer integration | **PASS (user Vivado evidence)** | No formal bus/AXI verification |
| Physical board numerical checks, initial | **300/300 PASS** | 100 cases per selected topology |
| Subsequent physical user-reported checks | **3,000/3,000 PASS reported** | Detailed raw files not archived |
| 100 MHz routed UART/consumer/OOC-core timing | **PASS in reported runs** | Different implementation boundaries |
| Activity-aware post-route core power | **COMPLETE AS ESTIMATE** | 55.4% matched, no SDF or physical power |
| Reset under fault, disconnected serial, long-term stress, EMI/thermal/voltage qualification | **NOT ESTABLISHED** | Must test at system level |
| Bearing classification task accuracy | **NOT ESTABLISHED** | Requires real measured data and held-out evaluation |

**Known engineering gaps:** uninitialised model SRAM after configuration; no atomic model-write transaction or model digest; partial-frame UART can hang until reset; no UART message timeout; weak XOR integrity; limited host transport robustness; no AXI, DMA, authenticated loading or multi-clock interface; power from EDA estimation only; integer overflow not separately saturated; no safety certification. Do not use this IP for unattended safety-critical machinery shutdown without system-level validation and appropriate fail-safe design.

## 7. Reproduction and provenance

```text
Track A — full UART FPGA reference demonstrator
  Vivado Tcl: source vivado/create_uart_npu_project.tcl
  Open project: build/uart_npu_project/uart_npu.xpr
  Build synth_1 and impl_1 through write_bitstream
  Program: build/bitstream/arty_a7_uart_npu.bit
  Windows: py host/smoke_uart.py --port COM4 --model 8
           py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5 --fpga-cycles

Track B — packaged reusable IP + autonomous consumer (NO UART)
  Vivado Tcl: source vivado/package_npu_ip.tcl
              source vivado/check_npu_ip_catalog.tcl
              source vivado/build_ip_consumer_impl.tcl

Matched routed-core power experiment (OOC NPU, not UART)
  Vivado Tcl: source vivado/run_npu_routed_power.tcl
  Windows:    py scripts/assess_routed_power.py --reports build/routed_core_power/reports

RTL source regressions (Icarus + Python)
  bash scripts/test.sh
```

`build/` is **intentionally excluded from GitHub**; the canonical UART bitstream, synthesis checkpoints and power reports are locally generated. A fresh Vivado implementation can vary by tool version and optimisation. Record Git commit SHA, tool version, design revision, board revision, bitstream hash, constraints and raw reports when reproducing a particular measurement.

For detailed integration instructions see [Start here](START_HERE.md), [IP port contract](IP_INTEGRATION.md), [verification report](VERIFICATION_REPORT.md), [release evidence checklist](RELEASE_ACCEPTANCE.md), [bearing application handoff](BEARING_DEPLOYMENT_HANDOFF.md) and [release notes](RELEASE_NOTES.md).

---
**Next integration:** [FPGA Bearing Condition Monitoring](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring). This link documents the **intended downstream deployment**; it does not establish that a trained bearing model is already running on the FPGA.

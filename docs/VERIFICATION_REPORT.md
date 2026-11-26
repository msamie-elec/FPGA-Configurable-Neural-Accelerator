# FPGA Configurable Neural Accelerator — Verification Report

**Revision:** 26 November 2026 · **Scope:** Arty A7-35T hardware demonstrator, application-independent packaged IP and separate core power studies  
**Verdict:** **Engineering-verified development demonstrator, with explicit limitations**. Not formally proven bug-free, safety-certified, production qualified, trained for a real bearing dataset, or physically power-characterised.

This document records **what was actually exercised**. It distinguishes CI software simulation, reported FPGA implementation, observed physical-board experiments, analytical calculations and EDA estimates. Use the [technical datasheet](TECHNICAL_DATASHEET.md) for the complete interface and numerical specification.

## 1. Tested implementation boundaries

| Track | Top / element | Purpose | What it does **not** establish |
|---|---|---|---|
| **UART/GUI reference board** | `arty_a7_uart_npu_top` | Host-programmable model, 115200-baud frame exchange, FPGA cycle timing, physical score parity | AXI interface, physical-power measurement, industrial UART robustness |
| **IP Catalog integration** | `npu_accelerator_ip` in `arty_a7_ip_consumer_top` | IP-XACT packaging, independent consumer synthesis, 100 MHz timing, hierarchical resources | UART endpoint; application-specific trained classifier |
| **Post-synthesis OOC core** | `npu_scalable_core` | Matching synthesis netlist/SAIF estimates | Post-route timing or board watts |
| **Post-route OOC core** | `npu_scalable_core` | Matched routed core netlist/SAIF, timing/resources/power estimate | Full integrated UART system power or measured electrical watts |

The **UART demo** and **autonomous IP consumer** generate different bitstreams. Programming the latter and using a Python UART host is an invalid test setup; the consumer has no UART RX/TX.

## 2. Functional RTL and software regression

The repository's `bash scripts/test.sh` is executed in GitHub Actions and comprises, among others:

| Test / control | Coverage supplied | Status |
|---|---|---|
| Base arithmetic and random v0.1 tests | Standalone original accelerator arithmetic | **CI PASS** |
| 1/4/8-lane MLP engine | Earlier pipelined/parallel architecture | **CI PASS** |
| Scalable NPU | **48 independent Python-golden cases** across 4→8→4→2, 8→16→8→2 and 32→32→32→32→8; entire logits and class compared | **CI PASS** |
| Reusable IP port wrapper | 48 Python-golden cases via `npu_accelerator_ip` | **CI PASS** |
| Directed external IP edge cases | Signed positive/negative scores, zero/tie lowest-index argmax, illegal dimensions, ignored weight write while busy, reset and persistence of programmed memory | **CI PASS** |
| UART driver, parser and controller | Framing, model programming, checksum/cycle telemetry, valid replies | **CI PASS** |
| UART negative responses | Corrupted weight-write XOR, unknown command, rejected topology with recovery, partial-frame parser reset | **CI PASS** |
| Autonomous IP-consumer stimulus | 4,096 weight slots, 128 bias addresses, two maximum-configuration inferences in RTL simulation | **CI PASS** |
| Host/reference/performance/reporting | Python parsing, benchmark metrics, report quality checks and mocked reliability campaigns | **CI PASS** |

A finite self-checking regression demonstrates coverage of the listed scenarios; it **does not prove absence of undiscovered RTL bugs**. The core is also not a formally model-checked implementation, and there is no assertion of complete branch/corner coverage. Reference fixtures are deterministic and are **not trained industrial models**.

### Important negative-test boundaries

The physical UART link has **no partial-frame receive timeout**, uses a simple XOR checksum rather than a CRC, and does not atomically validate an entire model image. A reset-recovery test is not evidence that truncated frames recover **without** reset. The core does not track whether all active weight/bias locations have been programmed. Design owners must require complete model loading and appropriate system interlocks before treating outputs as meaningful.

## 3. Physical Arty A7 functional and latency evidence

**Archived source:** [`docs/results/arty_a7_benchmark_2026-11-25.json`](results/arty_a7_benchmark_2026-11-25.json). Tested on Arty A7-35T using UART/NPU bitstream with cycle telemetry and an independent Python signed fixed-point oracle.

| Topology | MACs | Exact output/class comparisons | FPGA reported dispatch-to-valid cycles | FPGA equivalent at 100 MHz | Effective useful GOPS |
|---|---:|---:|---:|---:|---:|
| 4→8→4→2 | 72 | **100/100** | 114 | 1.14 µs | 0.1263 |
| 8→16→8→2 | 272 | **100/100** | 250 | 2.50 µs | 0.2176 |
| 32→32→32→32→8 | 3,328 | **100/100** | 2,394 | 23.94 µs | 0.2780 |

The **300/300** cases are present as the archived benchmark summary, not archived per-transaction input/vector files. A subsequent **3,000/3,000 user-reported physical result** (1,000 each topology) was observed with UART p95 **16.284/16.317/15.504 ms**, but the detailed raw logs are **not committed**. The endurance tool has additionally been run successfully for repeated model loading, per user report, but the full event log/summary is not archived. Distinguish these observations from an automated release CI run.

Definitions: the hardware cycle counter starts at UART inference dispatch and stops on accelerator valid. At 100 MHz `microseconds = cycles/100`. Useful GOPS = `2 × logical MACs × 100 MHz / cycles / 1e9`. Typical PC/USB/UART response time is **~15–16 milliseconds**, including transport/host overhead, **not** the FPGA compute time. The ideal reciprocal-of-core latency is analytical, **not measured sustained end-to-end transactions/s**.

No FPGA bitstream SHA256, board serial number, environmental corner sweep or original full 3,000-case transaction archives are included in these published benchmark summaries. The successful sample counts alone cannot establish an operational field failure rate.

## 4. Vivado implementation and timing

| Distinct routed build | Setup WNS | Hold WHS | Mapped resources | Evidence limitation |
|---|---:|---:|---|---|
| Independent packaged-IP **consumer**, 100 MHz | **+2.006 ns** | **+0.043 ns** | IP hierarchy: **811 LUT, 709 FF, 8 BRAM18, 12 DSP48E1**; whole consumer **862 LUT, 1,025 FF, 8 BRAM18, 12 DSP48E1** | Valid for the representative consumer/top only |
| Standalone **OOC routed core** (IP-9), 100 MHz | **+2.017 ns** | **+0.181 ns** | **959 LUT, 770 FF, 8 BRAM18, 12 DSP48E1** | Standalone core implementation; not UART board |
| Prior UART/NPU board build | Positive setup/hold at 100 MHz | Positive | Approx. **1,276 LUT, 1,645 FF, 8 BRAM18, 12 DSP** | Different wrapper and build; no universal macro Fmax |

The IP-9 routed core report recorded **1,436 / 1,436 routable nets fully routed**, with zero routing errors and no failing timing endpoints. Packaging/catalog discovery and independent consumer implementation were executed in user Vivado 2025.2.1; these vendor operations are **not run in Linux CI**. No automatic equivalence check between every generated bitstream and the corresponding source commit hash has been performed.

See the [integration guide](IP_INTEGRATION.md) and [IP consumer report procedure](IP_CONSUMER_IMPLEMENTATION.md).

## 5. Power characterisation

**All figures are EDA-estimated on-chip device power, not electrical measurements.**

| Method | SAIF match | Idle total/dynamic | Loading total/dynamic | Inference total/dynamic | Confidence |
|---|---|---|---|---|---|
| RTL-core activity into independently routed UART system (exploratory) | **99/3,664 (2.7%)** | 73/11 mW | 73/11 mW | 92/30 mW | Medium; **not reliable for quantitative phase comparison** |
| Identical source post-synthesis OOC core netlist/checkpoint | **1,471/2,771 (53.1%)** | 74/15 mW | 76/17 mW | 78/19 mW | High overall Vivado; incomplete mapping |
| **Routed** OOC core matched netlist/checkpoint (IP-9) | **1,471/2,653 (55.4%)** | **74/15 mW** | **76/17 mW** | **78/19 mW** | High overall Vivado; 44.6% unmapped |

In the **IP-9 routed OOC core**, modelled **device-static power ~59 mW** is included in all total figures. It represents the **entire FPGA device**, even though the study isolated an NPU core. The rounded estimates show BRAM switching rising during model loading (7→9 mW) and DSP switching rising during inference (rounded 0→2 mW). This is consistent with workload-dependent switching, **not proof of accurate whole-device activity or electrical energy**.

The post-route simulation was **functional without SDF delay/glitch backannotation** and has **44.6%** unmatched design nets. The older full UART/NPU *vectorless* reference estimate was **80 mW total** (18 mW dynamic / 62 mW static). It is a **different circuit and analysis boundary** from the core-only IP-9 figures.

The [IP-9 source-attributed result](results/ip9_routed_core_power_2026-11-26.json) preserves routed timing, resource and power metrics. External rail measurements, energy per inference and measured GOPS/W remain **unavailable**.

## 6. Industrial readiness / unresolved work

| Area | Position |
|---|---|
| Signed arithmetic, model programming and monitored UART inference | **Verified for tested cases and hardware samples** |
| Reusable Vivado IP packaging and independent consumer timing | **Observed PASS** |
| FPGA core 100 MHz timing and post-route SAIF engineering estimates | **Observed PASS with stated power coverage limits** |
| Truncated UART packet recovery without reset | **Not implemented** |
| CRC, versioned framing, atomic model authentication/image integrity | **Not implemented** |
| Formal equivalence and exhaustive RTL corner checking | **Not performed** |
| Physical reset/reconnection/cable faults, multiple boards, environmental/EMI testing | **Not established** |
| Metered power, true measured joules/inference or GOPS/W | **Not measured** |
| Bearing task-model accuracy, held-out specimen testing and false alarm rates | **Not established** |
| Production or functional-safety certification | **Not claimed** |

## 7. Final assessment and downstream deployment

The repository is technically defensible as a **reusable, hardware-demonstrated INT8 FPGA inference accelerator IP**, provided users follow its memory, interface and transport limitations. It is **not** accurate to describe the current system as a production-qualified, bug-free, fault-tolerant or application-trained industrial bearing classifier.

The next planned deployment is [**FPGA Bearing Condition Monitoring**](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring). The application repository manages actual vibration/current measurements, feature extraction, bearing-level train/test separation, quantisation and the monitoring UI. Its intended 8→16→8→2 network fits this IP. **A bearing classifier running this FPGA bitstream with measured-data validation has not yet been demonstrated.**

**Release references:** [Datasheet](TECHNICAL_DATASHEET.md) · [Release checklist](RELEASE_ACCEPTANCE.md) · [Start here](START_HERE.md) · [Routed core power](ROUTED_CORE_POWER_WORKFLOW.md).

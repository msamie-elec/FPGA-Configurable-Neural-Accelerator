# Configurable INT8 FPGA Neural Accelerator — Technical Datasheet (Engineering Draft)

**Status:** Hardware-verified *demonstrator*; not production-qualified or safety certified.
**IP interface:** Standalone synchronous RTL wrapper, separate from the USB-UART Arty A7 showcase.
**Reference FPGA:** Digilent Arty A7-35T, `xc7a35ticsg324-1L`; Vivado 2025.2.1.

## Function and configuration

| Parameter | Specification |
|---|---|
| Workload | Dense multilayer perceptron inference, batch 1 |
| Topology | 1–4 computational layers, 1–32 inputs, hidden widths 1–32, output width 1–8 |
| Maximum model | 32→32→32→32→8; 104 neurons and 3,328 active weights |
| Number of shared multipliers | 8 parallel signed INT8 lanes |
| Weight storage | 8 × 512 × 8-bit synchronous banks (mapping evidenced by 8 RAMB18 in integrated Vivado implementation) |
| Arithmetic | Signed INT8 weights/activations; signed INT32 accumulation and bias; right shift 0–15; signed saturation |
| Hidden activation | ReLU; output logits signed INT8 |
| Classification | Lowest-index argmax |
| Configuration | Runtime parallel programming port on IP; USB-UART adapter on board demo |
| Model load persistence | SRAM weights/biases must be loaded after power-up and must be treated as undefined until programmed |
| Design clock | Nominal 100 MHz, timing closed on prior UART-integrated design |
| Production AXI support | **None**; not AXI-compliant without additional adapter |

## Device implementation — reference build

The user-supplied prior routed implementation reported 1,276 LUTs, 1,645 FFs, 8 BRAM18 and 12 DSP48E1, with nonnegative setup/hold slack. These are **integrated UART+NPU resources**, not isolated IP-only counts. IP-only utilisation, multiple-place/route statistics and Fmax remain to be measured.

## Physical inference benchmark — 25 November 2026

| Metric | Small 4→8→4→2 | Medium 8→16→8→2 | Large 32→32→32→32→8 |
|---|---:|---:|---:|
| MAC operations | 72 | 272 | 3,328 |
| Measured dispatch-to-valid cycles | 114 | 250 | 2,394 |
| Measured FPGA latency at 100 MHz | 1.14 µs | 2.50 µs | 23.94 µs |
| Calculated effective core GOPS | 0.126 | 0.218 | 0.278 |
| Calculated ideal non-overlap core inferences/s | 877,193 | 400,000 | 41,771 |
| Mean PC/UART transaction | 15.915 ms | 15.854 ms | 15.281 ms |
| Recorded UART p95 | 16.285 ms | 16.477 ms | 15.774 ms |
| Model programming | 1.391 s | 4.782 s | 54.925 s |
| FPGA/Python exact matches | 100/100 | 100/100 | 100/100 |

**Definitions:** FPGA time is a dispatch-to-valid cycle count, not UART transport; one MAC is 2 operations for GOPS. Compute-only inference/s is calculated from cycles and assumes repeated non-overlapping jobs without communication delays. The UART inferences/s are substantially lower (approximately 63–65/s) at 115200 baud.

The raw input to this datasheet is `docs/results/arty_a7_benchmark_2026-11-25.json`. Recalculate with `python3 scripts/analyze_npu_performance.py --input docs/results/arty_a7_benchmark_2026-11-25.json`.

## Power, thermal and reliability boundaries

Previous Vivado routed **on-chip estimated power** approximately 80 mW (18 mW dynamic, 62 mW static; unannotated switching activity and medium confidence). This is *not* physically measured board power. No credible watt-based energy/inference or GOPS/W can be established until power activity/rail measurements are improved.

300 physical inferences produced no score mismatches, but do **not** establish a statistically strong field failure probability, memory error resilience, power-up robustness or safe behaviour under interrupted model programming.

The UART protocol includes a byte XOR checksum; CRC and timeout/recovery hardening remain future work.

## Versioning and reproducibility

- Core RTL: `rtl/npu_scalable_core.sv`, `rtl/npu_weight_bank.sv`.
- Reusable IP wrapper: `rtl/npu_accelerator_ip.sv`.
- Catalog packaging: `vivado/package_npu_ip.tcl`.
- Original physical benchmark: `docs/results/arty_a7_benchmark_2026-11-25.json`.
- Self-checking simulation: `bash scripts/test.sh`.
- Physical benchmark: `py host/benchmark_npu.py --port COM4 --model all --count 100 --warmup 5 --fpga-cycles`.
- Expected benchmark hardware: telemetry-enabled UART/NPU bitstream, not the standalone IP package.
- Canonical programming bitstream: `build/bitstream/arty_a7_uart_npu.bit`.

**Remaining qualification:** packaging/catalog proof, independent IP-only routed utilisation, additional directed and reset/fault tests, multiple-implementation variation, long-duration soak, and measured energy. No claims beyond observed evidence.


## Independent reusable-IP implementation qualification (additional evidence)

- The user-supplied independent consumer Vivado routed design met **100 MHz**, with **+2.006 ns setup slack** and **+0.043 ns hold slack**.
- **NPU hierarchical instance:** **811 LUTs**, **709 FFs**, **8 BRAM18**, **12 DSP48E1**. Whole independent consumer: **862 LUTs**, **1,025 FFs**, **8 BRAM18**, **12 DSP48E1**. These numbers differ from full UART/NPU resources because the two designs contain different wrappers.
- **User-reported follow-up physical comparison:** 3,000/3,000 correct predictions (1,000 per topology), p95 UART times **16.284/16.317/15.504 ms**. The raw 3,000-case JSON/CSVs are not yet archived.
- **Power:** an approximately **78 mW Vivado on-chip estimate**, including ~62 mW static and ~16 mW dynamic, was reported for the independent consumer. This is *not instrument-measured consumption*. Physical energy per inference and GOPS/W remain unreported.
- **Reliability:** a hardware endurance runner and RTL protocol fault tests are now present, but the new campaign has not yet been physically run. The XOR checksum and missing partial-message timeout limit current transport robustness.

The authoritative evidence review and scope are documented in [Verification Report](VERIFICATION_REPORT.md). No claim of an AXI interface, functional safety qualification, or trained model accuracy is made.

## Activity-aware power characterization (pending Vivado validation)

The 25-Nov-2026 routed UART/NPU tool-estimated baseline is **80 mW on-chip** (18 mW dynamic / 62 mW static) with **Medium** confidence and no SAIF. A new experimental three-window RTL SAIF workflow for idle, model loading and sustained compute has been added. It has **not yet produced verified annotated Vivado reports**. The design's physical watts, joules per inference and measured GOPS/W remain unknown. See [three-phase power evaluation](SAIF_POWER_WORKFLOW.md).


## Netlist-activity power verification — in progress

An additional **matched post-synthesis core-only** SAIF workflow has been added to improve upon the earlier 99/3,664 RTL-to-routed match. It runs a structural functional Verilog netlist against a matching synthesis checkpoint, and intentionally does not equate core OOC power with routed UART/FPGA board power. **No successful Vivado netlist simulation, matched annotation or physically measured energy figure has yet been returned.** See [Netlist Power Workflow](NETLIST_POWER_WORKFLOW.md).


## Post-route activity-aware power (pending)

An independent routed-core power experiment is available in `vivado/run_npu_routed_power.tcl`, simulating the **matching routed functional Verilog netlist** for three phase-specific SAIF power estimates. The work is currently **unverified on Vivado 2025.2.1**. No numeric post-route SAIF power is yet approved for publication. This OOC NPU core estimate must not be presented as a measurement of the UART board, and functional simulation excludes SDF glitch activity. See `docs/ROUTED_CORE_POWER_WORKFLOW.md`.

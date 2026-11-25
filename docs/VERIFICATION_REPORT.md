# Independent Verification Report — FPGA Configurable Neural Accelerator

**Engineering evidence review, 25 November 2026.** Status: verified development demonstrator; **not** safety/production qualified.

## 1. System boundaries

Two distinct demonstrators are built from the same accelerator:
- **UART/GUI board top**: arty_a7_uart_npu_top, USB UART 115200 8N1; used for Python model programming, bit-exact physical tests and core-cycle telemetry.
- **Reusable IP consumer**: Vivado packaged npu0 inside arty_a7_ip_consumer_top; internal programmed stimulus and LED digest, with no UART. Used for independent routed timing and IP resource attribution.

Do not run the UART Python benchmark with the autonomous IP-consumer bitstream. That produces an expected serial timeout, not a broken IP.

## 2. Physical FPGA benchmark — traceable source data

Test hardware: Digilent Arty A7-35T, 100 MHz. Numeric oracle: separate signed INT8/INT32 fixed-point Python implementation; deterministic test weights, **not a trained classifier**.

| Network | MACs/inference | Hardware cycles | FPGA µs | Effective GOPS | 25 Nov initial matches |
|---|---:|---:|---:|---:|---:|
| 4→8→4→2 | 72 | 114 | 1.14 | 0.1263 | 100/100 |
| 8→16→8→2 | 272 | 250 | 2.50 | 0.2176 | 100/100 |
| 32→32→32→32→8 | 3,328 | 2,394 | 23.94 | 0.2780 | 100/100 |

Initial benchmark: docs/results/arty_a7_benchmark_2026-11-25.json (inspectable raw measurements).

**Later user-reported repeatability run:** 1,000/1,000 successful results for **each** network, 3,000/3,000 total; measured p95 UART response 16.284, 16.317 and 15.504 ms. This was supplied as a PowerShell screenshot; the original 3,000-case JSON and transaction CSV files have **not** yet been committed. This is a repeatability result, not a statistical lifetime-reliability guarantee.

Compute time: hardware cycle count from UART inference dispatch to NPU valid, including small command-handshake overhead but **excluding** transport. Effective GOPS uses two operations per logical MAC, from that interval. UART mean (~15–16 ms) includes PC, USB, framed UART transfer, reply and FPGA compute; UART limits single-stream transactions to roughly 63–65/s. The core-only reciprocal-of-cycles rate is an analytical nonoverlap ceiling, not measured sustained UART throughput.

## 3. Independent packaged IP — routed implementation

Reported user-provided Vivado 2025.2.1 Artix-7-35T **100 MHz** consumer implementation:
- Setup worst slack: **+2.006 ns**.
- Hold worst slack: **+0.043 ns**.
- Hierarchical NPU IP instance: **811 LUTs**, **709 flip-flops**, **8 RAMB18**, **12 DSP48E1**.
- Total independent consumer: **862 LUTs**, **1,025 FFs**, **8 RAMB18**, **12 DSP48E1**.
- Estimated device on-chip power: **78 mW** (roughly 62 mW static and 16 mW dynamic), **not physical metered power**, medium-confidence Vivado estimate without realistic switching annotation.

This is a routed **consumer+IP** timing proof and a hierarchical utilisation breakdown, not an independently characterised abstract-IP Fmax or an electrical-power measurement. Vivado methodology recommendations and unconstrained LED outputs remain for review.

Earlier UART/NPU build showed approximately **1,276 LUTs, 1,645 FFs, 8 BRAM18, 12 DSP**, with 100 MHz setup and hold closure. The different wrapper/controller account for differing numbers. Use exact report/binary revision when reproducing.

## 4. Functional, negative and integration verification

| Gate | Evidence | Status |
|---|---|---|
| NPU arithmetic | 48 golden RTL reference vectors, signed INT8 arithmetic, topologies | PASS in CI |
| UART framing and model control | Existing UART bit-level TB and host protocol tests | PASS in CI |
| UART error injection | New test: unknown command, corrupted weight checksum, invalid topology and recovery, partial frame reset | **TEST ADDED**; verify CI result |
| FPGA numerical comparisons | 300/300 archived + 3,000/3,000 user-reported | PASS observed |
| IP-XACT packaging, catalog and consumer creation | component.xml, VLNV and npu0.xci generated in user Vivado | PASS |
| Reusable IP OOC synthesis | Prior Vivado synth successful | PASS |
| Independent consumer 100 MHz routed implementation | Above slack and resources | PASS observed |
| Automatic 10k+ hardware soak | New operator-run script; physical evidence not yet collected | PENDING |
| Physical reset-during-inference and serial fault recovery | No physical instrumented run; current RTL has no incomplete-packet timeout | PENDING |
| Power/energy measurement | Tool estimate only; optional meter CSV analyser added | PENDING physical data |
| AXI interface | Not present; NPU exposes native synchronous ports | NOT SUPPORTED |

## 5. New reproducible test suites

### Offline regression (no FPGA required)

~~~bash
bash scripts/test.sh
~~~

Includes RTL corruption/recovery simulation, long-run runner mock tests and power-analysis arithmetic mock tests. These **do not** establish physical error rates or physical rail power.

### Physical endurance / repeated reprogramming

With the **UART/NPU** bitstream, close GUI and other COM port tools:

~~~powershell
py host/reliability_campaign.py --port COM4 --model all --count 1000 --reload-every 250 --output build/reliability
~~~

This records per-case input, oracle scores, actual FPGA scores, class, elapsed UART ms and FPGA cycle counts in JSONL, plus per-model and overall summary JSON. **No automatic reset or malformed packet injection is performed on real hardware.** The campaign aborts on transport exception rather than blindly retrying. To explore longer endurance, raise count; do not report success unless the actual full run completes with zero mismatches and zero transport errors.

### Power

Follow docs/POWER_MEASUREMENT.md. Optional physical electrical readings can be analysed via scripts/assess_power.py; if no readings, physical power, energy and GOPS/W remain **not measured**.

## 6. Remaining engineering risks and evidence requirements

1. **UART lacks partial-packet timeout**; incomplete frames can block parser progress until reset or enough bytes arrive. An isolated reset-recovery simulation is not proof of safe live fault recovery.
2. Framing uses an XOR checksum, weaker than CRC for multi-bit errors; evaluate versioned CRC, timeout and model-write transaction integrity for production use.
3. FPGA model memories are uninitialised until software programmes every active address. Invalid or incomplete model loading requires stronger interlocks before unsupervised operation.
4. The user-submitted repeatability run is evidenced by terminal output only until its full CSV/JSON is archived.
5. No power meter, SAIF activity-annotated estimate, energy/inference or independent matched multi-lane architecture comparison is available.
6. IP port contract is synchronous and unbundled; not AXI or an independently certified functional safety IP.

## 7. Conclusion

The repository demonstrates a working runtime-configurable signed INT8 neural accelerator, physical 100 MHz compute-cycle telemetry, bit-exact UART/FPGA validation, and a reusable Vivado IP passing consumer integration timing. It is suitable to present as a **measured, engineering-verified FPGA IP demonstrator**, with explicit reliability/power and production-readiness limitations. Do not claim commercial safety assurance or trained-model accuracy.

## 8. Added activity-aware power characterization workflow (unexecuted)

The existing uploaded Vivado 2025.2.1 post-route UART/NPU report is a **vectorless** estimate: **0.080 W total on-chip**, **0.018 W dynamic**, **0.062 W device static**, **Medium confidence**, no simulation activity file and no matched activity nets. The reference source is summarized in `docs/results/uart_npu_vectorless_power_2026-11-25.json`.

An experimental **three-phase XSim activity workflow** has now been implemented (see `docs/SAIF_POWER_WORKFLOW.md`): 100 MHz NPU-core idle, 4,096 weight + 128 bias writes, and 16 maximal-network inferences. It creates separate SAIF files and imports each into the matching routed UART/NPU netlist while logging unmatched nets and confidence. **No Vivado SAIF/XSim run result has been returned or validated.** It is wrong to promote estimated power or energy using these scripts until successful SAIF annotation is independently verified. It remains a tool power estimate, not electrical measurement.

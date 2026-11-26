# Engineering roadmap and achieved milestones

**Updated 26 November 2026.** This is a **retrospective status plus future-work list**, not an assertion that all industrial qualification is complete.

| Milestone | Current outcome | Evidence / boundary |
|---|---|---|
| A. Signed INT8 RTL and pipelined MLP | **PASS** | Source RTL + Linux GitHub CI regression |
| B. Runtime-configurable 32-wide NPU | **PASS for tested configurations** | 48 golden cases; eight shared multiplier lanes |
| C. UART GUI and physical Arty A7 integration | **PASS** | UART/NPU reference bitstream, smoke, GUI, physical benchmarks |
| D. Hardware benchmark, three topologies | **PASS** | Archived 300/300 summary; subsequent 3,000/3,000 reported |
| E. Protocol negative tests / endurance | **PARTIAL** | CI corruption/reset tests and user-reported repetitive loading; incomplete-frame timeout and physical stress not done |
| F. Cycle telemetry and useful throughput | **PASS** | 114, 250, 2,394 cycles at 100 MHz; distinguish UART latency |
| G. Vivado catalog IP + independent consumer | **PASS** | User-reported IP-XACT catalog and 100 MHz routed consumer |
| H. Activity-aware power | **PASS as EDA study** | IP-9 routed core 55.4% SAIF match; 74/76/78 mW estimates; no physical wattage |
| I. Datasheet / evidence consolidation | **COMPLETED as engineering documentation** | Canonical [datasheet](TECHNICAL_DATASHEET.md) and [verification record](VERIFICATION_REPORT.md) |
| J. Production and functional-safety qualification | **NOT DONE** | Formal assurance, complete fault handling, environment/EMI, physical power |

## Next intended application: bearing condition monitoring

**Repository:** [FPGA Bearing Condition Monitoring](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring).

The application repo, not this hardware-IP repo, owns the next steps: inspect original Paderborn vibration/current measurements; confirm sensor units/sample rates; extract and verify eight numerical features; train/validate 8→16→8→2 MLP using **bearing-level held-out splits**; calibrate fixed-point INT8 arithmetic; program all active weights/biases; check Python/FPGA score parity; report accuracy and false alarms; and build an operator-facing GUI. **No measured-data bearing classifier accuracy has been established yet.**

## Potential IP hardening after application validation

- Define a model-image integrity check / valid-model flag, an explicit incomplete-UART-frame timeout and CRC versioning.
- Add tests for live disconnect/reconnect, reset during inference, partial model update and overflow at model extremes.
- Extend verification to post-implementation SDF/glitch activity if required by a power budget, and instrument FPGA voltage/current for actual energy/inference.
- Adapt the native interface to a documented AXI4-Lite/AXI-Stream adapter only if the downstream system needs it; do not label current ports as AXI.
- Maintain CI, production requirements traceability and device/board/tool provenance for future releases.

These are **future changes**, not features of the current reference IP.

# Engineering release notes — 26 November 2026

## Release scope

**FPGA Configurable Neural Accelerator** is an application-neutral signed INT8 MLP hardware demonstrator. The reference platform is a Digilent Arty A7-35T running a 100 MHz clock, tested with Vivado 2025.2.1. The user has demonstrated an integrated UART/GUI bitstream, physically measured compute-cycle telemetry, numerical parity, reusable IP-XACT packaging, independent consumer timing and separate post-route routed-core SAIF estimation.

It is **not** a fully field-qualified, safety-certified or physically power-metered NPU product.

## Reproducibility and portfolio entry points

- [Canonical technical datasheet](TECHNICAL_DATASHEET.md): complete numerical and interface contract, benchmarks, resource boundaries and limitations.
- [Start Here](START_HERE.md): UART/GUI demo bitstream selection and separate IP packaging/consumer flow.
- [Verification Report](VERIFICATION_REPORT.md): source-backed evidence and actual remaining gaps.
- [Release Acceptance](RELEASE_ACCEPTANCE.md): pass/partial/not-performed gates.
- [Architecture](ARCHITECTURE.md): current RTL/IP/demonstrator partition.
- [Deployment handoff](BEARING_DEPLOYMENT_HANDOFF.md): contract for next planned condition-monitoring application.

## Confirmed test milestones

1. GitHub RTL/Python regression: golden-model numeric comparisons, protocol fault tests and direct signed/tie/invalid-config/write-busy/reset IP tests.
2. Physical Arty A7 UART/NPU: 300/300 archived initial summary; 3,000/3,000 additional user-reported comparisons (original per-case raw file not archived).
3. Effective compute time: 114/250/2,394 FPGA cycles for the three recorded model sizes.
4. Independent packaged-IP routed consumer: 100 MHz WNS +2.006 ns, WHS +0.043 ns; hierarchical IP uses 811 LUT, 709 FF, 8 BRAM18 and 12 DSP48E1.
5. IP-9 routed OOC core: 100 MHz WNS +2.017 ns, WHS +0.181 ns, no route errors; 959 LUT, 770 FF, 8 BRAM18, 12 DSP48E1.
6. Routed-core **estimated** power: 74/76/78 mW idle/loading/inference; 55.4% SAIF net coverage, High Vivado overall confidence. No physical watts measured.

These figures refer to **different implementation boundaries**; avoid presenting OOC core estimates as integrated board consumption or physically measured energy/inference.

## Remaining limitations

No AXI interface, no UART receive timeout, no CRC or model-image integrity protocol; model RAM is undefined after configuration until loaded. No long-term field failure-rate study, full SDF/glitch power simulation, rail meter data, environmentally qualified operation, ASIC-style IP macro Fmax claim, or trained bearing-classification accuracy. The generated `build/` outputs are intentionally Git-ignored; only selected source-attributed summaries are committed.

## Next planned application

[FPGA Bearing Condition Monitoring](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring) is the **separate next integration target**. It will connect measured vibration/current feature extraction, a trained and externally validated quantised 8→16→8→2 model, UART or direct-IP programming, FPGA inference and a condition-monitoring interface. Actual measured-data validation remains outstanding.

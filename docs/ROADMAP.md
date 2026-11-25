# Rebuild roadmap

The purpose is a reusable FPGA accelerator IP for Edge AI inference, with a sensor-monitoring GUI as an illustrative application, not a sensor-specific architecture.

| Gate | Deliverable | Evidence |
| --- | --- | --- |
| 0 (this commit) | One RTL location, simple 4→2 INT8 core, testbench, A7 board top, Vivado build | CI regression, subsequent user Vivado logs |
| 1 | Board-verified 100 MHz baseline, switch/LED demonstration, resource report | Bitstream, timing summary, board test record |
| 2 | INT8 multi-lane MAC (1/4/8), registered pipeline, fixed-point activation/requantise | Randomised bit-exact tests vs Python |
| 3 | Parameterised MLP, BRAM buffers, runtime model loading/versioned format | Multiple networks without resynthesis |
| 4 | UART packet protocol, checksums/timeouts, board integration | End-to-end stress and malformed-packet tests |
| 5 | Python GUI with adjustable sensor values (mouse/keyboard arrows), plots and diagnostics | Demo recording, PC↔FPGA comparisons |
| 6 | Benchmark and portfolio release | Verified latency, throughput, DSP/BRAM/LUT/FF, timing/power reports; concise reproducible instructions |

### Engineering policies

- Exactly one authoritative file per RTL module; no duplicated source trees.
- Vivado project outputs only under ignored `build/`. Recreate them from scripts.
- Use explicitly versioned interfaces; any architecture change must update tests.
- No empty folders or placeholder READMEs.
- CI checks all committed RTL with an executable test before claims of success.
- Keep the archived implementation for comparison only; do not import unreviewed modules into the new code.

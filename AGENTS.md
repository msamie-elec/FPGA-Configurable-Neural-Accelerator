# Engineering rules for contributors and AI coding agents

- Implement the documented hardware architecture, **not an application-specific classifier**.
- Never add hard-coded demo shape, weights, labels or dataset-specific preprocessing inside reusable RTL.
- Freeze and test signed arithmetic, rounding, saturation, endianness and model descriptor before writing complicated RTL.
- A model is loadable only if the package passes bounds, schema, checksum and numeric checks.
- Keep Python reference independent of generated RTL logic; tests must check all output elements, not only top-class agreement.
- Treat simulation, synthesis, routed timing, physical FPGA tests and demonstrated application accuracy as **different evidence types**.
- Save actual commands, tool versions, source hashes, verified outputs and failing tests; never fabricate a PASS or performance metric.
- Build a minimal vertical slice and retain clean, reproducible scripts. Do not commit Vivado caches, local absolute paths or generated artefacts.
- Ask for exact board variants before final XDC selection; target board clock, device and reset wiring must be verified.
- No new operator or external memory interface can be claimed complete until its own separate test and documentation gates pass.

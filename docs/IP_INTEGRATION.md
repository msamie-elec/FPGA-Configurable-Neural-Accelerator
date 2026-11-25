# Reusable FPGA neural inference IP — Vivado Catalog v1.0

## What is the deliverable?

**Two independent deliverables:** the verified Arty A7 UART demonstration and the **standalone `npu_accelerator_ip` RTL wrapper**.

The IP wrapper instantiates the proven scalable NPU core and its eight BRAM-oriented weight banks. It has **no dependence on USB-UART, LED, pushbutton, board pin assignments or GUI**. It is an intentionally simple synchronous control/data interface, not an AXI4-Lite, AXI-Stream or DMA IP. Connecting to an AXI subsystem requires a separate, separately verified bridge.

Vendor namespace: `msamie-elec.github.io`; library: `user`; name: `npu_accelerator_ip`; version: `1.0`. The intended VLNV is `msamie-elec.github.io:user:npu_accelerator_ip:1.0`, subject to actual Vivado packaging/catalog verification.

## Port contract

| Port(s) | Direction | Width | Meaning |
|---|---|---:|---|
| `clk` | in | 1 | One synchronous positive-edge clock |
| `rst` | in | 1 | Active-high synchronous control reset; **does not clear weight/bias memories** |
| `start` | in | 1 | Pulse when idle, after model load |
| `features` | in | 256 | Up to 32 INT8 inputs, `features[8*i+:8]` |
| `layer_count` | in | 3 | 1–4 computational layers |
| `input_size` | in | 6 | 1–32 meaningful input samples |
| `size0..size3` | in | 6 each | 1–32 neurons per active layer; final output ≤8 |
| `shift` | in | 4 | Shared signed arithmetic right shift 0–15 |
| `weight_we` | in | 1 | Weight write strobe; issue only while idle |
| `weight_addr` / `weight_data` | in | 12 / 8 | Signed INT8 weight, addr=layer×1024 + neuron×32 + input |
| `bias_we` | in | 1 | Bias write strobe; issue only while idle |
| `bias_addr` / `bias_data` | in | 7 / 32 | Signed INT32 bias, addr=layer×32 + neuron |
| `busy` / `valid` / `error` | out | 1 each | Busy flag, one-cycle valid pulse, configuration rejection |
| `predicted_class` | out | 3 | Lowest-index argmax for final output scores |
| `outputs` | out | 64 | Eight signed INT8 outputs, inactive lanes zero |

All values are **little-lane order**; no byte endianness assumption is needed for the raw parallel ports. Both memories must be initialised by the integrating system after reset/power-up. IP has no runtime packet transport; attaching the existing UART frontend remains a *separate* system demonstration.

## Reproducible simulation verification

```bash
bash scripts/test.sh
```

The independent `tb/tb_npu_accelerator_ip.sv` drives a packed model and **all 48 Python-golden vectors** through the IP wrapper. This tests the reusable external port contract in addition to the existing UART and core regressions.

## Create the IP-XACT catalog package (Vivado 2025.2.1)

From a **fresh** Vivado Tcl session, with current directory anywhere:

```tcl
source vivado/package_npu_ip.tcl
```

Outputs to local ignored `build/ip_repo/npu_accelerator_ip_1_0/component.xml` (plus packaged RTL and metadata). To verify that the IP catalog can discover it:

```tcl
source vivado/check_npu_ip_catalog.tcl
```

**These Tcl flows have not been executed in Vivado by CI.** The source package, metadata, clock recognition and catalog integrity must be checked on Windows Vivado before claiming a validated IP-XACT release. The simulator only checks the RTL wrapper.

## Add to another Vivado design

In the target Vivado project:

```tcl
set_property ip_repo_paths [list {C:/path/to/your/FPGA-project/build/ip_repo}] [current_project]
update_ip_catalog -rebuild
```

Then open IP Integrator and search for **Configurable INT8 Neural Inference Accelerator**. The interface is unbundled scalar/vector ports, not AXI. To avoid unsupported AXI claims, connect RTL signals explicitly and add appropriate clock/reset handling and timing constraints.

## Release criteria

- [x] Wrapper RTL and 48-case golden simulation (CI).
- [x] Prior UART-integrated implementation timing and physical hardware numeric test.
- [ ] Vivado IP packager generated a clean `component.xml` and passed catalog discovery.
- [ ] IP instance independently synthesised in a consuming project.
- [ ] IP standalone representative integration meets 100 MHz routed timing.
- [ ] Reset/start/write/busy error handling strengthened under fault injection.
- [ ] Signed-off datasheet with versioned Vivado, netlist and bitstream provenance.

AMD reference: [Vivado Creating and Packaging Custom IP (UG1118)](https://docs.amd.com/r/en-US/ug1118-vivado-creating-packaging-custom-ip).

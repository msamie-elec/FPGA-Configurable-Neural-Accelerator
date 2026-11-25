# Engineering charter, constraints and definition of done

## 1. Problem statement

Build a small, reusable neural-inference hardware IP subsystem on real Arty A7 / Arty S7 FPGA development boards. The **hardware architecture** is the product; application demonstrations are separate clients. The architecture must support different *compatible* pre-trained models without revising RTL or regenerating a bitstream when model dimensions and weights change inside fixed device capacity.

## 2. Aim and concrete objectives

1. Specify an NPU-style subsystem (host command bridge, controller/scheduler, local SRAM memories, parallel MAC datapath, post-processing, reporting).
2. Freeze a bit-exact integer arithmetic contract and machine-readable, platform-neutral model descriptor.
3. Make model architecture a runtime **data input** rather than a fixed, elaboration-time parameter for supported layers.
4. Build a validated serial baseline and 4/8-lane variants with reproducible verification.
5. Show different networks without bitstream regeneration; reject incompatible networks with meaningful errors.
6. Implement at least one primary Arty A7 variant physically and port to a confirmed Arty S7 variant when feasible.
7. Publish code, hierarchy, diagrams, source-relative Vivado Tcl, XDC, simulations, waveforms, measured results and limitations.
8. Keep all related work cleanly separated from existing maritime DSP, Ethernet and motor-monitor repositories.

## 3. Architecture classes and design decisions

**Hardware target:** modular, *inference-only*, low-precision, SRAM-backed neural inference engine; FPGA prototype of NPU-type IP, not a fabricated ASIC.

**V1 operator set:** DENSE (matrix-vector affine), fused optional ReLU on hidden outputs, per-layer requantise back to signed INT8; final INT32 vector/logits. Host-side argmax is permissible for general use; optional hardware argmax is an explicitly identified auxiliary operation, not a requirement of every network.

**V1 network class:** feed-forward, sequential dense layers; configurable layer count and vector dimensions within finite limits. No recurrent loops, arbitrary branches, convolution, transformer/attention, training or autonomous learning. CNN kernels, pooling, attention, sparsity, mixed INT4/FP8 and external-memory DMA are later research tracks, not baseline claims.

**Configurable at synthesis:** processing lanes, SRAM sizes, maximum layer count, max vector dimension, memory bank layout, board wrapper, clock strategy.

**Configurable at runtime:** graph/layer descriptors, dimensions inside maxima, quantisation parameters, weights, biases, input vectors, model identity. All are loaded as data with checked integrity; the bitstream stays unchanged.

## 4. Preliminary resource/functional envelope (PROPOSED; MUST BE VERIFIED)

| Property | Initial candidate | Caveat |
|---|---|---|
| Precision | signed INT8 activations and weights, INT32 bias and accumulation | Exact rounding and bounds in model contract |
| Layers | 1 to 4 sequential dense layers | Within total weights/storage limit |
| Max layer input/output dimension | 256 each | A 256x256 weight matrix exceeds default 16-KiB total budget, so rejected unless increased |
| Total weights | 16 KiB on-chip SRAM initial candidate | Adjust to actual board BRAM mapping/capacity |
| Accumulators | INT32, with exporter checking every supported layer and biases | 64-bit temporary for requantisation where required |
| Lane count | 1, 4, 8 variants | Actual DSP/BRAM mapping to be measured |
| Inputs | Board host interface: USB-UART buffered inference transactions | No physical camera or motor needed |
| Board priority | Arty A7-35T first, then confirmed Arty S7 variant | Verify board part, oscillator, constraints and resources |

A model might fit by bytes yet fail to sustain an 8-lane access pattern; memory banking and read latency are first-class architectural requirements. Proposed limits are **not measured specifications**.

## 5. Definition of done — minimum strong portfolio release

- [ ] Stable bitstream executes **two intentionally different network topologies** (e.g., 8→16→4 and 12→8→3) loaded from independently generated packages on the *same programmed FPGA*.
- [ ] Model loading reports validated model ID/schema/checksum; malformed, unsupported or oversized models are explicitly rejected, not silently truncated.
- [ ] At least one **actually trained** compatible model is exported and executed on the FPGA after synthetic fixture tests, with documented provenance, preprocessing, quantisation and software-vs-FPGA accuracy. The model is a test workload, not hard-coded RTL.
- [ ] Signed arithmetic, rounding, saturation, bias alignment and layer boundaries are bit-exact against a **separately implemented integer oracle**.
- [ ] Inference input/output, buffer reuse, model replacement, reset, timeouts, CRC and invalid command behaviour are covered by automated tests.
- [ ] Actual A7 build is synthesised, routed, timed and placed, and physical board results are captured and archived with provenance.
- [ ] Core cycles/latency, resource usage, routed timing and host transport time are measured/reported separately.
- [ ] README, hierarchical RTL diagram, block diagram, operation trace, model compiler/loader instructions, supported-ops table and known limitations all agree with shipped source.
- [ ] `git clone` plus documented commands reproduce software and portable RTL simulation; local Vivado Tcl rebuilds with no machine-specific source paths.

Hardware success must be accompanied by test evidence; a generated `.bit` file is not by itself proof of inference correctness.

## 6. Career positioning

Primary: NPU/ML accelerator datapath architecture, resource-aware memory systems, SystemVerilog RTL, DSP48/BRAM inference, fixed-point numerics, timing closure, functional verification, portable interface design, reproducible experimental benchmarking. Secondary: host toolchain, model quantisation and embedded AI deployment. Avoid claims of GPU/TPU silicon tape-out or ASIC production experience from this exercise alone.

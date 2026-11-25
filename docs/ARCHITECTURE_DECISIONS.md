# FPGA NPU Architecture Decisions (ADRs) and risks

**Design, not completed implementation.** Changes to these decisions require matching updates to model binary, RTL ports, tests and final diagrams.

| Decision | Adopted V1 | Justification / restriction |
|---|---|---|
| Accelerator scope | Runtime-programmable sequential dense INT8 MLP | Hardware IP is independent of motor, image or sensor applications |
| Compute topology | 1D 1/4/8 multiply-PE vector + signed reduction + per-neuron accumulator | Implementable/inspectable on Arty FPGA; **not** 2D systolic array |
| Parameter change | Runtime model descriptors, weights, biases, quant params | Same bitstream serves differently shaped compatible models |
| Compute width | signed INT8 operands, signed INT32 bias/logits, signed INT64 requant intermediate | Deterministic bit-exact contract; no FP8/FP16/INT4 or affine zero point |
| Weight transport | 64-b wide on-chip RAM, neuron rows padded to 8 bytes | Supplies 8 lanes per read; portable model package across lane variants |
| Intermediate activations | Two 64-b packed scratchpads, ping/pong by layer | Eliminates read/write aliasing for sequential networks |
| Model change | BEGIN invalidates old model, one memory image | No doubled 16-KiB staging cost; failed replacement requires reload |
| External interface | 115200 8N1 UART, framed CRC, stop-and-wait | Reproducible Arty board proof, not high-throughput transport |
| Memory fabric | Local BRAM/LUTRAM, explicit address generation, no external DMA | Avoids implying nonexistent DDR/AXI master |
| Inference jobs | One active network job | Easier deterministic reset, schedule and independent testing |
| Model provenance | Exporter records model origin/licence/dataset/quantisation | No third-party pretrained model silently embedded |
| Portability | A7 and S7 use distinct wrappers/XDC | Do not transfer clocks/pins blindly between device families |

## Verification-driven risks

1. **Memory mapping:** 2048×64 weights and packed byte-enabled activation scratchpads must infer real usable FPGA memories. The BRAM mapping is a *target* until measured, not a claim.
2. **DSP inference:** INT8 signed multiplies may map to LUTs rather than DSP48 despite hints; document actual post-synthesis DSP and LUT counts.
3. **BRAM bandwidth:** P=8 needs 8 weight bytes **and** 8 activation bytes per arithmetic issue. Registered 64-bit reads and operand-latching must supply them without false speedup claims.
4. **Pipeline validity:** Products, group sums, neuron IDs and final-group flags need exactly aligned registers; drain before bias prevents cross-neuron leakage.
5. **Numerical safety:** Loader checks signed bias bounds using larger-than-INT32 math; verification rejects wrap/saturation before the intended output layer.
6. **Protocol resilience:** Packet loss, CRC failure, reset during load/inference and serial port reconnect must not leave stale `model_valid` or `result_valid`.
7. **Model fit:** The 16-KiB packed limit is stricter than max input/output dimensions. Compiler must report exact padded bytes and reject non-fitting graphs.
8. **Claims:** Green software regression, post-route timing, physical board proof and actual classification accuracy are different evidence classes. Keep them separate.

## Diagram acceptance gate

**Do not publish the final RTL poster before code/ports correspond to the architecture.** Future graphics are (A) system context, (B) top-level FPGA subsystems with control/data/memory arrows and (C) nested compute PE/pipeline architecture. Label unimplemented diagrams as *proposed*. The finished diagram must never show fictional DMA, DDR, systolic PE mesh, application motor block inside the FPGA, or training on FPGA.

# Scalable banked INT8 NPU — experimental V0.3

## Purpose and limitations

A new independent RTL subsystem, `rtl/npu_scalable_core.sv`, supports **up to 32 INT8 inputs and four sequential dense layers**. The target maximum is **32 → 32 → 32 → 32 → 8**: 104 computational neurons, 3,328 used INT8 weights, 104 biases, and **eight shared physical multiplication lanes**. This is an inference datapath, not trained model storage or a complete board application. The original small board demo is unchanged.

The network topology is set at each inference from `layer_count=1..4`, `input_size=1..32`, and `size0..size3`. The **final** active layer must have at most eight neurons. Unused layer sizes do not affect inference. 1/4/8 compile-time lanes remain available in the earlier V0.2 core; V0.3 is intentionally **fixed at eight lanes** to develop banking and timing before adding another parameter.

## Hardware datapath

```text
                                 layer/neuron/group FSM
                               /         |            \
host writes -> 8 x weight banks          |             -> bias registers
              512 x INT8 each            |
                  | 8 synchronous reads  |
activation A/B -> 8 signed INT8 products (registered)
                  |
               4 pair sums (registered)
                  |
               2 quad sums (registered)
                  |
               INT32 accumulation per input group
                  |
               bias -> signed shift -> INT8 saturation
                  |
        hidden: ReLU / final: unmodified logits + argmax
                  |
          activation ping-pong bank or output register
```

Each output neuron is completed in sequence. Within a neuron, up to eight input-weight pairs are processed simultaneously. Source activations are double-buffered, and consecutive layers alternate which activation bank supplies inputs.

## Memory contract

Weights occupy 4,096 addressable signed bytes. Host uses a **12-bit** logical address `layer*1024 + neuron*32 + input_index`, where `layer=0..3`, `neuron=0..31`, `input_index=0..31`. The physical mapping uses lane `address%8` and row `address/8`. Each bank implements synchronous registered reads, an 8-bit write interface, and the `ram_style="block"` synthesis hint. A real block-RAM mapping is **not guaranteed** until the Vivado report proves it.

Bias addresses are `layer*32+neuron` with signed INT32 contents. All used weights and biases **must be programmed** before inference; memory has no reset contents. Writes during `busy` are ignored for weights and biases. `start` is accepted only while idle and with write strobes low.

Input data uses 32 little-endian signed INT8 lanes in `features[255:0]`. Output data uses eight little-endian signed INT8 lanes in `outputs[63:0]`. Inactive output lanes are zero. `predicted_class` is argmax with lowest-index tie break. Arithmetic is signed: add products in INT32, add bias once, arithmetic right-shift by `shift`, saturate to [-128,127], then apply ReLU on hidden layers only.

`valid` pulses at end of a completed inference or rejected topology. `error` indicates a rejected configuration and remains set until another accepted configuration/reset.

## Reproducible simulation verification

```bash
bash scripts/test.sh
```

The extended test automatically generates deterministic weights, biases, and Python golden model outputs, programs all 4,096 weight positions and 128 bias positions over RTL write ports, and executes 48 inferences:

- 4 → 8 → 4 → 2 (original 14-neuron case)
- 8 → 16 → 8 → 2 (26 computational neurons)
- 32 → 32 → 32 → 32 → 8 (104 computational neurons)

Each topology receives 16 cases including zero, max/min signed INT8 and 12 seeded random inputs. The TB checks all output bytes and argmax. This is a directed/deterministic regression, not exhaustive mathematical proof.

## Vivado synthesis experiment

From project root in Vivado Tcl console:

```tcl
source vivado/synth_scalable.tcl
```

Produces `build/scalable_synth/utilization.rpt` and synthesis checkpoint. It is *synthesis only*: no I/O pin mapping, routed performance or 100 MHz timing claim. This module has too many configuration I/O pins to use directly as a physical top for the A7 board. A UART/packet controller and board-level top must be integrated before place-and-route and bitstream verification.

## Remaining engineering gates

1. Confirm GitHub CI success for new RTL and golden vectors.
2. Review Vivado DSP/BRAM inference, optimisation warnings and utilisation.
3. Integrate serial model loading, topology parameters and input/output packet transactions.
4. Close all constraints and 100 MHz post-route timing.
5. Execute physical A7 board tests with host numerical comparisons.
6. Add PC GUI for changing sensor features, training/testing externally, choosing models and reporting inference timing.

The current 32-wide capacity is an **engineering target** rather than a measured accuracy requirement for industrial anomaly detection. Model accuracy must be assessed using representative data.

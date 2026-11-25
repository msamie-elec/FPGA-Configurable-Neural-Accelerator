# V0.2 configurable MLP core (experimental)

This standalone compute subsystem is implemented in `rtl/mlp_engine.sv`. It does **not replace** the validated Arty A7 switch/LED top-level. It must pass GitHub CI and a separate Vivado synthesis/route before hardware integration.

## Contract

- Network: 1–3 densely connected layers, up to 8 input features, up to 8 outputs per layer.
- Example: **4 → 8 → 4 → 2** (14 computational neurons; 72 weights).
- `LANES` is an elaboration-time parameter: 1, 4 or 8 registered signed 8×8 multipliers operating in parallel on input groups. Layer sizes and count are configurable between inferences without synthesis.
- Weights: 192 signed INT8 locations (index `layer*64 + output_neuron*8 + input_feature`). Unused slots ignored.
- Biases: 24 signed INT32 locations (index `layer*8 + output_neuron`).
- Activations: INT8 signed, INT32 accumulated sums; each layer applies arithmetic right shift `output_shift`, saturates to signed INT8; ReLU on all hidden layers, no ReLU on final output.
- Tie-breaking: lowest class index.
- Host interface: parallel register write strobes, not yet UART. Program every used weight and bias before asserting `start` and do not write while `busy`.
- `valid` pulses once after inference; `error` latches on invalid topology until a valid start or reset. The host must inspect `error` whenever `valid` occurs.
- `features`: eight signed input bytes packed little-endian, first input in bits 7:0.
- `outputs`: eight output bytes packed identically; only first final-layer width is defined.

## Microarchitecture

```text
write interface  ---> weight register array (192 × 8) / bias registers (24 × 32)
input features   ---> activation bank A
                          |
                [LANES signed multipliers]
                          |
                 pipeline product register
                          |
                  sum/reduce accumulator
                          |
                 bias + shift + sat + ReLU
                          |
              alternating activation bank B/A
                          |
               final output + argmax + valid
```

The sequencer processes one neuron at a time, while parallelizing its input-channel products. The implementation uses a **register-array storage scheme**, not yet verified BRAM inference. A Vivado `use_dsp` hint is present, but actual DSP mapping and timing are only established from synthesis/utilisation reports. There is no claimed classification accuracy on a trained dataset.

## Verification

Run `bash scripts/test.sh` in WSL with Icarus Verilog. CI runs directed checks at **LANES=1/4/8** for two network topologies, changing inputs after `start` to check latching, ties, invalid configuration, and multiple hidden layers.

This is a directed smoke test, **not yet exhaustive randomised, bit-exact cross-validation against the Python reference**. That and FPGA timing closure are next acceptance gates.

## Vivado

The legacy board design remains top-level `arty_a7_top`. For synthesis-only exploration of the new standalone core:

```tcl
source vivado/synth_mlp.tcl
```

This runs three independent Vivado synthesis passes and generates utilisation reports under `build/mlp_synth/`. They are not hardware timing results. Never claim that 1/4/8 lanes or 100 MHz are implemented on the physical board until the new core has been integrated and routed.

## Next steps

1. Verify all CI jobs and simulation numerical expectations.
2. Run 1/4/8 lane Vivado synth: inspect inferred DSP, LUT/FF, and memory resources.
3. Add independent Python fixed-point reference and randomised test vectors.
4. Pipeline/reshape weight access for BRAM inference rather than 192-way register muxing.
5. Integrate model load protocol, UART transport, real hardware benchmark and PC GUI.

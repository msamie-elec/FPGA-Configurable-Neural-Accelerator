# V1 verification and architecture results

Verification used Icarus Verilog 12.0 and an independent scalar Python oracle. All results here are **simulation or structural synthesis evidence**. The [Arty procedure](V1_BOARD_TEST.md) is the outstanding board acceptance step.

## Functional coverage

| Test | Lanes | Observed result |
|---|---|---|
| Exhaustive signed INT8 operand pairs per build, reduction, masks, last tags and bubbles | 1, 4, 8 | 65,536 outputs checked per build |
| Full model load and result paging over byte-level link | 1, 4, 8 | 199 complete output vectors per build, including 100 held-out trained inputs |
| Serial 8N1 pin-level integration and A→B→A | 4 | 9 output vectors, nominal 16 clocks per serial bit |
| Serial 8N1 at the 100 MHz configuration | 4 | 3 output vectors with the actual 868-cycle baud divider |

The directed and seeded tests cover one, two and four layers; shape and lane tails; signed extrema, rounding ties, saturation and nonzero masked padding; maximum input width, output width and weight footprint; packed-word prefetch; result pagination; frame CRC rejection, parse timeout and stall stability; model CRC, descriptor, section, quantisation and bias rejection; invalid write offsets, incomplete model/input, busy rejection and reset during an active job. Bench assertions check model and memory ownership and reject unexpected output timing or content. These tests do not constitute exhaustive control-state or formal coverage.

Optional trained-model run used scikit-learn 1.8.0, UCI Optical Recognition of Handwritten Digits, 1,347 training and 450 test samples, stratified split with seed 42. Floating-point classifier matched **428/450** labels and the exported integer classifier matched **429/450**. The HDL regression separately matched every logit for 100 held-out inputs on each lane build. This one split does not establish a general accuracy improvement from quantisation.

## Controlled lane comparison

The 196→32→10 workload performs 6,592 useful scalar MACs. These elapsed **RTL clock counts** were checked against `GET_STATS`. Time is computed at 100 MHz and depends on closing timing when the design is routed.

| Lanes | Compute cycles | Arithmetic groups | Packed weight reads | Core time at 100 MHz target |
|---:|---:|---:|---:|---:|
| 1 | 6,898 | 6,592 | 840 | 68.98 µs |
| 4 | 2,038 | 1,648 | 840 | 20.38 µs |
| 8 | 1,272 | 840 | 840 | 12.72 µs |

The three configurations read the same weight words and use the same model image. From 4 to 8 lanes, group count falls by roughly half while overall simulated speed improves by **1.60×**. The per-neuron fetch, pipeline drain and post-processing account for the diminishing return. USB–UART transfer and model load time are outside the core counts.

## Synthesis check

Yosys 0.52 mapped the Arty top to 7-series cells and reported zero structural check problems in each build. The DSP totals include the common requantisation and descriptor validation logic.

| Lanes | DSP48E1 | RAMB18E1 |
|---:|---:|---:|
| 1 | 6 | 12 |
| 4 | 9 | 12 |
| 8 | 13 | 12 |

These mapped primitive counts are tool-specific. Routed utilisation, setup/hold closure, actual inference latency, UART round-trip time, power and physical board results require Vivado and the board. The GitHub Actions workflow runs the synthetic regression, and `--trained` adds the trained fixture locally.

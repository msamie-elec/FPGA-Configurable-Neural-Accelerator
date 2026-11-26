# Integration handoff: FPGA Bearing Condition Monitoring

**Consumer repository:** [FPGA Bearing Condition Monitoring](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring)  
**Reusable hardware supplier:** [FPGA Configurable Neural Accelerator](https://github.com/msamie-elec/FPGA-Configurable-Neural-Accelerator)

This page records the **intended deployment contract** without implying that the industrial bearing classifier is already trained, validated or deployed to physical hardware.

## Responsibility split

| Responsibility | Owner |
|---|---|
| Raw vibration/motor-current file ingestion, units and specimen labels | **Bearing application** |
| Eight numerical feature extraction and model-centre/scale calibration | **Bearing application** |
| Bearing-level held-out training/validation and monitoring thresholds | **Bearing application** |
| Train/quantise/export 8→16→8→2 MLP parameters | **Bearing application** |
| INT8×INT8 / INT32 MLP inference, ReLU, saturation and argmax | **Accelerator IP** |
| Reference Arty A7 UART transport, bitstream and physical cycle telemetry | **Accelerator demo** |
| Deploy model and compare FPGA logits to application Python oracle | **Joint integration**, not completed |

## Verified source-code interface (reviewed 26 November 2026)

The bearing repository implements:
- `bearing/features.py`: eight *derived features from two physical signal streams*, in the order:
  1. `vibration_rms`
  2. `vibration_std`
  3. `vibration_crest_factor`
  4. `vibration_excess_kurtosis`
  5. `current_rms`
  6. `current_std`
  7. `current_crest_factor`
  8. `current_high_band_power_fraction` (proposed 4–12 kHz current-band fraction).
- `bearing/train_export.py`: integer candidate model export, 8→16→8→2, per-model shift and grouped (bearing-ID) train/validation/test splits.
- `bearing/model_io.py`: `fpga-bearing-int8-v1` manifest validation, feature scaling, fixed-point Python prediction and UART model programming.

The current software's feature encoder computes `round_to_nearest_even((feature - feature_center) / feature_scale * 20)`, clips to signed INT8 and returns **eight bytes in the feature order above**. Software must use the **exact persisted training manifest** for `feature_center`, `feature_scale` and `shift`. The feature definitions and 4–12 kHz band are application hypotheses, **not proof of bearing-fault separability**.

The accelerator interprets byte 0 as `features[7:0]` and byte 7 as `features[63:56]`; the other 24 input bytes in the UART `I` request are padding. The configured `input_size` is **8**. The final size is 2. `outputs[7:0]` and `outputs[15:8]` are **signed logits**, not calibrated probabilities; `predicted_class` selects the larger and chooses class 0 if tied.

## FPGA model memory contract

The bearing project's `load_fpga_model` writes **weights individually with acknowledgement** to `layer*1024+neuron*32+input` and writes each signed INT32 bias to `layer*32+neuron`. It then calls the UART `configure(8, (16,8,2), shift=model_shift)`. Do **not** replace this with `load_demo_model()` (which uses deterministic, untrained weights).

A three-layer 8→16→8→2 model requires **272 active weights** and **26 active biases**. All those *used* addresses must be programmed after FPGA configuration/power-up. Unused weights do not require writing for that topology, but the current FPGA **has no model-image completeness flag or CRC**; the host must ensure that every write succeeded.

### Acceptance sequence for the actual bearing deployment

1. Inspect original licensed Paderborn MAT recordings and confirm channel structure, sampling rates, metadata and specimen labels. Do not train from fabricated unit-test waveforms.
2. Validate window feature extraction and the eight-feature order against real measurements.
3. Split by **physical bearing ID**, not by randomly allocated windows; fit any scaling on training bearings only.
4. Evaluate the exported **quantised** model on held-out bearings; publish confusion matrix, damaged recall and false-alarm rate. Confirm the manifest's status/acceptance gate.
5. Load the actual manifest via UART into the Track A bitstream `build/bitstream/arty_a7_uart_npu.bit` and run its eight signed-INT8 feature inputs.
6. Compare all FPGA **signed score bytes** and argmax with the application's `fixed_infer` on the **same** INT8 inputs. Confirm the exact shared shift, weight order and bias sign extension. Retain mismatches and latency logs.
7. Test invalid/truncated UART packets, reset/restart, incomplete programming and environmental assumptions before making any operational condition-monitoring claim.
8. Keep bearing-level quality/false-alarm claims in the **application** repository, and accelerator timing/area/power claims in this **hardware IP** repository.

## Current status and caveats

- Generic accelerator RTL, UART board and packaged Vivado IP have separate demonstrated verification evidence.
- The bearing application's Python feature processing and manifest checks have **synthetic software unit tests**, but original Paderborn MAT file ingestion has **not been verified using actual source recordings**.
- No measured-data trained/validated bearing-classification result, actual trained-model FPGA-vs-Python parity campaign or deployed bearing monitoring rig is claimed.
- Original Paderborn recordings are third-party **CC BY-NC 4.0** material; check permitted use and attribution before downloading, redistributing or commercial work.

For reproducibility see [Technical Datasheet](TECHNICAL_DATASHEET.md), [IP Integration](IP_INTEGRATION.md), [Start Here](START_HERE.md) and the companion [application documentation](https://github.com/msamie-elec/FPGA-Bearing-Condition-Monitoring/blob/main/docs/BEARING_APPLICATION.md).

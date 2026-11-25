# First industrial application: binary bearing-condition classification

## Scope

**Active work: healthy vs damaged bearing.** Avoid labelling the model as complete electric-motor diagnosis. Faults in IGBT drive/inverter circuitry are **out of scope** and may become a separate future project.

The generic FPGA NPU (UART, runtime weights, inference) is already physically tested with deterministic demonstration weights. **That is not a trained bearing classifier.** This new work defines the real data and software path before training a replacement model.

## Reference experimental dataset

[Paderborn University Bearing Data Center — official download page](https://mb.uni-paderborn.de/kat/forschung/bearing-datacenter/data-sets-and-download).

The university describes synchronous vibration and motor-current measurements for **six healthy** and **26 damaged** bearing conditions, recorded under four operating conditions, with 20 four-second measurements per setting. Some damaged bearings were artificially damaged; others developed damage in accelerated lifetime tests.

**Licence:** The official data centre states **Creative Commons Attribution–NonCommercial 4.0**. Commercial use needs the author's permission. Do not commit or republish the raw data in our public GitHub/Upwork portfolio without checking the licence and attribution obligations. Source citation: Lessmeier et al., KAt-DataCenter, Paderborn University.

## Physically meaningful sensor data

There are *two measured signal streams*, not eight independent physical sensors. Eight NPU features are extracted from windows of vibration/current:

| Input | Feature | Physical origin |
| --- | --- | --- |
| 1 | Vibration root-mean-square | vibration signal |
| 2 | Vibration standard deviation | vibration signal |
| 3 | Vibration crest factor | vibration signal |
| 4 | Vibration excess kurtosis | vibration signal |
| 5 | Current root-mean-square | current signal |
| 6 | Current standard deviation | current signal |
| 7 | Current crest factor | current signal |
| 8 | Current spectral power fraction, 4–12 kHz | current signal |

The 4–12 kHz fraction is an **initial engineering hypothesis**, not a validated bearing-fault feature. It must be tested for separability. The numerical units of vibration/current are inherited from the source records and must be checked against the university's signal metadata before displaying engineering-unit labels.

## Data ingestion and reproducibility

1. Download only the required Paderborn bearing recordings from the official provider and store them outside Git (e.g. `data/bearing/raw/`).
2. Confirm the original MATLAB structure and sampling metadata using a real file; do not silently guess channel locations or units.
3. Export paired synchronous vibration/current samples to a two-column CSV named with the original bearing code, e.g. `N15_M07_F10_K001_1.csv`, under `data/bearing/csv/`. A validated MATLAB reader can be added once the file format is inspected.
4. Create a **verified label manifest** using the official bearing list and condition tables. `bearing/labels_template.csv` is only a *format example*, not a complete or authoritative class map.
5. Extract aligned non-overlapping 8192-sample features:
   ```powershell
   py -m pip install -r bearing/requirements.txt
   py -m bearing.build_feature_table --input data/bearing/csv --labels bearing/labels.csv --output build/bearing/features.csv
   ```
6. Check distributions, missingness, operating conditions, imbalance and real bearing IDs. Do not label a class by applying a broad filename-prefix heuristic.

All steps must preserve `bearing_id`, original recording filename, operating condition, and window offset, allowing audit back to the real experiment. The input data is not included in this repository.

## Machine-learning acceptance

- Binary labels: **class 0 = healthy bearing**, **class 1 = damaged bearing**.
- Split by *physical bearing ID* so windows of the same bearing cannot appear in both training and held-out evaluation. Prefer group-aware cross-validation. Never randomly split overlapping windows.
- Fit scaling and any feature selection **only on training folds**.
- Train a small 8→16→8→2 MLP first; compare with a simple non-neural baseline.
- Quantise with the **actual fixed-point rules** implemented in the FPGA (signed INT8 weights/activations, signed INT32 biases/accumulator, one integer right shift per layer, saturate and hidden ReLU).
- Validate class accuracy, recall/sensitivity for damaged bearings, precision, confusion matrix, false-alarm rate and per-operating-condition generalisation on held-out bearings. Do not claim reliability from training accuracy.
- Export calibrated feature-to-INT8 transform and a **versioned weight/bias manifest**. Write real trained weights/biases via the existing UART interface; compare FPGA scores bit-for-bit with a fixed-point Python reference.
- Add real held-out healthy/damaged examples to the GUI, each with source bearing ID, operating condition and engineering-unit metadata. Clearly distinguish measured data from manually changed sliders.
- **Do not rename the current GUI classes to Healthy/Faulty until this trained model and its actual measurements are loaded.**

## State

Implemented here: numerical feature-extraction functions and a source-preserving CSV-to-feature-table command; synthetic-waveform *calculation* tests (not model training or fault-validation).

Not yet implemented: original MATLAB format verification, measured example extraction, bearing-level splits, trained model, calibrated quantisation or bearing-specific GUI integration. These cannot be honestly claimed without actual real records.

## V0.6 training and true-data GUI

The repository now includes `bearing/train_export.py` (grouped-bearing validation, real signal features, candidate MLP training and bit-exact fixed-point export), `bearing/model_io.py` (strict model shape/range checks and UART loading), `bearing/gui.py` (held-out healthy/damaged examples with real feature values), and synthetic unit tests **only for the processing pipeline**.

**The genuine Paderborn model is NOT yet trained** because no original measured recordings or extracted real feature table were provided to this execution. The training command refuses to operate without the labelled feature CSV; the GUI refuses to label a deterministic demo model as bearing health.

After acquiring and exporting a meaningful set of labelled real recordings (with multiple distinct physical specimens per class), run:

```powershell
py -m pip install -r bearing/requirements.txt
py -m bearing.build_feature_table --input data/bearing/csv --labels bearing/labels.csv --output build/bearing/features.csv
py -m bearing.train_export --features build/bearing/features.csv --output build/bearing/trained
py -m bearing.gui
```

The model manifest is `build/bearing/trained/bearing_model.json` and the authentic held-out measurements are `build/bearing/trained/held_out_examples.csv`. Both remain **local** and are excluded from Git. Physical device programming uses the existing UART bitstream and an independent fixed-point Python comparison.

Evaluation: split by physical bearing ID (never random recording windows), calculate preprocessing only using training rows, select integer candidates on held-out **validation** bearings, then calculate held-out test metrics once. The fixed-point model uses **global per-layer arithmetic shift** and has a 2-logit final layer whose class-0 score is 0. A baseline float sklearn classifier is trained, then re-expressed as quantised FPGA weights and biases; report *quantised* validation/test metrics rather than float training metrics. The current acceptance flag is a preliminary quality gate, not industrial safety certification.

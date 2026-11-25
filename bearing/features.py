"""Eight *measured-signal* features for the future bearing classifier.

Inputs must be synchronous sampled vibration and motor-current windows.
No model training or physical-unit calibration is implied here.
"""
from __future__ import annotations

import numpy as np

FEATURE_NAMES = (
    "vibration_rms",
    "vibration_std",
    "vibration_crest_factor",
    "vibration_excess_kurtosis",
    "current_rms",
    "current_std",
    "current_crest_factor",
    "current_high_band_power_fraction",
)


def _stats(samples: np.ndarray) -> tuple[float, float, float, float]:
    x = np.asarray(samples, dtype=np.float64)
    if x.ndim != 1 or len(x) < 32 or not np.all(np.isfinite(x)):
        raise ValueError("Signal must be a finite 1D vector of at least 32 samples")
    rms = float(np.sqrt(np.mean(x*x)))
    sd = float(np.std(x))
    peak = float(np.max(np.abs(x)))
    crest = peak / rms if rms > 1e-12 else 0.0
    centered = x - np.mean(x)
    fourth = float(np.mean(centered**4))
    kurtosis = fourth/(sd**4)-3 if sd > 1e-12 else 0.0
    return rms, sd, crest, kurtosis


def extract_features(
    vibration: np.ndarray,
    motor_current: np.ndarray,
    sample_rate_hz: float,
    *,
    high_band_hz: tuple[float, float] = (4000.0, 12000.0),
) -> np.ndarray:
    """Return 8 floats; last feature is current-signal 4–12 kHz power fraction.

    Band limits are an initial proposed feature, not a validated fault signature.
    Signal units are inherited from the source dataset, not assumed to be m/s² or A.
    """
    vib = np.asarray(vibration, dtype=np.float64).reshape(-1)
    cur = np.asarray(motor_current, dtype=np.float64).reshape(-1)
    if len(vib) != len(cur):
        raise ValueError("Vibration and current must have identical sample counts")
    if not np.isfinite(sample_rate_hz) or sample_rate_hz <= 2*high_band_hz[1]:
        raise ValueError("Sample rate is insufficient for requested high-frequency band")
    if not 0 < high_band_hz[0] < high_band_hz[1]:
        raise ValueError("Invalid spectral band")
    v_rms, v_sd, v_crest, v_kurt = _stats(vib)
    c_rms, c_sd, c_crest, _ = _stats(cur)
    spectrum = np.abs(np.fft.rfft(cur - np.mean(cur)))**2
    frequencies = np.fft.rfftfreq(len(cur), d=1.0/sample_rate_hz)
    # Exclude DC. This ratio is dimensionless and independent of FFT size.
    total = float(np.sum(spectrum[1:]))
    band = (frequencies >= high_band_hz[0]) & (frequencies <= high_band_hz[1])
    hf = float(np.sum(spectrum[band])) / total if total > 1e-24 else 0.0
    return np.asarray(
        [v_rms, v_sd, v_crest, v_kurt, c_rms, c_sd, c_crest, hf],
        dtype=np.float64,
    )

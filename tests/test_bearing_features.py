"""Numerical features tests use synthetic waveforms ONLY to validate calculations."""
import pathlib
import sys
import unittest

try:
    import numpy as np
except ImportError:
    np = None

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
if np is not None:
    from bearing.features import FEATURE_NAMES, extract_features


@unittest.skipIf(np is None, "numpy not installed")
class BearingFeatureTests(unittest.TestCase):
    def test_constant_and_spectral_band(self):
        rate=64000
        n=8192
        t=np.arange(n)/rate
        vib=np.sin(2*np.pi*1000*t)
        current=np.sin(2*np.pi*8000*t)
        features=extract_features(vib,current,rate)
        self.assertEqual(len(features),8)
        self.assertEqual(len(FEATURE_NAMES),8)
        self.assertAlmostEqual(features[0],2**-0.5,places=4)
        self.assertGreater(features[7],0.99)
        self.assertTrue(np.all(np.isfinite(features)))

    def test_zero_window(self):
        f=extract_features(np.zeros(8192),np.zeros(8192),64000)
        self.assertTrue(np.all(f==0))

    def test_invalid_inputs(self):
        with self.assertRaises(ValueError):
            extract_features(np.ones(10),np.ones(10),64000)
        with self.assertRaises(ValueError):
            extract_features(np.ones(1024),np.ones(512),64000)


if __name__=="__main__":
    unittest.main()

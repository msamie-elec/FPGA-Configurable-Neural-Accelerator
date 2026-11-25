"""Raw MATLAB loader tests use fabricated signal data ONLY for parser validation."""
import csv
from pathlib import Path
import tempfile
import unittest

import numpy as np
from scipy.io import savemat

from bearing.convert_mat import read_mat_channels,extract_from_mat
from bearing.build_feature_table import load_labels
from bearing.features import FEATURE_NAMES


class MatConverterTests(unittest.TestCase):
    def test_official_32_bearing_manifest(self):
        manifest=Path(__file__).resolve().parents[1]/"bearing"/"paderborn_labels_official.csv"
        labels=load_labels(manifest)
        self.assertEqual(len(labels),32)
        self.assertEqual(sum(v==0 for v in labels.values()),6)
        self.assertEqual(sum(v==1 for v in labels.values()),26)
        self.assertEqual(labels["K001"],0)
        self.assertEqual(labels["KA04"],1)
        self.assertEqual(labels["KI21"],1)


    def test_channel_selection_alignment_and_export(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            raw=root/"raw"
            raw.mkdir()
            filename=raw/"N15_M07_F10_K001_1.mat"
            t=np.arange(16384)/64000.0
            vib=np.sin(2*np.pi*400*t)
            cur=np.sin(2*np.pi*8000*t)
            savemat(filename,{"record":{"Y":[
                {"Name":"vibration_1","Data":{"y_values":vib}},
                {"Name":"phase_current_1","Data":{"y_values":cur}}
            ]}})
            recovered_v,recovered_c=read_mat_channels(filename)
            self.assertTrue(np.allclose(recovered_v,vib))
            self.assertTrue(np.allclose(recovered_c,cur))
            labels=root/"labels.csv"
            labels.write_text("bearing_id,class_id\nK001,0\n",encoding="utf-8")
            out=root/"features.csv"
            count=extract_from_mat(raw,labels,out)
            self.assertEqual(count,2)
            with out.open(newline="",encoding="utf-8") as f:
                rows=list(csv.DictReader(f))
            self.assertEqual(rows[0]["operating_condition"],"N15_M07_F10")
            self.assertTrue(all(feature in rows[0] for feature in FEATURE_NAMES))

    def test_missing_channel_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/"N15_M07_F10_K001_1.mat"
            savemat(path,{"record":{"Y":[
                {"Name":"vibration_1","Data":{"y_values":np.ones(8192)}}]}})
            with self.assertRaises(ValueError):
                read_mat_channels(path)


if __name__=="__main__":
    unittest.main()

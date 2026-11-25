"""Synthetic unit fixtures verify software wiring only, never bearing accuracy."""
import csv
from pathlib import Path
import tempfile
import unittest

import numpy as np

from bearing.features import FEATURE_NAMES
from bearing.train_export import (
    calibration, encode_features, fixed_infer, read_features, split_groups, train,
)
from bearing.model_io import read_model, reference_prediction


class BearingModelPipelineTests(unittest.TestCase):
    def test_fixed_point_signed_and_argmax(self):
        weights=[
            [[2],[-2]],
        ]
        biases=[[0,0]]
        # signed arithmetic shift 4 => 32*2 >> 4 = 4, -32*2 >> 4=-4
        score,winner=fixed_infer([32],weights,biases,4)
        self.assertEqual((score,winner),([4,-4],0))
        score,winner=fixed_infer([-32],weights,biases,4)
        self.assertEqual((score,winner),([-4,4],1))

    def test_group_split_and_train_export_round_trip(self):
        rng=np.random.default_rng(119)
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            path=root/"features.csv"
            with path.open("w",newline="",encoding="utf-8") as f:
                w=csv.writer(f)
                w.writerow(["source_file","bearing_id","class_id",
                    "window_start_sample",*FEATURE_NAMES])
                for label in range(2):
                    for bearing_no in range(7):
                        group=f"K{bearing_no+1:03d}" if label==0 else f"KA{bearing_no+1:02d}"
                        for sample in range(8):
                            values=rng.normal(loc=3*label+2,scale=0.55,size=8)
                            w.writerow([f"N15_M07_F10_{group}_1.csv",
                                        group,label,sample*8192,*values])
            records,x,y,groups=read_features(path)
            a,b,c=split_groups(y,groups)
            self.assertFalse(set(groups[a]) & set(groups[b]))
            self.assertFalse(set(groups[b]) & set(groups[c]))
            self.assertFalse(set(groups[a]) & set(groups[c]))
            center,scale=calibration(x[a])
            q=encode_features(x,center,scale)
            self.assertEqual(q.shape,(112,8))
            self.assertTrue(np.all(q>=-128) and np.all(q<=127))
            result=train(path,root/"export")
            model=read_model(root/"export"/"bearing_model.json")
            self.assertEqual(model["format"],"fpga-bearing-int8-v1")
            self.assertEqual(model["layer_sizes"],[16,8,2])
            self.assertEqual(set(model["classes"]),{"Healthy bearing","Damaged bearing"})
            with (root/"export"/"held_out_examples.csv").open(newline="",encoding="utf-8") as f:
                examples=list(csv.DictReader(f))
            self.assertTrue(examples)
            for example in examples[:8]:
                self.assertIn(example["bearing_id"],model["bearing_groups"]["test"])
                features=[float(example[n]) for n in FEATURE_NAMES]
                quantized,score,pred=reference_prediction(features,model)
                self.assertEqual(pred,int(example["fpga_reference_class"]))
                self.assertEqual(score,[int(example["score0"]),int(example["score1"])])
                self.assertEqual(quantized,[int(example[f"int8_{n}"]) for n in FEATURE_NAMES])


if __name__=="__main__":
    unittest.main()

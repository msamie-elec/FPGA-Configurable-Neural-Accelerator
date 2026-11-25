"""Offline mock tests; NOT physical reliability evidence."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"host"))

from reliability_campaign import campaign_one
from reference_scalable import infer


class FakeBoard:
    def __init__(self, corrupt=False, fail_at=None):
        self.loaded=None
        self.count=0
        self.corrupt=corrupt
        self.fail_at=fail_at
        self.load_count=0

    def load_demo_model(self, input_count, widths):
        self.loaded=widths
        self.load_count+=1

    def infer(self, sample):
        if self.fail_at is not None and self.count == self.fail_at:
            raise TimeoutError("injected timeout (mock)")
        self.count+=1
        scores,winner=infer(sample,self.loaded)
        class Reply:
            pass
        ret=Reply()
        ret.scores=tuple(scores+[0]*(8-len(scores)))
        ret.class_index=(winner+1)%self.loaded[-1] if self.corrupt else winner
        return ret

    def read_cycle_count(self):
        return 250


class ReliabilityCampaignTest(unittest.TestCase):
    def test_pass_and_reload_coverage(self):
        with tempfile.TemporaryDirectory() as d:
            b=FakeBoard()
            s=campaign_one(b,"medium",7,123,Path(d),reload_every=3)
            self.assertEqual((s["passes"],s["attempted"],s["model_reloads"]),(7,7,3))
            self.assertEqual(s["status"],"PASS")
            self.assertEqual(s["min_cycles"],250)
            self.assertEqual(len((Path(d)/"medium_events.jsonl").read_text().splitlines()),7)

    def test_mismatches_are_not_hidden(self):
        with tempfile.TemporaryDirectory() as d:
            s=campaign_one(FakeBoard(corrupt=True),"small",5,1,Path(d))
            self.assertEqual(s["status"],"FAIL_MISMATCH")
            self.assertEqual(s["mismatches"],5)

    def test_timeout_aborts_and_saves_partial_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            s=campaign_one(FakeBoard(fail_at=2),"small",8,1,Path(d))
            self.assertEqual(s["status"],"ABORTED")
            self.assertEqual((s["attempted"],s["passes"],s["transport_failures"]),(3,2,1))
            persisted=json.loads((Path(d)/"small_summary.json").read_text())
            self.assertEqual(persisted["status"],"ABORTED")
            self.assertEqual(len((Path(d)/"small_events.jsonl").read_text().splitlines()),3)


if __name__=="__main__":
    unittest.main()

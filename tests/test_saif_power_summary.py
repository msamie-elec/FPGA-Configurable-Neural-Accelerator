"""Use fabricated Vivado report excerpts to test parsing only."""
import sys
import tempfile
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from summarize_saif_power import evaluate,parse_power


def report(saif,matched):
    return f"""
| Total On-Chip Power (W) | 0.080 |
| Dynamic (W) | 0.018 |
| Device Static (W) | 0.062 |
| Confidence Level | Medium |
| Simulation Activity File | {saif} |
| Design Nets Matched | {matched} |
"""


class SaifPowerSummaryTests(unittest.TestCase):
    def test_parse_and_quality_gate(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            for phase in ["idle","loading","inference"]:
                (root/f"power_{phase}_saif.rpt").write_text(report(f"{phase}.saif","3.4%"))
            (root/"power_vectorless.rpt").write_text(report("---","NA"))
            result=evaluate(root)
            self.assertEqual(result["baseline_and_phase_estimates"]["idle"]["dynamic_w"],0.018)
            self.assertTrue(result["phase_quality"]["idle"]["saif_reported"])
            self.assertFalse(result["phase_quality"]["idle"]["ready_for_comparative_claims"])
            self.assertFalse(result["physical_power_measured"])
    def test_missing_report_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(FileNotFoundError):evaluate(folder)
    def test_missing_total_rejected(self):
        with self.assertRaises(ValueError):
            d=Path("missing")
            # Parse only: missing total is not guessed
            self.assertIsNone(parse_power("no report")["total_on_chip_w"])


if __name__=="__main__":
    unittest.main()

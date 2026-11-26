"""Synthetic Vivado report fixtures for routed NPU conservative quality gate."""
import sys
import tempfile
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from assess_routed_power import assess_routed


def report(cov=None):
    lines = [
        "| Total On-Chip Power (W) | 0.080 |",
        "| Dynamic (W) | 0.018 |",
        "| Device Static (W) | 0.062 |",
        "| Confidence Level | High |",
        "| Simulation Activity File | core.saif |",
    ]
    if cov:
        lines.append(f"| Design Nets Matched | {cov} |")
    return "\n".join(lines)+"\n"


class RoutedPowerAssessmentTests(unittest.TestCase):
    def fill(self,p,coverage):
        (p/"power_vectorless.rpt").write_text(report())
        for phase in ("idle","loading","inference"):
            (p/f"power_{phase}_saif.rpt").write_text(report(coverage))
            (p/f"{phase}_unmatched.txt").write_text("unmatched list\n")

    def test_good_coverage_not_physical_signoff(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            self.fill(p,"53% (1471/2771)")
            result=assess_routed(p)
            self.assertTrue(result["all_phases_above_provisional_threshold"])
            self.assertFalse(result["engineering_signoff"])
            self.assertFalse(result["measured_electrical_power"])
            self.assertIn("SDF",result["method"])

    def test_missing_coverage_fails_screen(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            self.fill(p,None)
            self.assertFalse(assess_routed(p)["all_phases_above_provisional_threshold"])

    def test_missing_report_fails(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(FileNotFoundError):
                assess_routed(d)


if __name__=="__main__":
    unittest.main()

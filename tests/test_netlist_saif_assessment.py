"""Synthetic Vivado report fixtures; tests parsing and conservative gate."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from assess_netlist_saif import assess, match_info

def power_report(matched=None):
    s = """| Total On-Chip Power (W) | 0.080 |
| Dynamic (W) | 0.018 |
| Device Static (W) | 0.062 |
| Confidence Level | Medium |
| Simulation Activity File | core.saif |
"""
    if matched is not None:
        s += f"| Design Nets Matched | {matched} |\n"
    return s


class NetlistAssessmentTests(unittest.TestCase):
    def populate(self, root, coverage="81% (3000/3700)"):
        (root / "power_vectorless.rpt").write_text(power_report())
        for phase in ("idle", "loading", "inference"):
            (root / f"power_{phase}_saif.rpt").write_text(power_report(coverage))
            (root / f"{phase}_unmatched.txt").write_text("unmatched nets list")

    def test_coverage_parsing(self):
        self.assertEqual(match_info("| Design Nets Matched | 3% (99/3664) |")["matched"], 99)
        self.assertAlmostEqual(
            match_info("INFO: [Power 33-26] Design nets matched = 99 of 3664")["fraction"],
            99 / 3664,
        )

    def test_good_coverage_remains_unqualified(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.populate(root)
            r = assess(root)
            self.assertTrue(r["all_phases_above_provisional_threshold"])
            self.assertFalse(r["engineering_signoff"])
            self.assertFalse(r["measured_electrical_power"])

    def test_low_coverage_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.populate(root, "3% (99/3664)")
            r = assess(root)
            self.assertFalse(r["all_phases_above_provisional_threshold"])

    def test_unreported_coverage_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.populate(root, None)
            self.assertFalse(assess(root)["all_phases_above_provisional_threshold"])

    def test_missing_file_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(FileNotFoundError):
                assess(td)


if __name__ == "__main__":
    unittest.main()

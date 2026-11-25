"""Validate physical benchmark report mathematics against source measurements."""
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from analyze_npu_performance import build_rows,report_md

class PhysicalBenchmarkReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source=Path(__file__).resolve().parents[1]/"docs/results/arty_a7_benchmark_2026-11-25.json"
        cls.data=json.loads(source.read_text(encoding="utf-8"))
        cls.rows=build_rows(cls.data)
    def test_exact_fpga_cycles_and_latencies(self):
        self.assertEqual([r["fpga_dispatch_to_valid_cycles"] for r in self.rows],
                         [114,250,2394])
        self.assertEqual([r["fpga_dispatch_to_valid_us"] for r in self.rows],
                         [1.14,2.5,23.94])
    def test_workload_gops_and_transport(self):
        self.assertEqual([r["macs"] for r in self.rows],[72,272,3328])
        self.assertAlmostEqual(self.rows[2]["effective_core_gops_2ops_per_mac"],0.278028,places=5)
        self.assertGreater(self.rows[2]["uart_time_divided_by_fpga_time"],600)
        self.assertGreater(self.rows[2]["eight_lane_ideal_peak_fraction"],0.17)
    def test_pass_counts_and_reporting(self):
        self.assertEqual(sum(r["passes"] for r in self.rows),300)
        self.assertTrue(all(r["mismatches"]==0 for r in self.rows))
        md=report_md(self.data,self.rows)
        self.assertIn("not an experimentally achieved",md)
        self.assertIn("23.94",md)

if __name__=="__main__":unittest.main()

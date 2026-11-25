"""Synthetic meter fixtures test calculations, not device power."""
import csv,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"scripts"))
from assess_power import analyse_power

class PowerTests(unittest.TestCase):
    def write(self,p,rows):
        with p.open("w",newline="") as fh:
            writer=csv.writer(fh)
            writer.writerow(["phase","scope","voltage_v","current_a","trial_id"])
            writer.writerows(rows)
    def test_power_and_optional_energy(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"m.csv"
            self.write(p,[["idle","fpga_rail",1,.1,"i1"],["idle","fpga_rail",1,.1,"i2"],
                          ["active","fpga_rail",1,.3,"a1"],["active","fpga_rail",1,.3,"a2"]])
            r=analyse_power(p,1000)
            self.assertAlmostEqual(r["incremental_power_w"],.2)
            self.assertAlmostEqual(r["active_energy_per_inference_j"],.0003)
            self.assertIsNone(analyse_power(p)["active_energy_per_inference_j"])
    def test_invalid_scope_and_rate(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"m.csv"
            self.write(p,[["idle","board",5,.1,"i1"],["idle","board",5,.1,"i2"],
                          ["active","fpga_rail",1,.2,"a1"],["active","fpga_rail",1,.2,"a2"]])
            with self.assertRaises(ValueError):analyse_power(p,100)
            with self.assertRaises(ValueError):analyse_power(p,float("nan"))
if __name__=="__main__":unittest.main()

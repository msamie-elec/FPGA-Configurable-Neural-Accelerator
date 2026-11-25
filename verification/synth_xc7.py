"""Run a structural 7-series mapping check. Vivado is used for the Arty bitstream."""
import argparse
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("hardware/build/yosys"))
    parser.add_argument("--lanes", nargs="+", type=int, choices=(1, 4, 8), default=[1, 4, 8])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    rtl = sorted(str(p.relative_to(root)) for p in (root / "hardware/rtl").rglob("*.sv"))
    rtl.append("hardware/boards/arty_a7/arty_a7.sv")
    args.out.mkdir(parents=True, exist_ok=True)
    for lanes in args.lanes:
        script = (f"read_verilog -sv {' '.join(rtl)}; "
                  f"chparam -set LANES {lanes} arty_a7; "
                  "synth_xilinx -family xc7 -top arty_a7; check -assert; stat")
        log = args.out / f"p{lanes}.log"
        with log.open("w") as output:
            subprocess.run([os.environ.get("YOSYS", "yosys"), "-Q", "-p", script],
                           cwd=root, stdout=output, stderr=subprocess.STDOUT, check=True)
        print(f"P={lanes} structural check PASS, {log}")


if __name__ == "__main__":
    main()

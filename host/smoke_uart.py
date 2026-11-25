#!/usr/bin/env python3
"""Hardware smoke test: program example MLP and verify a real UART inference."""
import argparse
from npu_serial import NpuBoard
from reference_scalable import infer

MODELS = {
    4:(4,(8,4,2)),
    8:(8,(16,8,2)),
    32:(32,(32,32,32,8)),
}
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port",required=True,help="E.g. COM4 (Windows) or /dev/ttyUSB1 (Linux)")
    parser.add_argument("--model",type=int,choices=MODELS,default=8)
    args=parser.parse_args()
    count,widths=MODELS[args.model]
    sample=[((i*11+7)%21)-10 for i in range(count)]
    expected,expected_class=infer(sample,widths)
    board=NpuBoard.open(args.port,timeout=3.0)
    try:
        board.ping()
        print("FPGA UART ping: OK")
        board.load_demo_model(count,widths,progress=lambda n,total:
            print(f"Weight loading: {n}/{total}") if n%128==0 or n==total else None)
        result=board.infer(sample)
        print("INPUTS ",sample)
        print("FPGA   ",result.scores[:widths[-1]],"class",result.class_index)
        print("PYTHON ",expected,"class",expected_class)
        if tuple(expected)!=result.scores[:widths[-1]] or expected_class!=result.class_index:
            raise SystemExit("FAIL: board and independent Python outputs differ")
        print("PASS: FPGA physical UART inference matched Python bit-for-bit")
    finally:
        board.close()

if __name__=="__main__":
    main()

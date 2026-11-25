"""Arty A7 hardware-in-loop acceptance test. Program the given bitstream first."""
import argparse
import hashlib
import json
import statistics
import subprocess
import time
import zlib
from pathlib import Path

from host.npu import Client, model_image
from host.reference import infer
from verification.fixtures import A, B, BENCH, network, vectors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", help="e.g. COM4 or /dev/ttyUSB1")
    parser.add_argument("--bitstream", type=Path, required=True)
    parser.add_argument("--lanes", choices=(1, 4, 8), type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--trained", action="store_true", help="also run 100 held-out digits")
    args = parser.parse_args()
    import serial

    bitstream_sha = hashlib.sha256(args.bitstream.read_bytes()).hexdigest()
    git = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True)
    report = {
        "git_sha": git.stdout.strip(), "operator_supplied_bitstream_sha256": bitstream_sha,
        "port": args.port, "runs": [], "pass": False,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    try:
        with serial.Serial(args.port, 115200, timeout=2, write_timeout=2) as port:
            port.reset_input_buffer()
            device = Client(port)
            report["caps"] = caps = device.caps()
            if caps["lanes"] != args.lanes:
                raise RuntimeError(f"Reported {caps['lanes']} lanes, expected {args.lanes}")
            workloads = [
                ("A", network(A, 15), vectors(A[0], 4, 42)),
                ("B", network(B, 15), vectors(B[0], 4, 42)),
                ("A_reload", network(A, 15), vectors(A[0], 4, 42)),
                ("196x32x10", network(BENCH, 15), vectors(BENCH[0], 100, 42)),
            ]
            if args.trained:
                from verification.trained_digits import train
                layers, inputs, report["training"] = train()
                workloads.append(("trained_digits", layers, inputs[:100]))
            device.command(0x7F)
            for name, layers, inputs in workloads:
                image = model_image(layers)
                crc = zlib.crc32(image)
                t0 = time.perf_counter()
                device.upload(image)
                group = {"name": name, "model_crc": crc, "model_size": len(image),
                         "load_ms": (time.perf_counter()-t0)*1000, "cases": []}
                report["runs"].append(group)
                for vector in inputs:
                    t0 = time.perf_counter()
                    observed, stats = device.infer(vector, len(layers[-1]["bias"]))
                    elapsed = time.perf_counter()-t0
                    expected = infer(layers, vector)
                    group["cases"].append({"input": vector, "expected": expected,
                        "observed": observed, "job_ms": elapsed*1000,
                        "core_us": stats["cycles"]*1_000_000/caps["clock_hz"], **stats})
                    if observed != expected or stats["model_crc"] != crc:
                        raise RuntimeError(f"{name} case {len(group['cases'])}: logit/model mismatch")
                group["median_job_ms"] = statistics.median(c["job_ms"] for c in group["cases"])
                print(f"{name} PASS {len(group['cases'])} full output vectors", flush=True)
            if report["runs"][0]["model_crc"] != report["runs"][2]["model_crc"]:
                raise RuntimeError("A reload image changed")
            report["pass"] = True
    except Exception as exc:
        report["error"] = str(exc)
        raise
    finally:
        args.out.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Saved {args.out}")


if __name__ == "__main__":
    main()

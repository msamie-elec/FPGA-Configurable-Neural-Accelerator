#!/usr/bin/env python3
"""Repeatable Arty A7 NPU UART benchmark: observed end-to-end transaction latency.

This tool NEVER calls serial round-trip timing "FPGA compute latency".
Reports raw scores, Python-oracle comparisons, p50/p95/p99 transactions,
pass/fail counts, source seed and topology. Requires a programmed Arty A7.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import random
import statistics
import time

from npu_serial import NpuBoard
from reference_scalable import infer

MODELS = {
    "small": (4, (8, 4, 2)),
    "medium": (8, (16, 8, 2)),
    "large": (32, (32, 32, 32, 8)),
}


def generate_inputs(n_features: int, count: int, seed: int):
    """Deterministic signed INT8 boundary and random vectors."""
    if count < 1:
        raise ValueError("count must be positive")
    corner = [
        [0] * n_features,
        [127] * n_features,
        [-128] * n_features,
        [127 if i % 2 else -128 for i in range(n_features)],
        [i % 11 - 5 for i in range(n_features)],
    ]
    rng = random.Random(seed)
    samples = list(corner[:count])
    while len(samples) < count:
        samples.append([rng.randrange(-128, 128) for _ in range(n_features)])
    return samples


def percentile(values, q: float):
    """Simple linear interpolation quantile for positive millisecond samples."""
    if not values:
        return None
    xs = sorted(values)
    index = (len(xs) - 1) * q / 100
    left = int(index)
    right = min(len(xs)-1, left+1)
    if right == left:
        return xs[left]
    return xs[left] * (right-index) + xs[right] * (index-left)


def benchmark_one(board, model_name: str, count: int, warmup: int, seed: int):
    inputs, widths = MODELS[model_name]
    t_load = time.perf_counter_ns()
    board.load_demo_model(inputs, widths)
    model_load_ms = (time.perf_counter_ns()-t_load)/1e6
    for sample in generate_inputs(inputs, max(1, warmup), seed ^ 0xABCD)[:warmup]:
        board.infer(sample)
    rows = []
    for index, sample in enumerate(generate_inputs(inputs, count, seed)):
        reference_scores, reference_class = infer(sample, widths)
        begin = time.perf_counter_ns()
        got = board.infer(sample)
        elapsed_ms = (time.perf_counter_ns() - begin) / 1e6
        actual_scores = tuple(int(x) for x in got.scores[:widths[-1]])
        expected_scores = tuple(reference_scores)
        passed = (actual_scores == expected_scores and got.class_index == reference_class)
        rows.append({
            "index": index, "inputs": json.dumps(sample),
            "expected_scores": json.dumps(reference_scores),
            "actual_scores": json.dumps(actual_scores),
            "expected_class": reference_class, "actual_class": got.class_index,
            "match": int(passed), "uart_transaction_ms": round(elapsed_ms, 6),
        })
    latencies = [r["uart_transaction_ms"] for r in rows]
    failures = sum(not r["match"] for r in rows)
    metrics = {
        "model": model_name, "topology": [inputs, *widths],
        "count": len(rows), "warmup": warmup, "seed": seed,
        "passes": len(rows)-failures, "mismatches": failures,
        "model_programming_ms": round(model_load_ms,3),
        "host_uart_transaction_ms": {
            "min": min(latencies), "mean": statistics.fmean(latencies),
            "p50": percentile(latencies, 50), "p95": percentile(latencies, 95),
            "p99": percentile(latencies, 99), "max": max(latencies),
        },
        "observed_single_stream_transactions_per_s": 1000/statistics.fmean(latencies),
        "fpga_compute_latency_cycles": None,
        "fpga_compute_latency_note": "Not instrumented; UART time includes transfers and Python/OS overhead",
    }
    return metrics, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port",required=True,help="Windows COM4 or equivalent serial port")
    parser.add_argument("--model",choices=[*MODELS, "all"],default="all")
    parser.add_argument("--count",type=int,default=100)
    parser.add_argument("--warmup",type=int,default=5)
    parser.add_argument("--seed",type=int,default=20261125)
    parser.add_argument("--output",type=Path,default=Path("build/benchmarks"))
    args=parser.parse_args()
    if args.count<1 or args.warmup<0:
        parser.error("--count >= 1 and --warmup >= 0 are required")
    chosen=list(MODELS) if args.model=="all" else [args.model]
    args.output.mkdir(parents=True,exist_ok=True)
    report={
        "timestamp_utc":datetime.now(timezone.utc).isoformat(),
        "target":"Digilent Arty A7-35T / UART at 115200 8N1",
        "protocol":"A5 XOR command, response 5A, v0.4",
        "test":"deterministic INT8 inputs vs independent signed fixed-point Python oracle",
        "important":"These are system-level UART transaction times, NOT FPGA core-cycle latency.",
        "results":{},
    }
    board=NpuBoard.open(args.port,timeout=3.0)
    try:
        board.ping()
        for name in chosen:
            print(f"Running {name}: {args.count} samples after {args.warmup} warmup")
            metrics,rows=benchmark_one(board,name,args.count,args.warmup,args.seed)
            report["results"][name]=metrics
            with (args.output/f"{name}_transactions.csv").open("w",newline="",encoding="utf-8") as f:
                writer=csv.DictWriter(f,fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            print(f"  matches={metrics['passes']}/{metrics['count']}, "
                  f"p95={metrics['host_uart_transaction_ms']['p95']:.3f} ms")
    finally:
        board.close()
    out=args.output/"benchmark_summary.json"
    out.write_text(json.dumps(report,indent=2),encoding="utf-8")
    print(f"Saved {out}")
    if any(result["mismatches"] for result in report["results"].values()):
        raise SystemExit("FAIL: FPGA and Python reference differed")
    print("PASS: all sampled FPGA outputs matched Python reference")


if __name__=="__main__":
    main()

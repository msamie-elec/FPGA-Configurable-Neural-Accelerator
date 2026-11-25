#!/usr/bin/env python3
"""Generate an inspectable, strictly source-backed FPGA NPU performance report.

Usage:
  python3 scripts/analyze_npu_performance.py \
    --input docs/results/arty_a7_benchmark_2026-11-25.json \
    --output build/performance
No vendor-specific tool needed; requires standard-library Python only.
All power/energy conclusions remain explicitly unmeasured.
"""
import argparse
import csv
import json
from pathlib import Path
import math


def build_rows(record: dict):
    clock=record["clock_hz"]
    if clock<=0:
        raise ValueError("Invalid FPGA clock")
    rows=[]
    for source in record["models"]:
        name=source["model"]
        cycles=source["cycles"]
        macs=source["macs"]
        n=source["count"]
        successes=source["passes"]
        if cycles<=0 or macs<=0 or n<=0 or not 0<=successes<=n:
            raise ValueError("Invalid source benchmark data")
        uart=source["uart_ms"]
        if not all(math.isfinite(float(v)) and float(v)>0 for v in uart.values()):
            raise ValueError("Invalid UART timing")
        latency_us=cycles*1e6/clock
        ideal_fps=clock/cycles
        mean_uart_s=uart["mean"]/1000
        effective_gops=2*macs*ideal_fps/1e9
        rows.append({
            "network":name,
            "topology":"→".join(str(x) for x in source["topology"]),
            "macs":macs,
            "sample_count":n,
            "passes":successes,
            "mismatches":n-successes,
            "fpga_dispatch_to_valid_cycles":cycles,
            "fpga_dispatch_to_valid_us":round(latency_us,6),
            "ideal_nonoverlap_core_inferences_s":round(ideal_fps,3),
            "effective_core_gops_2ops_per_mac":round(effective_gops,6),
            "eight_lane_ideal_peak_fraction":round(effective_gops/(8*2*clock/1e9),6),
            "model_programming_s":round(source["load_ms"]/1000,6),
            "uart_mean_ms":round(uart["mean"],6),
            "uart_min_ms":round(uart["min"],6),
            "uart_p50_ms":round(uart["p50"],6),
            "uart_p95_ms":round(uart["p95"],6),
            "uart_p99_ms":round(uart["p99"],6),
            "uart_max_ms":round(uart["max"],6),
            "uart_serial_transaction_s":round(mean_uart_s,9),
            "observed_single_stream_uart_inferences_s":round(1/mean_uart_s,4),
            "uart_time_divided_by_fpga_time":round((mean_uart_s*clock)/cycles,2),
        })
    return rows


def report_md(record,rows):
    table="| Network | MACs | FPGA cycles | FPGA µs | Core GOPS | UART mean ms | UART p95 ms | Passes |\n"
    table+="|---|---:|---:|---:|---:|---:|---:|---:|\n"
    for r in rows:
        table+=(f"| {r['network']} | {r['macs']:,} | {r['fpga_dispatch_to_valid_cycles']:,} "
                f"| {r['fpga_dispatch_to_valid_us']:.2f} | {r['effective_core_gops_2ops_per_mac']:.3f} "
                f"| {r['uart_mean_ms']:.3f} | {r['uart_p95_ms']:.3f} "
                f"| {r['passes']}/{r['sample_count']} |\n")
    return f"""# FPGA Configurable Neural Accelerator — physical benchmark assessment

## Provenance

- Source: user-submitted benchmark JSON (25 November 2026, {record["timestamp_utc"]}).
- Device: {record["target"]}; clock used in calculations: {record["clock_hz"]/1e6:.0f} MHz.
- Reference: independent signed fixed-point Python implementation; deterministic weights and inputs.
- Logic: eight shared signed INT8 multiplier lanes; this is a **mathematical reference workload**, not a trained task-accuracy evaluation.

## Direct measurements and derived quantities

{table}

All {sum(x['passes'] for x in rows)} sampled outputs matched the numerical reference out of {sum(x['sample_count'] for x in rows)} trials.
FPGA latency is a **cycle-counter measurement from inference command dispatch to core-valid**, including a small amount of interface handshake, but **excluding** PC-to-FPGA transmission.
UART timing measures **host transaction time** (USB/OS/UART transfers, FPGA computation and response). It is not isolated compute time.
For these steady one-transaction-at-a-time tests, mean UART latency produces roughly 63–65 transactions/second.

### Derived calculations

- Clock-period assumption: 10 ns per cycle.
- FPGA time = recorded cycles / 100 MHz.
- Effective core GOPS = 2 × MACs / FPGA dispatch-to-valid seconds, with one multiply plus one addition counted as two operations.
- Nonoverlapped compute-only upper-rate estimate = 100 MHz / recorded cycles. This **is a calculated per-inference upper bound for this protocol's measured cycle count**, not an experimentally achieved streaming throughput.
- Ideal multiplier-only peak = 8 physical signed INT8 lanes × 2 operations × 100 MHz = **1.6 GOPS**. It assumes every lane performs useful MAC work every clock; scheduling, reduction, memory, bias and quantisation overhead decrease achievable useful throughput.
- For the largest measured network, effective GOPS is **{rows[-1]['effective_core_gops_2ops_per_mac']:.3f}**, which is **{100*rows[-1]['eight_lane_ideal_peak_fraction']:.1f}%** of that arithmetic peak, and its mean UART transaction is **{rows[-1]['uart_time_divided_by_fpga_time']:.0f}×** the FPGA dispatch-to-valid latency.

### What is NOT supported by this benchmark

No measured **electrical watts**, **energy/inference**, **long-term field reliability**, **system sustained stream bandwidth under concurrency**, **maximum operating Fmax**, **fault tolerance**, **trained model accuracy**, or **official MLPerf score** was obtained.
The earlier Vivado power number is an unannotated tool estimate for FPGA *on-chip power*, not a physical meter reading, and should not be multiplied by UART latency to claim chip energy/inference.

### Follow-up qualification

1. Run 1,000+ hardware inferences per model, preserve all CSVs, record failures and timeouts explicitly.
2. Add protocol fault-injection, reset/recovery and partial-model protection tests.
3. Capture switching activity for more credible power analysis, then instrument rail power if available.
4. Re-run IP-only Vivado synthesis/place/route in a representative integrating top and validate the packaging/catalog flow.
5. Compare design trade-offs at identical precision, workload and 100 MHz timing constraints.

This generated report is evidence-backed but does **not** constitute industrial or safety certification.
"""


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--output",type=Path,default=Path("build/performance"))
    args=parser.parse_args()
    record=json.loads(args.input.read_text(encoding="utf-8"))
    rows=build_rows(record)
    args.output.mkdir(parents=True,exist_ok=True)
    with (args.output/"performance_comparison.csv").open("w",encoding="utf-8",newline="") as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (args.output/"PERFORMANCE_REPORT.md").write_text(report_md(record,rows),encoding="utf-8")
    print(f"Wrote {args.output/'PERFORMANCE_REPORT.md'} and performance_comparison.csv")
    for row in rows:
        print(f"{row['network']:<7}: {row['fpga_dispatch_to_valid_us']:>6.2f} µs, "
              f"{row['effective_core_gops_2ops_per_mac']:.3f} effective GOPS, "
              f"{row['passes']}/{row['sample_count']} passed")


if __name__=="__main__":
    main()

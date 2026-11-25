#!/usr/bin/env python3
"""Real FPGA endurance test with durable per-transaction evidence.

This is NOT a safety/lifetime qualification or a reset/fault injector.
A protocol/serial exception aborts the run (never blindly resend a packet
to potentially desynchronised firmware); the partial run is preserved.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time

from benchmark_npu import MODELS, generate_inputs
from npu_serial import NpuBoard
from reference_scalable import infer


def utcnow():
    return datetime.now(timezone.utc).isoformat()


def campaign_one(board, model_name, count, seed, output, reload_every=0, capture_cycles=True):
    """One topology; returns summary even if transport fails halfway."""
    if model_name not in MODELS or count < 1 or reload_every < 0:
        raise ValueError("Invalid model/count/reload interval")
    inputs, widths = MODELS[model_name]
    output.mkdir(parents=True, exist_ok=True)
    event_path = output / (model_name + "_events.jsonl")
    summary_path = output / (model_name + "_summary.json")
    samples = generate_inputs(inputs, count, seed)
    stats = dict(model=model_name, topology=[inputs, *widths],
                 requested=count, attempted=0, passes=0, mismatches=0,
                 transport_failures=0, model_reloads=0,
                 count_with_telemetry=0, min_cycles=None, max_cycles=None,
                 seed=seed, reload_every=reload_every,
                 started_utc=utcnow(), completed_utc=None,
                 status="RUNNING", error=None,
                 event_log=event_path.name)
    began=time.perf_counter()
    with event_path.open("w", encoding="utf-8") as log:
        try:
            for i, sample in enumerate(samples):
                if i == 0 or (reload_every > 0 and i % reload_every == 0):
                    board.load_demo_model(inputs, widths)
                    stats["model_reloads"] += 1
                reference_scores, reference_class = infer(sample, widths)
                begin_ns = time.perf_counter_ns()
                try:
                    response = board.infer(sample)
                    transaction_ms=(time.perf_counter_ns()-begin_ns)/1e6
                    cycles=board.read_cycle_count() if capture_cycles else None
                except Exception as exc:
                    stats["attempted"] += 1
                    stats["transport_failures"] += 1
                    stats["error"]=f"{type(exc).__name__}: {exc}"
                    log.write(json.dumps(dict(index=i, status="TRANSPORT_ERROR",
                                              error=stats["error"], input=sample))+"\n")
                    log.flush()
                    raise
                actual_scores=list(response.scores[:widths[-1]])
                passed=(actual_scores==list(reference_scores) and
                        response.class_index==reference_class)
                stats["attempted"]+=1
                stats["passes"]+=int(passed)
                stats["mismatches"]+=int(not passed)
                if cycles is not None:
                    stats["count_with_telemetry"]+=1
                    stats["min_cycles"]=cycles if stats["min_cycles"] is None else min(cycles,stats["min_cycles"])
                    stats["max_cycles"]=cycles if stats["max_cycles"] is None else max(cycles,stats["max_cycles"])
                log.write(json.dumps(dict(index=i, status="PASS" if passed else "MISMATCH",
                    input=sample, expected_scores=list(reference_scores),
                    actual_scores=actual_scores, expected_class=reference_class,
                    actual_class=response.class_index,
                    transaction_ms=round(transaction_ms,6),
                    fpga_dispatch_to_valid_cycles=cycles))+"\n")
                if not passed or i%100==0:
                    log.flush()
            stats["status"]="PASS" if stats["mismatches"]==0 else "FAIL_MISMATCH"
        except Exception as exc:
            if stats["status"]=="RUNNING":
                stats["status"]="ABORTED"
            if stats["error"] is None:
                stats["error"]=f"{type(exc).__name__}: {exc}"
        finally:
            stats["elapsed_s"]=round(time.perf_counter()-began,3)
            stats["completed_utc"]=utcnow()
            log.flush()
            summary_path.write_text(json.dumps(stats,indent=2)+"\n",encoding="utf-8")
    return stats


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port",required=True)
    p.add_argument("--model",choices=[*MODELS,"all"],default="all")
    p.add_argument("--count",type=int,default=1000,help="Trials PER model")
    p.add_argument("--reload-every",type=int,default=0,
                   help="Reprogram weights/biases every N inferences; 0=only once")
    p.add_argument("--seed",type=int,default=20261125)
    p.add_argument("--no-cycle-counter",action="store_true")
    p.add_argument("--output",type=Path,default=Path("build/reliability"))
    args=p.parse_args()
    if args.count<1 or args.reload_every<0:
        p.error("count >= 1 and reload-every >= 0 required")
    args.output.mkdir(parents=True,exist_ok=True)
    report=dict(test="physical_fpga_endurance", start_utc=utcnow(),
        target="Arty A7-35T UART NPU, 115200 baud",
        note="No reset, electrical power or injected-wire-fault testing is performed here",
        seed=args.seed, results={})
    try:
        board=NpuBoard.open(args.port,timeout=3)
        try:
            board.ping()
            if not args.no_cycle_counter:
                board.read_cycle_count()
            for model in ([*MODELS] if args.model=="all" else [args.model]):
                print(f"Testing {model}: {args.count} comparisons; reload-every={args.reload_every}")
                stats=campaign_one(board,model,args.count,args.seed,args.output,
                                   args.reload_every,not args.no_cycle_counter)
                report["results"][model]=stats
                print(f"  {stats['passes']}/{stats['attempted']} passed, {stats['status']}")
                if stats["status"]!="PASS":
                    break
        finally:
            board.close()
    except Exception as exc:
        report["fatal_error"]=f"{type(exc).__name__}: {exc}"
    finally:
        report["completed_utc"]=utcnow()
        report["total_passes"]=sum(x["passes"] for x in report["results"].values())
        report["total_attempted"]=sum(x["attempted"] for x in report["results"].values())
        report["overall_status"]="PASS" if (len(report["results"]) == (len(MODELS) if args.model=="all" else 1)
            and all(x["status"]=="PASS" for x in report["results"].values())
            and not report.get("fatal_error")) else "INCOMPLETE_OR_FAIL"
        result=args.output/"campaign_summary.json"
        result.write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
        print(f"Evidence: {result} ({report['overall_status']})")
    if report["overall_status"]!="PASS":
        raise SystemExit(1)


if __name__=="__main__":
    main()

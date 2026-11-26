#!/usr/bin/env python3
"""Summarise matching routed NPU netlist SAIF reports, without auto-signoff."""
import argparse
import json
import math
from pathlib import Path
from assess_netlist_saif import assess, PHASES


def assess_routed(reports_dir, min_match=0.30):
    outcome = assess(reports_dir, min_match)
    outcome["scope"] = "out-of-context NPU core, routed XC7A35T, 100 MHz"
    outcome["basis"] = "Vivado routed functional netlist and SAME routed checkpoint"
    outcome["method"] = "Functional post-route simulation: SAIF excludes SDF timing glitches"
    outcome["limitations"] = [
        "Not full integrated UART/FPGA board implementation",
        "Device static power is modelled for the entire target FPGA",
        "Unmatched nets use Vivado estimated switching rates",
        "No post-route SDF/timing backannotation, therefore glitch activity may be understated",
        "No physical rail voltage/current measurements",
    ]
    outcome["engineering_signoff"] = False
    outcome["qualification"] = "REVIEW — check DSP, BRAM, clocks, SAIF coverage and timing"
    powers = outcome["phases"]
    if all(p["power"]["dynamic_w"] is not None for p in powers.values()):
        idle = powers["idle"]["power"]["dynamic_w"]
        outcome["estimated_dynamic_delta_mw_vs_idle"] = {
            "loading": round(1000*(powers["loading"]["power"]["dynamic_w"]-idle), 3),
            "inference": round(1000*(powers["inference"]["power"]["dynamic_w"]-idle), 3)
        }
    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", type=Path, default=Path("build/routed_core_power/reports"))
    parser.add_argument("--output", type=Path, default=Path("build/routed_core_power/routed_power_assessment.json"))
    parser.add_argument("--min-match", type=float, default=0.30)
    args = parser.parse_args()
    output = assess_routed(args.reports, args.min_match)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2)+"\n", encoding="utf-8")
    for phase in PHASES:
        p = output["phases"][phase]
        count = p["annotation"]
        cov = "UNKNOWN" if count is None else f"{count['matched']}/{count['total']} ({100*count['fraction']:.1f}%)"
        print(f"{phase:10}: {p['power']['total_on_chip_w']} W total, "
              f"{p['power']['dynamic_w']} W dynamic, SAIF coverage {cov}, "
              f"{p['power']['confidence']} confidence")
    print(f"Saved {args.output}")
    print("CAUTION: routed OOC core VIVADO ESTIMATES, not measured watts or energy/inference.")
    if not output["all_phases_above_provisional_threshold"]:
        raise SystemExit("Insufficient SAIF coverage: inspect unmatched reports before quoting phase power.")


if __name__ == "__main__":
    main()

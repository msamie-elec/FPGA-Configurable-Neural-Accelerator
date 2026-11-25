#!/usr/bin/env python3
"""Quality gate for post-synthesis core netlist SAIF power estimates.

This script DOES NOT run XSim, Vivado or a power meter. It reads actual
Vivado reports and refuses to call a comparison acceptable when the matched
activity cannot be established. 30% is a provisional engineering screening
threshold, NOT a Vivado qualification or universal standard.
"""
import argparse
import json
import math
import re
from pathlib import Path

from summarize_saif_power import parse_power

PHASES = ("idle", "loading", "inference")
MIN_SCREENING_MATCH = 0.30


def match_info(text):
    # Vivado report_power reports normally use "3% (99/3664)".
    m = re.search(r"Design\s+Nets\s+Matched[^\r\n]*?\|\s*(\d+(?:\.\d+)?)%\s*\(\s*(\d+)\s*/\s*(\d+)\s*\)",
                  text, re.IGNORECASE)
    if m:
        count, total = int(m.group(2)), int(m.group(3))
        if total > 0 and count <= total:
            return {"matched": count, "total": total, "fraction": count / total}
    # Also accept the raw Vivado console phrasing from the SAIF importer.
    m = re.search(r"Design\s+Nets\s+Matched\s*=\s*(\d+)\s+of\s+(\d+)",
                  text, re.IGNORECASE)
    if m:
        count, total = int(m.group(1)), int(m.group(2))
        if total > 0 and count <= total:
            return {"matched": count, "total": total, "fraction": count / total}
    return None


def assess(root, min_match=MIN_SCREENING_MATCH):
    if not (math.isfinite(min_match) and 0 < min_match <= 1):
        raise ValueError("Invalid SAIF screening threshold")
    root = Path(root)
    result = {
        "scope": "post-synthesis out-of-context NPU core XC7A35T at 100 MHz",
        "basis": "Vivado post-synthesis functional netlist, identical checkpoint for report_power",
        "not_comparable_as_equivalent_to": "routed UART+NPU board-level Vivado estimate",
        "measured_electrical_power": False,
        "qualification": "experimental",
        "min_screening_fraction": min_match,
        "phases": {},
    }
    baseline = root / "power_vectorless.rpt"
    if not baseline.is_file():
        raise FileNotFoundError(baseline)
    result["vectorless"] = parse_power(baseline.read_text(encoding="utf-8", errors="replace"))
    if result["vectorless"]["total_on_chip_w"] is None:
        raise ValueError("Baseline report does not contain total on-chip power")
    for phase in PHASES:
        p = root / f"power_{phase}_saif.rpt"
        unmatched = root / f"{phase}_unmatched.txt"
        if not p.is_file() or not unmatched.is_file():
            raise FileNotFoundError(f"Missing {p} or {unmatched}")
        content = p.read_text(encoding="utf-8", errors="replace")
        power = parse_power(content)
        if power["total_on_chip_w"] is None:
            raise ValueError(f"Missing on-chip total in {p}")
        m = match_info(content)
        if m is None:
            # Some Vivado reports print the coverage only in the unmatched file.
            m = match_info(unmatched.read_text(encoding="utf-8", errors="replace"))
        enough = m is not None and m["fraction"] >= min_match
        result["phases"][phase] = {
            "power": power,
            "annotation": m,
            "screening_status": "REVIEW" if enough else "INSUFFICIENT_MATCH",
            "screening_pass": enough,
            "unmatched_report": str(unmatched),
        }
    result["all_phases_above_provisional_threshold"] = all(
        r["screening_pass"] for r in result["phases"].values()
    )
    result["engineering_signoff"] = False
    result["signoff_reason"] = (
        "Review primitive clock/DSP/BRAM activity and compare with routed design "
        "before citing phase power; matched-net fraction alone is insufficient."
    )
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--reports", type=Path, default=Path("build/netlist_power/reports"))
    p.add_argument("--output", type=Path, default=Path("build/netlist_power/netlist_power_assessment.json"))
    p.add_argument("--min-match", type=float, default=MIN_SCREENING_MATCH)
    args = p.parse_args()
    r = assess(args.reports, args.min_match)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(r, indent=2) + "\n", encoding="utf-8")
    for name, item in r["phases"].items():
        m = item["annotation"]
        coverage = "not reported" if m is None else f"{m['matched']}/{m['total']} = {100*m['fraction']:.1f}%"
        print(f"{name}: coverage={coverage}, on-chip estimate="
              f"{item['power']['total_on_chip_w']} W, {item['screening_status']}")
    print(f"Saved: {args.output}")
    print("SAIF results are NOT physical power; a provisional screening PASS is NOT sign-off.")
    if not r["all_phases_above_provisional_threshold"]:
        raise SystemExit("NETLIST POWER ACTIVITY COVERAGE INSUFFICIENT OR UNKNOWN; inspect unmatched reports.")


if __name__ == "__main__":
    main()

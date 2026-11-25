#!/usr/bin/env python3
"""Summarise Vivado vectorless and phase-specific SAIF ESTIMATES.

Reject reports without traceable SAIF annotation instead of inventing
improvements. Matching/coverage must be reviewed before qualification.
"""
import argparse
import json
from pathlib import Path
import re


def field(text,label):
    patt=r"\|\s*"+re.escape(label)+r"\s*\|\s*([^|\r\n]+?)\s*\|"
    m=re.search(patt,text,re.I)
    return m.group(1).strip() if m else None


def parse_power(text):
    def watts(name):
        v=field(text,name)
        return float(v) if v not in (None,"---","NA") else None
    return {
        "total_on_chip_w":watts("Total On-Chip Power (W)"),
        "dynamic_w":watts("Dynamic (W)"),
        "device_static_w":watts("Device Static (W)"),
        "confidence":field(text,"Confidence Level"),
        "saif_file":field(text,"Simulation Activity File"),
        "design_nets_matched":field(text,"Design Nets Matched"),
    }


def evaluate(root):
    root=Path(root)
    files={"vectorless":"power_vectorless.rpt",
           "idle":"power_idle_saif.rpt",
           "loading":"power_loading_saif.rpt",
           "inference":"power_inference_saif.rpt"}
    output={}
    for label,name in files.items():
        p=root/name
        if not p.is_file():
            raise FileNotFoundError(f"Missing Vivado report: {p}")
        output[label]=parse_power(p.read_text(encoding="utf-8",errors="replace"))
        if output[label]["total_on_chip_w"] is None:
            raise ValueError(f"Vivado power total missing: {p}")
    quality={}
    for phase in ["idle","loading","inference"]:
        row=output[phase]
        annotated=row["saif_file"] not in (None,"---","NA","")
        matched=row["design_nets_matched"] not in (None,"---","NA","")
        quality[phase]={
            "saif_reported":annotated,
            "design_net_match_reported":matched,
            "mapping_review_required":True,
            "ready_for_comparative_claims":False,
            "reason":"Core-only RTL SAIF; inspect unmapped nets and matched coverage, clock/phase assumptions, and topology vs implemented UART design.",
        }
    return {
        "source":"Vivado post-route report_power output, not external electricity meter",
        "baseline_and_phase_estimates":output,
        "phase_quality":quality,
        "physical_power_measured":False,
        "energy_per_inference_measured":False,
        "note":"Do not calculate measured power or joules from tool estimates. RTL SAIF switching coverage may be incomplete.",
    }


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--reports",type=Path,default=Path("build/power_activity/reports"))
    p.add_argument("--output",type=Path,default=Path("build/power_activity/power_phase_summary.json"))
    args=p.parse_args()
    result=evaluate(args.reports)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    for phase,power in result["baseline_and_phase_estimates"].items():
        print(f"{phase:10s}: total={power['total_on_chip_w']} W "
              f"dynamic={power['dynamic_w']} W SAIF={power['saif_file']} "
              f"matched={power['design_nets_matched']}")
    print(f"Summary: {args.output}")
    print("WARNING: these remain ACTIVITY-INFORMED VIVADO ESTIMATES, not hardware measurements.")


if __name__=="__main__":
    main()

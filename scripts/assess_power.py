#!/usr/bin/env python3
"""Analyse ACTUALLY MEASURED same-scope rail/board voltage-current samples.

This script does not perform measurements. Never pass Vivado estimated power
as real samples. Energy/inference requires MEASURED sustained throughput.
"""
import argparse,csv,json,math
from pathlib import Path
from statistics import fmean,stdev

def analyse_power(path,measured_fps=None):
    if measured_fps is not None and (not math.isfinite(measured_fps) or measured_fps<=0):
        raise ValueError("Measured sustained fps must be positive and finite")
    with Path(path).open(newline="",encoding="utf-8-sig") as fh:
        reader=csv.DictReader(fh)
        if not reader.fieldnames or not {"phase","scope","voltage_v","current_a","trial_id"}<=set(reader.fieldnames):
            raise ValueError("Required columns: phase,scope,voltage_v,current_a,trial_id")
        records=list(reader)
    if not records:raise ValueError("No measurements")
    groups={"idle":[],"active":[]};scopes=set()
    for row in records:
        phase=row["phase"].strip().lower()
        if phase not in groups:raise ValueError("Phase must be idle or active")
        scopes.add(row["scope"].strip())
        v=float(row["voltage_v"]);i=float(row["current_a"])
        if not (math.isfinite(v) and math.isfinite(i) and 0<v<=20 and 0<=i<=20):
            raise ValueError("Invalid voltage/current measurement")
        if not row["trial_id"].strip():raise ValueError("Missing trial_id")
        groups[phase].append(v*i)
    if len(scopes)!=1 or "" in scopes:raise ValueError("Mixed or missing measurement scope")
    if min(len(v) for v in groups.values())<2:raise ValueError("Need 2+ observations per phase")
    idle=fmean(groups["idle"]);active=fmean(groups["active"])
    result={"scope":scopes.pop(),"source_file":str(path),
        "type":"operator-supplied electrical measurements, NOT Vivado estimated watts",
        "incremental_power_w":active-idle,
        "incremental_power_negative":active<idle,
        "measured_sustained_fps":measured_fps,
        "active_energy_per_inference_j":active/measured_fps if measured_fps else None,
        "incremental_energy_per_inference_j":(active-idle)/measured_fps if measured_fps else None,
        "notes":["Scope may represent total board rather than isolated FPGA.",
          "Samples should be time-aligned to sustained inference operation.",
          "Energy requires a sustained rate MEASURED under same power conditions.",
          "Do not substitute the ideal 100MHz/cycles rate for measured system throughput."]}
    for key,values in groups.items():
        result.setdefault("phases",{})[key]={
            "n":len(values),"mean_w":fmean(values),"sample_std_w":stdev(values),
            "min_w":min(values),"max_w":max(values)}
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--measurements",type=Path,required=True)
    p.add_argument("--measured-fps",type=float)
    p.add_argument("--output",type=Path,default=Path("build/power/assessment.json"))
    a=p.parse_args()
    result=analyse_power(a.measurements,a.measured_fps)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print("Measured-power assessment:",a.output)
    print("Idle W:",result["phases"]["idle"]["mean_w"],
          "active W:",result["phases"]["active"]["mean_w"],
          "incremental W:",result["incremental_power_w"])
    if a.measured_fps is None:print("Energy/inference UNAVAILABLE (measured FPS not supplied)")
if __name__=="__main__":main()

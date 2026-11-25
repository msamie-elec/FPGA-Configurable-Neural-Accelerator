"""Conservative extractor for Paderborn-style MATLAB recordings.

Original files may use MATLAB structs with Y channel records named
'vibration_1' and 'phase_current_1'. We require explicit channel names and
reject missing/ambiguous structures. This reader still needs verification
against a genuine downloaded .mat file before claims about raw-data coverage.
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path
import re

import numpy as np
from scipy.io import loadmat
from .build_feature_table import load_labels, BEARING_CODE
from .features import FEATURE_NAMES,extract_features

CONDITION = re.compile(r"(N\d{2}_M\d{2}_F\d{2})",re.I)


def _scan(obj, found, depth=0):
    if depth>20:
        raise ValueError("MATLAB structure nesting too deep")
    if isinstance(obj,dict):
        norm={str(k).lower():v for k,v in obj.items()}
        if "name" in norm and "data" in norm:
            name=str(np.asarray(norm["name"]).squeeze())
            if name in ("vibration_1","phase_current_1"):
                arr=_find_numeric_signal(norm["data"])
                found.setdefault(name,[]).append(arr)
        for value in obj.values():
            _scan(value,found,depth+1)
    elif isinstance(obj,(list,tuple)):
        for value in obj:
            _scan(value,found,depth+1)
    elif isinstance(obj,np.ndarray) and obj.dtype==object:
        for value in obj.flat:
            _scan(value,found,depth+1)


def _find_numeric_signal(obj):
    candidates=[]
    def walk(v,level=0):
        if level>20:raise ValueError("Nested data exceeds supported depth")
        if isinstance(v,dict):
            # Prefer the canonical numeric samples rather than metadata time.
            if "y_values" in v:
                walk(v["y_values"],level+1)
            elif "Data" in v:
                walk(v["Data"],level+1)
            else:
                for k,value in v.items():
                    if str(k).lower() in ("value","values","samples"):
                        walk(value,level+1)
        elif isinstance(v,(list,tuple)):
            for item in v:walk(item,level+1)
        elif isinstance(v,np.ndarray):
            if np.issubdtype(v.dtype,np.number) and v.size>=8192:
                candidates.append(np.asarray(v,dtype=np.float64).reshape(-1))
            elif v.dtype==object:
                for item in v.flat:walk(item,level+1)
    walk(obj)
    if len(candidates)!=1:
        raise ValueError(f"Expected one unambiguous numeric waveform, found {len(candidates)}")
    if not np.all(np.isfinite(candidates[0])):
        raise ValueError("Recording contains invalid samples")
    return candidates[0]


def read_mat_channels(path):
    try:
        content=loadmat(str(path),simplify_cells=True)
    except NotImplementedError as exc:
        raise RuntimeError("MATLAB v7.3 / HDF5 file: inspect channel structure and add a verified loader") from exc
    found={}
    _scan({k:v for k,v in content.items() if not k.startswith("__")},found)
    for name in ("vibration_1","phase_current_1"):
        if len(found.get(name,[]))!=1:
            raise ValueError(f"{path.name}: require exactly one {name} channel, got {len(found.get(name,[]))}")
    vib=found["vibration_1"][0]
    cur=found["phase_current_1"][0]
    if len(vib)!=len(cur):
        raise ValueError(f"{path.name}: sample counts not aligned: {len(vib)} vs {len(cur)}")
    return vib,cur


def extract_from_mat(input_dir,labels_path,output_path,fs=64000.0,window=8192,stride=8192):
    labels=load_labels(labels_path)
    records=sorted(input_dir.rglob("*.mat"))
    if not records:
        raise FileNotFoundError("No real Paderborn .mat recordings present")
    rows=[]
    for file in records:
        found=BEARING_CODE.search(file.stem)
        condition=CONDITION.search(file.stem)
        if not found or not condition:
            raise ValueError(f"Unrecognised Paderborn recording filename {file.name}")
        bearing_id=found.group(1).upper()
        if bearing_id not in labels:
            raise ValueError(f"Missing verified bearing label for {bearing_id}")
        vib,cur=read_mat_channels(file)
        for offset in range(0,len(vib)-window+1,stride):
            feats=extract_features(vib[offset:offset+window],
                                   cur[offset:offset+window],fs)
            rows.append([file.name,bearing_id,labels[bearing_id],offset,
                         condition.group(1).upper(),*map(float,feats)])
    if not rows:
        raise ValueError("No complete signal windows extracted")
    output_path.parent.mkdir(parents=True,exist_ok=True)
    with output_path.open("w",encoding="utf-8",newline="") as f:
        wr=csv.writer(f)
        wr.writerow(["source_file","bearing_id","class_id",
                     "window_start_sample","operating_condition",*FEATURE_NAMES])
        wr.writerows(rows)
    return len(rows)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--labels",type=Path,required=True)
    parser.add_argument("--output",type=Path,default=Path("build/bearing/features.csv"))
    parser.add_argument("--sample-rate",type=float,default=64000.0)
    parser.add_argument("--window",type=int,default=8192)
    parser.add_argument("--stride",type=int,default=8192)
    args=parser.parse_args()
    n=extract_from_mat(args.input,args.labels,args.output,
                       args.sample_rate,args.window,args.stride)
    print(f"Extracted {n} measured windows from raw MATLAB recordings.")
    print("IMPORTANT: verify original channel units/time alignment from experimental metadata.")


if __name__=="__main__":
    main()

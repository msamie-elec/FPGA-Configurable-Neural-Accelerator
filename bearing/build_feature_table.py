#!/usr/bin/env python3
"""Prepare measured Paderborn bearing signals exported as aligned CSV columns.

Usage:
 python -m bearing.build_feature_table --input data/bearing/csv \
  --labels bearing/labels.csv --output build/bearing/features.csv

CSV must have columns 'vibration' and 'motor_current'. The filename must
include a bearing code; labels.csv explicitly maps physical bearing IDs to
healthy (0) or damaged (1). No auto-classification by filename prefixes.
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path
import re

import numpy as np

from .features import FEATURE_NAMES, extract_features

BEARING_CODE = re.compile(r"(?:^|_)(K\d{3}|KA\d{2}|KI\d{2}|KB\d{2})(?:_|$)", re.I)


def load_labels(path: Path) -> dict[str, int]:
    labels = {}
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames or not {"bearing_id", "class_id"} <= set(reader.fieldnames):
            raise ValueError("labels.csv must contain bearing_id,class_id")
        for row in reader:
            bearing_id = row["bearing_id"].strip().upper()
            value = int(row["class_id"])
            if value not in (0,1):
                raise ValueError(f"Invalid binary label: {value}")
            if bearing_id in labels and labels[bearing_id] != value:
                raise ValueError(f"Conflicting labels for {bearing_id}")
            labels[bearing_id] = value
    if not labels:
        raise ValueError("Label manifest is empty")
    return labels


def load_two_channel_csv(path: Path) -> tuple[np.ndarray,np.ndarray]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames or not {"vibration", "motor_current"} <= set(reader.fieldnames):
            raise ValueError(f"{path}: requires vibration,motor_current columns")
        vibration, current = [], []
        for row in reader:
            vibration.append(float(row["vibration"]))
            current.append(float(row["motor_current"]))
    if not vibration:
        raise ValueError(f"{path}: no samples")
    return np.asarray(vibration), np.asarray(current)


def build(
    input_dir: Path, label_manifest: Path, output: Path,
    sample_rate_hz: float=64000.0, window_size: int=8192, stride: int=8192,
) -> int:
    if window_size < 32 or stride < 1:
        raise ValueError("Invalid window size or stride")
    labels = load_labels(label_manifest)
    rows = []
    for path in sorted(input_dir.rglob("*.csv")):
        match = BEARING_CODE.search(path.stem)
        if not match:
            raise ValueError(f"Filename lacks a bearing ID: {path.name}")
        bearing_id = match.group(1).upper()
        if bearing_id not in labels:
            raise ValueError(f"No verified class label for bearing {bearing_id}")
        vib, cur = load_two_channel_csv(path)
        for offset in range(0, len(vib)-window_size+1, stride):
            values = extract_features(
                vib[offset:offset+window_size],
                cur[offset:offset+window_size],
                sample_rate_hz,
            )
            rows.append([path.name, bearing_id, labels[bearing_id],
                         offset, *[float(x) for x in values]])
    if not rows:
        raise RuntimeError("No complete input windows found. Add labelled source CSV files.")
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("w",newline="",encoding="utf-8") as out:
        writer = csv.writer(out)
        writer.writerow(["source_file","bearing_id","class_id",
                         "window_start_sample",*FEATURE_NAMES])
        writer.writerows(rows)
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input",type=Path,required=True)
    parser.add_argument("--labels",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--sample-rate",type=float,default=64000.0)
    parser.add_argument("--window",type=int,default=8192)
    parser.add_argument("--stride",type=int,default=8192)
    args=parser.parse_args()
    n=build(args.input,args.labels,args.output,args.sample_rate,args.window,args.stride)
    print(f"Extracted {n} feature windows from recorded bearing signals into {args.output}")
    print("IMPORTANT: No neural network was trained or assessed by this command.")


if __name__=="__main__":
    main()

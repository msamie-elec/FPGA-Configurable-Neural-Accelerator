"""Read and validate trained bearing-model manifests; program existing FPGA UART.

Refuses corrupted or incomplete model files rather than silently loading
zero weights. The FPGA protocol itself performs no authenticity verification.
"""
from __future__ import annotations

import json
from pathlib import Path
import numpy as np

from .features import FEATURE_NAMES
from .train_export import encode_features, fixed_infer

SIZES=(16,8,2)


def read_model(path):
    record=json.loads(Path(path).read_text(encoding="utf-8"))
    if record.get("format")!="fpga-bearing-int8-v1":
        raise ValueError("Unrecognised bearing-model format")
    if record.get("input_size")!=8 or tuple(record.get("layer_sizes",[]))!=SIZES:
        raise ValueError("This bearing application expects the 8→16→8→2 model")
    if tuple(record.get("feature_names",[]))!=FEATURE_NAMES:
        raise ValueError("Feature order differs from trained model")
    shift=record.get("shift")
    if not isinstance(shift,int) or not 0<=shift<=15:
        raise ValueError("Invalid FPGA right shift")
    widths=(8,16,8,2)
    weights=record["weights"]
    biases=record["biases"]
    for l in range(3):
        if len(weights[l])!=widths[l+1] or len(biases[l])!=widths[l+1]:
            raise ValueError("Incorrect neuron count in model")
        for neuron in weights[l]:
            if len(neuron)!=widths[l]:
                raise ValueError("Incorrect input width in model")
            if any(type(w)!=int or not -128<=w<=127 for w in neuron):
                raise ValueError("Invalid signed INT8 model weight")
        if any(type(b)!=int or not -(1<<31)<=b<(1<<31) for b in biases[l]):
            raise ValueError("Invalid signed INT32 bias")
    for key in ("feature_center","feature_scale"):
        values=np.asarray(record[key],dtype=float)
        if values.shape!=(8,) or not np.all(np.isfinite(values)):
            raise ValueError(f"Invalid {key}")
    if any(s<=0 for s in record["feature_scale"]):
        raise ValueError("Preprocessing scale must be positive")
    return record


def measurement_to_int8(features,record):
    x=np.asarray(features,dtype=float)
    if x.shape!=(8,) or not np.all(np.isfinite(x)):
        raise ValueError("Eight finite measured feature values required")
    return encode_features(x,np.asarray(record["feature_center"]),
                            np.asarray(record["feature_scale"])).tolist()


def reference_prediction(features,record):
    q=measurement_to_int8(features,record)
    outputs,pred=fixed_infer(q,record["weights"],record["biases"],record["shift"])
    return q,outputs,pred


def load_fpga_model(board,record,progress=None):
    """Program weights/biases to the existing UART NPU. Wait for ACK per write."""
    previous=8
    total=sum(w*p for p,w in zip((8,16,8),(16,8,2)))
    done=0
    for layer,width in enumerate(SIZES):
        for neuron in range(width):
            for feature in range(previous):
                board.write_weight(layer*1024 + neuron*32 + feature,
                                   record["weights"][layer][neuron][feature])
                done+=1
                if progress and (done%32==0 or done==total):
                    progress(done,total)
            board.write_bias(layer*32+neuron,record["biases"][layer][neuron])
        previous=width
    board.configure(8,SIZES,shift=record["shift"])

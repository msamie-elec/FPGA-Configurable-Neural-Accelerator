"""Train a grouped binary bearing classifier, quantise to EXACT Arty A7 NPU math.

Requires verified physical bearing labels and real features.csv from the
Paderborn recordings. No synthetic motor/bearing training data is supplied.
The held-out bearing IDs are never used for fitting scalers or model selection.
"""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import accuracy_score, balanced_accuracy_score, confusion_matrix, f1_score
from .features import FEATURE_NAMES

SIZES=(16,8,2)
INPUT_GAIN=20.0


def read_features(path: Path):
    with path.open(newline="",encoding="utf-8-sig") as f:
        records=list(csv.DictReader(f))
    required={"bearing_id","class_id","source_file","window_start_sample",*FEATURE_NAMES}
    if not records or not required <= set(records[0]):
        raise ValueError("Missing real-source metadata, labels or one of the eight features")
    x=np.asarray([[float(r[k]) for k in FEATURE_NAMES] for r in records],dtype=np.float64)
    y=np.asarray([int(r["class_id"]) for r in records],dtype=int)
    groups=np.asarray([r["bearing_id"].strip().upper() for r in records])
    if not np.all(np.isfinite(x)) or not set(y).issubset({0,1}):
        raise ValueError("Invalid features or binary labels")
    uniq=np.unique(groups)
    if len(uniq)<8 or any(len(np.unique(groups[y==c]))<3 for c in (0,1)):
        raise ValueError("Need >=8 bearings, with >=3 distinct physical bearings in each class")
    for g in uniq:
        if len(set(y[groups==g]))!=1:
            raise ValueError(f"Conflicting labels within bearing {g}")
    return records,x,y,groups


def split_groups(y,groups,seed=20261125):
    """Stratified group split. All 3 partitions must contain each class."""
    for attempt in range(50):
        rng=seed+attempt
        fold=StratifiedGroupKFold(n_splits=4,shuffle=True,random_state=rng)
        for pool,test in fold.split(np.zeros(len(y)),y,groups):
            if len(set(y[test]))!=2 or len(set(y[pool]))!=2:
                continue
            inner=StratifiedGroupKFold(n_splits=3,shuffle=True,random_state=rng+101)
            for train,val in inner.split(np.zeros(len(pool)),y[pool],groups[pool]):
                train,val=pool[train],pool[val]
                if len(set(y[train]))==len(set(y[val]))==2:
                    sets=[set(groups[idx]) for idx in (train,val,test)]
                    if all(not sets[a].intersection(sets[b]) for a,b in ((0,1),(0,2),(1,2))):
                        return train,val,test
    raise ValueError("Unable to find disjoint healthy/damaged bearing-level train/val/test split")


def calibration(x_train):
    center=np.median(x_train,axis=0)
    q25=np.percentile(x_train,25,axis=0)
    q75=np.percentile(x_train,75,axis=0)
    scale=(q75-q25)/1.349
    # Avoid division by zero for constant features.
    fallback=np.maximum(np.std(x_train,axis=0),1e-9)
    scale=np.where(scale>1e-9,scale,fallback)
    return center,scale


def encode_features(x,center,scale):
    q=np.clip(np.rint((np.asarray(x)-center)/scale*INPUT_GAIN),-128,127)
    return q.astype(np.int16)


def fixed_infer(features,weights,biases,shift):
    """Exact signed arithmetic order used by npu_scalable_core.sv."""
    activations=[int(v) for v in features]
    for layer,(wmat,bs) in enumerate(zip(weights,biases)):
        out=[]
        for w,b in zip(wmat,bs):
            total=int(b)+sum(int(a)*int(ww) for a,ww in zip(activations,w))
            value=max(-128,min(127,total >> shift))
            if layer<len(weights)-1:
                value=max(0,value)
            out.append(value)
        activations=out
    return activations, int(np.argmax(activations))


def fixed_predict(xq,weights,biases,shift):
    return np.asarray([fixed_infer(row,weights,biases,shift)[1] for row in xq],dtype=int)


def export_integer(model,xq_calibration,shift):
    """Map sklearn ReLU layers to NPU global-shift INT8 arithmetic.

    Output channel 0 is constant 0 and channel 1 is binary decision logit.
    Quantized activation scales are chosen using TRAIN-ONLY examples.
    """
    if tuple(model.hidden_layer_sizes)!=(16,8):
        raise ValueError("Expected 8→16→8→2 hardware topology")
    a=np.asarray(xq_calibration,dtype=np.float64)
    scales=[1.0]
    matrices=[];biases=[]
    for l,(w,b) in enumerate(zip(model.coefs_,model.intercepts_)):
        float_layer=a@w+b
        is_last=l==len(model.coefs_)-1
        if not is_last:
            a=np.maximum(float_layer,0)
            level=np.percentile(np.abs(a),99)
        else:
            level=np.percentile(np.abs(float_layer),99)
        max_weight=float(np.max(np.abs(w)))
        # Avoid parameter overflow and reserve headroom.
        limit=(115*scales[-1])/max((1<<shift)*max_weight,1e-12)
        outscale=min(80.0/max(float(level),0.1),64.0,limit)
        outscale=max(outscale,1e-6)
        int_w=np.rint(w*(1<<shift)*outscale/scales[-1])
        int_b=np.rint(b*(1<<shift)*outscale)
        if np.any(np.abs(int_w)>127) or np.any(np.abs(int_b)>2**31-1):
            raise ArithmeticError("Quantised model parameters overflow FPGA representation")
        if is_last:
            matrices.append([[0]*w.shape[0], [int(v) for v in int_w[:,0]]])
            biases.append([0,int(int_b[0])])
        else:
            matrices.append(int_w.T.astype(int).tolist())
            biases.append(int_b.astype(int).tolist())
        scales.append(outscale)
    return matrices,biases,scales


def stats(y_true,pred):
    cm=confusion_matrix(y_true,pred,labels=[0,1])
    return {
        "samples":len(y_true),
        "confusion_matrix_rows_actual_0_1":cm.tolist(),
        "accuracy":float(accuracy_score(y_true,pred)),
        "balanced_accuracy":float(balanced_accuracy_score(y_true,pred)),
        "damaged_recall":float(cm[1,1]/max(1,cm[1].sum())),
        "false_alarm_rate":float(cm[0,1]/max(1,cm[0].sum())),
        "f1_damaged":float(f1_score(y_true,pred,zero_division=0)),
    }


def train(path:Path,out:Path,seed:int=20261125):
    rows,x,y,groups=read_features(path)
    train_ids,val_ids,test_ids=split_groups(y,groups,seed)
    center,scale=calibration(x[train_ids])
    xq=encode_features(x,center,scale)
    best=None
    trials=[]
    for shift in (4,5,6):
        for alpha in (0.0001,0.01):
            model=MLPClassifier(hidden_layer_sizes=(16,8),activation="relu",
                solver="lbfgs",alpha=alpha,random_state=seed,max_iter=500)
            model.fit(xq[train_ids],y[train_ids])
            wi,bi,acts=export_integer(model,xq[train_ids],shift)
            pred=fixed_predict(xq[val_ids],wi,bi,shift)
            measured=stats(y[val_ids],pred)
            trials.append({"shift":shift,"alpha":alpha,"validation":measured})
            key=(measured["f1_damaged"],measured["balanced_accuracy"])
            if best is None or key>best[0]:
                best=(key,shift,alpha,wi,bi,acts)
    _,shift,alpha,wi,bi,acts=best
    # Evaluate test set ONCE after selecting quantized model from validation.
    test_pred=fixed_predict(xq[test_ids],wi,bi,shift)
    val_pred=fixed_predict(xq[val_ids],wi,bi,shift)
    test_stats=stats(y[test_ids],test_pred)
    val_stats=stats(y[val_ids],val_pred)
    eligible=(test_stats["balanced_accuracy"]>=0.75 and
              test_stats["damaged_recall"]>=0.75 and
              test_stats["false_alarm_rate"]<=0.25)
    result={
        "format":"fpga-bearing-int8-v1",
        "model_type":"group_evaluated_paderborn_binary_bearing",
        "model_status":"held_out_acceptance_passed" if eligible else "experimental_quality_not_accepted",
        "dataset_provenance":"User-supplied Paderborn measured feature table; verify source and licence.",
        "feature_names":list(FEATURE_NAMES),
        "classes":["Healthy bearing","Damaged bearing"],
        "input_size":8,"layer_sizes":list(SIZES),"shift":shift,
        "feature_center":center.tolist(),"feature_scale":scale.tolist(),
        "input_gain":INPUT_GAIN,
        "weights":wi,"biases":bi,
        "validation":val_stats,"held_out_test":test_stats,
        "bearing_groups":{
            "train":sorted(set(groups[train_ids])),
            "validation":sorted(set(groups[val_ids])),
            "test":sorted(set(groups[test_ids])),
        },
        "selection":{"alpha":alpha,"seed":seed,"candidates":trials},
        "runtime_integer_math":"signed INT8 * INT8, INT32 sum+bias, >>shift, signed saturation, hidden ReLU; class0 logit is zero",
    }
    out.mkdir(parents=True,exist_ok=True)
    (out/"bearing_model.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    with (out/"held_out_examples.csv").open("w",newline="",encoding="utf-8") as file:
        writer=csv.writer(file)
        writer.writerow(["source_file","bearing_id","class_id","window_start_sample",
                          *FEATURE_NAMES,*[f"int8_{s}" for s in FEATURE_NAMES],
                          "fpga_reference_class","score0","score1"])
        for i in test_ids:
            scores,pred=fixed_infer(xq[i],wi,bi,shift)
            writer.writerow([rows[i]["source_file"],groups[i],int(y[i]),
                rows[i]["window_start_sample"],*[float(t) for t in x[i]],
                *[int(t) for t in xq[i]],pred,*scores])
    print("Held-out bearing-level test:",test_stats)
    print("Trained model exported:",out/"bearing_model.json")
    print("Measured test examples exported:",out/"held_out_examples.csv")
    print("Model status:",result["model_status"])
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--features",type=Path,required=True)
    p.add_argument("--output",type=Path,default=Path("build/bearing/trained"))
    p.add_argument("--seed",type=int,default=20261125)
    args=p.parse_args()
    train(args.features,args.output,args.seed)


if __name__=="__main__":
    main()

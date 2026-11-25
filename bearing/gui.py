#!/usr/bin/env python3
"""Measured bearing-condition GUI. Requires an actually trained model and
held-out examples exported from real Paderborn recordings.

Launch: py -m bearing.gui
"""
import csv
import threading
import tkinter as tk
from tkinter import filedialog,messagebox,ttk
from pathlib import Path
import sys

from .features import FEATURE_NAMES
from .model_io import load_fpga_model,read_model,reference_prediction
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"host"))
from npu_serial import NpuBoard


class BearingGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("FPGA Bearing Condition Monitoring — measured samples")
        self.geometry("1050x740")
        self.model=None
        self.board=None
        self.loaded=False
        self.examples=[]
        self.values=[]
        self.active=None
        self.busy=False
        self.port=tk.StringVar(value="COM4")
        self.status=tk.StringVar(value="Load a verified bearing-model file and held-out examples.")
        self.model_status=tk.StringVar(value="No trained bearing model selected")
        self.result=tk.StringVar(value="No prediction")
        self.case_name=tk.StringVar()
        self.examples_path=tk.StringVar(value="build/bearing/trained/held_out_examples.csv")
        self.model_path=tk.StringVar(value="build/bearing/trained/bearing_model.json")
        self.controls=[]
        self._ui()

    def _ui(self):
        frame=ttk.Frame(self,padding=14)
        frame.pack(fill="both",expand=True)
        ttk.Label(frame,text="FPGA Bearing Health: Healthy vs Damaged",
                  font=("Segoe UI",18,"bold")).pack(anchor="w")
        ttk.Label(frame,text="Real labelled bearing recordings → 8 derived signal features → INT8 FPGA inference",
                  foreground="#5a7185").pack(anchor="w",pady=(2,8))
        ttk.Label(frame,text="Only a model trained from real recordings can support a bearing-health interpretation.",
                  foreground="#9b5a1d").pack(anchor="w",pady=(0,10))
        for label,variable,command in [
            ("Model JSON",self.model_path,self._pick_model),
            ("Held-out real examples CSV",self.examples_path,self._pick_examples),
        ]:
            row=ttk.Frame(frame)
            row.pack(fill="x",pady=4)
            ttk.Label(row,text=label,width=23).pack(side="left")
            ttk.Entry(row,textvariable=variable).pack(side="left",fill="x",expand=True,padx=5)
            ttk.Button(row,text="Browse",command=command).pack(side="left")
        ttk.Button(frame,text="Load model and measured examples",command=self._load_files).pack(anchor="w",pady=5)
        ttk.Label(frame,textvariable=self.model_status,wraplength=1000).pack(anchor="w")
        row=ttk.Frame(frame)
        row.pack(fill="x",pady=(14,8))
        ttk.Label(row,text="Measured reference example",width=26).pack(side="left")
        self.cases=ttk.Combobox(row,state="readonly",textvariable=self.case_name,width=70)
        self.cases.pack(side="left",fill="x",expand=True)
        self.cases.bind("<<ComboboxSelected>>",self._select_case)
        ttk.Button(row,text="Restore measured values",command=self._select_case).pack(side="left",padx=5)
        ttk.Label(frame,text="Measurements shown in source-record units (unverified calibration); adjusting a value creates a hypothetical, not measured, example.",
                  wraplength=1000,foreground="#9b5a1d").pack(anchor="w")
        table=ttk.Frame(frame)
        table.pack(fill="x",pady=8)
        for i,name in enumerate(FEATURE_NAMES):
            row=ttk.Frame(table)
            row.pack(fill="x",pady=2)
            ttk.Label(row,text=name.replace("_"," "),width=32).pack(side="left")
            value=tk.StringVar(value="0")
            self.values.append(value)
            ttk.Entry(row,textvariable=value,width=16).pack(side="left",padx=6)
        action=ttk.Frame(frame)
        action.pack(fill="x",pady=(12,6))
        ttk.Label(action,text="Arty A7 COM port").pack(side="left")
        ttk.Entry(action,textvariable=self.port,width=12).pack(side="left",padx=7)
        self.connect_btn=ttk.Button(action,text="Connect",command=self._connect)
        self.connect_btn.pack(side="left",padx=6)
        self.program_btn=ttk.Button(action,text="Program TRAINED model",command=self._program)
        self.program_btn.pack(side="left",padx=6)
        self.infer_btn=ttk.Button(action,text="Run FPGA inference",command=self._infer)
        self.infer_btn.pack(side="left",padx=6)
        ttk.Button(action,text="Python reference only",command=self._preview).pack(side="left",padx=6)
        ttk.Label(frame,textvariable=self.status,wraplength=1000).pack(anchor="w",pady=(8,2))
        ttk.Label(frame,textvariable=self.result,font=("Segoe UI",12,"bold"),wraplength=1000).pack(anchor="w",pady=7)

    def _pick_model(self):
        path=filedialog.askopenfilename(filetypes=[("Model manifest","*.json")])
        if path:self.model_path.set(path)

    def _pick_examples(self):
        path=filedialog.askopenfilename(filetypes=[("Feature tables","*.csv")])
        if path:self.examples_path.set(path)

    def _load_files(self):
        try:
            model=read_model(self.model_path.get())
            with open(self.examples_path.get(),newline="",encoding="utf-8-sig") as file:
                examples=list(csv.DictReader(file))
            if not examples or not all(k in examples[0] for k in
                     ("bearing_id","class_id","source_file",*FEATURE_NAMES)):
                raise ValueError("Expected held-out example CSV from bearing/train_export.py")
            held=set(model["bearing_groups"]["test"])
            if any(r["bearing_id"] not in held for r in examples):
                raise ValueError("One or more examples do not belong to held-out bearings")
            self.model=model
            self.loaded=False
            self.examples=examples
            names=[]
            for i,r in enumerate(examples):
                class_name="Healthy" if int(r["class_id"])==0 else "Damaged"
                names.append(f"{i+1:03d} | {class_name} | {r['bearing_id']} | {r['source_file']} | window {r['window_start_sample']}")
            self.cases.configure(values=names)
            self.cases.current(0)
            self._select_case()
            s=model["model_status"]
            self.model_status.set(f"Loaded {s} • 8→16→8→2 • held-out balanced accuracy "
                f"{model['held_out_test']['balanced_accuracy']:.3f} • "
                f"damaged recall {model['held_out_test']['damaged_recall']:.3f}")
            self.status.set("Model file loaded locally. Program the FPGA before hardware inference.")
        except Exception as exc:
            self.model=None
            messagebox.showerror("Invalid model/examples",str(exc))

    def _select_case(self,_event=None):
        i=self.cases.current()
        if i<0 or i>=len(self.examples):return
        self.active=self.examples[i]
        for key,var in zip(FEATURE_NAMES,self.values):
            var.set(self.active[key])
        self.result.set("Measured case selected; no prediction yet")

    def _measurements(self):
        if self.model is None:raise ValueError("Load a trained bearing model first")
        return [float(v.get()) for v in self.values]

    def _preview(self):
        try:
            q,output,pred=reference_prediction(self._measurements(),self.model)
            meaning=self.model["classes"][pred]
            truth=("(record label: "+("Healthy" if self.active["class_id"]=="0" else "Damaged")+")") if self.active else ""
            self.result.set(f"Python fixed-point model → {meaning} {truth} | scores {output} | INT8 features {q}")
        except Exception as exc:
            messagebox.showerror("Reference model",str(exc))

    def _background(self,work,callback):
        if self.busy:return
        self.busy=True
        for c in (self.connect_btn,self.program_btn,self.infer_btn):c.configure(state="disabled")
        def job():
            try:
                value=work()
                self.after(0,lambda:callback(value))
            except Exception as exc:
                self.after(0,lambda message=str(exc):messagebox.showerror("FPGA communication",message))
            finally:
                self.after(0,self._unlock)
        threading.Thread(target=job,daemon=True).start()

    def _unlock(self):
        self.busy=False
        for c in (self.connect_btn,self.program_btn,self.infer_btn):c.configure(state="normal")

    def _connect(self):
        def work():
            board=NpuBoard.open(self.port.get(),timeout=3)
            try:board.ping()
            except Exception:
                board.close();raise
            return board
        def callback(board):
            if self.board:self.board.close()
            self.board=board
            self.loaded=False
            self.status.set("Connected to FPGA via UART. Load trained model next.")
        self._background(work,callback)

    def _program(self):
        if self.model is None or self.board is None:
            messagebox.showwarning("Not ready","Load the model and connect to the FPGA first.")
            return
        model=self.model
        def work():
            load_fpga_model(self.board,model)
            return True
        def done(_value):
            self.loaded=True
            self.status.set("Model weights/biases loaded into FPGA from bearing_model.json")
        self._background(work,done)

    def _infer(self):
        if not self.board or not self.loaded or not self.model:
            messagebox.showwarning("Not ready","Connect and program the trained bearing model first.")
            return
        try:
            q,golden,pred=reference_prediction(self._measurements(),self.model)
        except Exception as exc:
            messagebox.showerror("Invalid measurements",str(exc));return
        def done(answer):
            matches=tuple(golden)==answer.scores[:2] and pred==answer.class_index
            label=self.model["classes"][answer.class_index]
            self.result.set(f"FPGA: {label} | FPGA scores {answer.scores[:2]} | "
                            f"Python scores {golden} | "
                            +("BIT-EXACT MATCH" if matches else "MISMATCH — do not rely on prediction"))
        self._background(lambda:self.board.infer(q),done)


if __name__=="__main__":
    BearingGUI().mainloop()

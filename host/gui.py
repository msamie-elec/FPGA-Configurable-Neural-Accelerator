#!/usr/bin/env python3
"""Interactive PC GUI for Arty A7 configurable neural accelerator.

This application loads deterministic demo weights. They are not trained and
must not be interpreted as reliable industrial anomaly/fault predictions.
Requires a live board using arty_a7_uart_npu_top and the USB-UART port.
"""
import threading
import tkinter as tk
from tkinter import messagebox, ttk
from tkinter.scrolledtext import ScrolledText

from npu_serial import NpuBoard
from reference_scalable import infer as reference_infer

MODELS = {
    "4 → 8 → 4 → 2": (4, (8, 4, 2)),
    "8 → 16 → 8 → 2": (8, (16, 8, 2)),
    "32 → 32 → 32 → 32 → 8": (32, (32, 32, 32, 8)),
}


class AcceleratorGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("FPGA Edge AI | Arty A7 | Configurable INT8 Inference")
        self.geometry("1000x760")
        self.board = None
        self.loaded_model = None
        self.working = False
        self.sensor_vars = []
        self.model_var = tk.StringVar(value="8 → 16 → 8 → 2")
        self.port_var = tk.StringVar(value="COM3")
        self.connection_var = tk.StringVar(value="Disconnected")
        self.result_var = tk.StringVar(value="No inference performed")
        self.progress_var = tk.StringVar(value="Load a model to begin")
        self._build()
        self._rebuild_sensors()

    def _build(self):
        header = ttk.Frame(self, padding=12)
        header.pack(fill="x")
        ttk.Label(header, text="Configurable FPGA Neural Accelerator",
                  font=("Segoe UI", 17, "bold")).pack(anchor="w")
        ttk.Label(header, text="8 shared INT8 MAC lanes • Runtime model loading • 100 MHz FPGA clock",
                  foreground="#59758d").pack(anchor="w", pady=(4, 0))
        ttk.Label(header,
                  text="Demonstration weights only — not a trained or validated industrial fault detector.",
                  foreground="#a65e16").pack(anchor="w", pady=(6, 0))

        toolbar = ttk.Frame(self, padding=(12, 8))
        toolbar.pack(fill="x")
        ttk.Label(toolbar, text="USB serial port").pack(side="left")
        ttk.Entry(toolbar, textvariable=self.port_var, width=12).pack(side="left", padx=6)
        self.connect_btn = ttk.Button(toolbar, text="Connect", command=self._connect)
        self.connect_btn.pack(side="left", padx=4)
        ttk.Label(toolbar, textvariable=self.connection_var).pack(side="left", padx=10)

        config = ttk.Frame(self, padding=(12, 8))
        config.pack(fill="x")
        ttk.Label(config, text="Neural network").pack(side="left")
        self.model_selector = ttk.Combobox(config, textvariable=self.model_var, state="readonly",
                                values=list(MODELS), width=29)
        self.model_selector.pack(side="left", padx=8)
        self.model_selector.bind("<<ComboboxSelected>>", lambda _e: self._rebuild_sensors())
        self.load_btn = ttk.Button(config, text="Load example weights into FPGA",
                                   command=self._load_model)
        self.load_btn.pack(side="left", padx=6)
        ttk.Label(config, textvariable=self.progress_var).pack(side="left", padx=8)

        body = ttk.Panedwindow(self, orient="horizontal")
        body.pack(fill="both", expand=True, padx=12, pady=8)
        left = ttk.Frame(body)
        right = ttk.Frame(body)
        body.add(left, weight=2)
        body.add(right, weight=1)
        ttk.Label(left, text="Sensor input values (signed INT8: −128 to 127)",
                  font=("Segoe UI", 11, "bold")).pack(anchor="w", pady=(0, 5))
        ttk.Label(left, text="Use the mouse or keyboard up/down arrows to change values.",
                  foreground="#59758d").pack(anchor="w")
        canvas = tk.Canvas(left, highlightthickness=0)
        scroll = ttk.Scrollbar(left, orient="vertical", command=canvas.yview)
        canvas.configure(yscrollcommand=scroll.set)
        scroll.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True)
        self.sensor_frame = ttk.Frame(canvas)
        sensor_window = canvas.create_window((0, 0), window=self.sensor_frame, anchor="nw")
        self.sensor_frame.bind("<Configure>",
                               lambda _e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.bind("<Configure>", lambda e: canvas.itemconfigure(sensor_window,width=e.width))
        canvas.bind_all("<MouseWheel>",
                        lambda e: canvas.yview_scroll(-int(e.delta/120), "units"))
        ttk.Label(right, text="Inference output",
                  font=("Segoe UI", 11, "bold")).pack(anchor="w", pady=(0, 8))
        self.infer_btn = ttk.Button(right, text="Run inference on FPGA",
                                    command=self._infer)
        self.infer_btn.pack(fill="x", pady=(0, 10))
        ttk.Button(right, text="Preview in Python (no board required)",
                   command=self._preview).pack(fill="x", pady=(0, 10))
        ttk.Button(right, text="Reset sensor inputs to zero",
                   command=self._clear_inputs).pack(fill="x")
        ttk.Label(right, textvariable=self.result_var, wraplength=280,
                  font=("Segoe UI", 11)).pack(anchor="w", pady=16)
        ttk.Label(right, text="Raw signed INT8 output scores").pack(anchor="w")
        self.scores = ScrolledText(right, height=10, width=28, state="disabled")
        self.scores.pack(fill="both", expand=True, pady=6)
        ttk.Label(self, text="Hardware execution requires the new FPGA UART bitstream; "
                  "running the GUI alone does not perform FPGA inference.",
                  foreground="#59758d").pack(anchor="w", padx=14, pady=(0, 10))

    def _rebuild_sensors(self):
        for child in self.sensor_frame.winfo_children():
            child.destroy()
        count,_ = MODELS[self.model_var.get()]
        self.sensor_vars=[]
        for index in range(count):
            item=ttk.Frame(self.sensor_frame,padding=(8,4))
            item.pack(fill="x")
            ttk.Label(item,text=f"Sensor {index+1:02d}",width=12).pack(side="left")
            value=tk.IntVar(value=0)
            self.sensor_vars.append(value)
            spin=ttk.Spinbox(item,from_=-128,to=127,increment=1,
                             textvariable=value,width=7)
            spin.pack(side="left",padx=5)
            slider=ttk.Scale(item,from_=-128,to=127,orient="horizontal",
                             command=lambda v,variable=value:variable.set(round(float(v))))
            slider.set(0)
            slider.pack(side="left",fill="x",expand=True,padx=6)
            value.trace_add("write",
                lambda *_args,s=slider,v=value: self._set_slider(s,v))
        self.result_var.set("Model selected. Load weights before inferring.")

    @staticmethod
    def _set_slider(slider, value):
        try:
            n=max(-128,min(127,int(value.get())))
            if abs(slider.get()-n)>=0.6:
                slider.set(n)
        except (ValueError,tk.TclError):
            pass

    def _clear_inputs(self):
        for v in self.sensor_vars:
            v.set(0)

    def _busy(self, busy):
        self.working=busy
        state="disabled" if busy else "normal"
        self.connect_btn.configure(state=state)
        self.load_btn.configure(state=state)
        self.infer_btn.configure(state=state)
        self.model_selector.configure(state='disabled' if busy else 'readonly')

    def _worker(self, action, completed):
        if self.working:
            return
        self._busy(True)
        def run():
            try:
                result=action()
                self.after(0,lambda: completed(result))
            except Exception as exc:
                self.after(0,lambda msg=str(exc):messagebox.showerror("FPGA communication",msg))
            finally:
                self.after(0,lambda:self._busy(False))
        threading.Thread(target=run,daemon=True).start()

    def _connect(self):
        self.loaded_model = None
        if self.board:
            try:self.board.close()
            except Exception:pass
            self.board=None
        port=self.port_var.get().strip()
        def connect():
            board=NpuBoard.open(port,timeout=3.0)
            try:board.ping()
            except Exception:
                board.close()
                raise
            return board
        def completed(board):
            self.board=board
            self.connection_var.set(f"Connected: {port}, 115200 8N1")
            self.progress_var.set("Choose and load a model")
        self._worker(connect,completed)

    def _load_model(self):
        if not self.board:
            messagebox.showwarning("No connection","Connect to the Arty A7 first.")
            return
        model_name=self.model_var.get()
        inputs,widths=MODELS[model_name]
        def progress(done,total):
            if done==total or done%128==0:
                self.after(0,lambda d=done,t=total:self.progress_var.set(f"Loading {d}/{t} weights"))
        def work():
            self.board.load_demo_model(inputs,widths,progress=progress)
            return f"Loaded: {inputs} → " + " → ".join(str(x) for x in widths)
        def completed(message):
            self.loaded_model=model_name
            self.progress_var.set(message)
            self.result_var.set("Model loaded; adjust sensors then run inference")
        self._worker(work,completed)

    def _infer(self):
        if not self.board:
            messagebox.showwarning("No connection","Connect to the Arty A7 first.")
            return
        if self.loaded_model != self.model_var.get():
            messagebox.showwarning("Model not loaded", "Load the selected model into the FPGA first.")
            return
        try:
            inputs,widths=MODELS[self.model_var.get()]
            values=[int(v.get()) for v in self.sensor_vars[:inputs]]
            if any(v<-128 or v>127 for v in values):
                raise ValueError("Sensor inputs must be signed INT8.")
        except ValueError as exc:
            messagebox.showerror("Invalid inputs",str(exc))
            return
        def work():
            return self.board.infer(values)
        def completed(result):
            golden, expected_class = reference_infer(values, widths)
            matched = (tuple(golden) == result.scores[:widths[-1]]
                       and expected_class == result.class_index)
            self.result_var.set(
                f"FPGA class: {result.class_index} | Python class: {expected_class}\n"
                + ("Bit-exact MATCH" if matched else "MISMATCH — inspect board/model"))
            self.scores.configure(state="normal")
            self.scores.delete("1.0","end")
            self.scores.insert("end", "\n".join(
                f"Output {i}: {score}" for i,score in enumerate(result.scores[:widths[-1]])))
            self.scores.configure(state="disabled")
        self._worker(work,completed)

    def _preview(self):
        try:
            inputs,widths=MODELS[self.model_var.get()]
            values=[int(v.get()) for v in self.sensor_vars[:inputs]]
            if any(v<-128 or v>127 for v in values):
                raise ValueError("Sensor inputs must be signed INT8.")
            score,winner=reference_infer(values,widths)
        except ValueError as exc:
            messagebox.showerror("Invalid sensor inputs",str(exc))
            return
        self.result_var.set(f"Python-only reference class: {winner}\n"
                            "No FPGA hardware was used")
        self.scores.configure(state="normal")
        self.scores.delete("1.0","end")
        self.scores.insert("end", "\n".join(
            f"Reference output {i}: {s}" for i,s in enumerate(score)))
        self.scores.configure(state="disabled")


if __name__=="__main__":
    AcceleratorGUI().mainloop()

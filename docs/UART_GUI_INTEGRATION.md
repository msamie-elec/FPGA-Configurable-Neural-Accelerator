# V0.4 — UART / Arty A7 / Python GUI integration

**Status: integrated RTL simulation and host protocol unit tests verified in CI. The integrated design has not yet been placed, routed, or physically tested on an FPGA.**

## Hardware target

- Digilent **Arty A7-35T**, XC7A35T-1L, on-board 100 MHz oscillator
- Integrated FPGA top: `rtl/arty_a7_uart_npu_top.sv`
- USB-UART: 115200 baud, 8 data bits, no parity, one stop bit, no hardware flow control
- System clock pin **E3**, host-to-FPGA serial RX **A9**, FPGA-to-host serial TX **D10**, reset BTN1 **C9**, LEDs **H5/J5/T9/T10**.
- Source of UART pin assignments: [Digilent's Arty-A7-35 master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Arty-A7-35-Master.xdc)
- BTN1 reset is active high. Four LEDs: class 0, class 1, result seen and inference busy. Classes 2–7 are available through UART but not individually decoded on LEDs.
- I/O timing: UART RX and reset inputs are asynchronous and synchronised inside FPGA; the port-to-first-flop timing paths are false-pathed. Internal synchronous paths must meet 10.000 ns. The PC UART is asynchronous and has no synchronous I/O delay requirement.

## Block hierarchy

```text
arty_a7_uart_npu_top
  └─ npu_uart_bridge
       ├─ uart_rx          (2-stage synchronizer, mid-bit sampling)
       ├─ uart_tx          (8N1 serial output)
       ├─ packet parser   (A5 command payload XOR)
       ├─ response FSM    (5A command status class scores XOR)
       └─ npu_scalable_core
            ├─ eight npu_weight_bank instances (BRAM-oriented)
            ├─ eight shared INT8 multipliers
            ├─ registered summation tree and INT32 accumulator
            ├─ biases / fixed-point activation / argmax
            └─ layer/neuron/input-group sequencer
```

## Protocol v0.4

The host uses synchronous request/reply transactions: **never send a new request until the full previous response has been read**. There is no streaming pipeline, packet timeout or collision recovery in this milestone.

Request: `A5 | command | payload (fixed length) | XOR(command + all payload bytes)`

| Command | Hex | Payload | Length |
| --- | --- | --- | ---: |
| Weight | 57 | 12-bit weight address (lo, hi), signed INT8 value | 3 |
| Bias | 42 | 7-bit bias address, signed INT32 LE | 5 |
| Configure | 43 | layer_count, input_count, size0, size1, size2, size3, shift | 7 |
| Inference | 49 | 32 signed INT8 input samples (unused slots zero) | 32 |
| Ping | 50 | none | 0 |

Response: `5A | command | status | class | score0..score7 (signed INT8) | XOR(command,status,class,all scores)` (13 bytes).

Status: 0 OK, 1 bad request XOR, 2 unsupported command, 3 core rejects invalid topology. The `I` reply is delayed until inference finishes. For writing/config/ping, scores and class are zero.

Weights: `layer*1024 + neuron*32 + feature` (0..4095).
Bias: `layer*32+neuron` (0..127).
The host must initialise **all used** weights and biases before inference. Inactive neuron/layer addresses are not read. `shift` is applied in each layer, followed by signed INT8 saturation; ReLU only on hidden layers.

Security/robustness limits: XOR is a basic transmission-integrity check, **not a robust CRC or authentication**. Current RTL has no receive framing timeout, sequence IDs, model-version handshake, retransmission/recovery, or multi-command queue. Use a reliable local USB-UART connection and reset after serial desynchronisation. These are planned hardening tasks, not completed features.

## 1. GitHub test suite (hardware not required)

In WSL/Linux with `iverilog` and Python 3:

```bash
bash scripts/test.sh
```

Includes the existing 14/26/104-neuron Python-golden tests, bit-level UART simulation that verifies weight/bias/config writes, corrupt XOR rejection, inference response and ping, integrated FPGA top elaboration, plus host protocol unit tests and GUI syntax checks.

## 2. Build the integrated FPGA project

Download a clean ZIP of this branch, extract it and from the **project root** use the Vivado 2025.2 Tcl console:

```tcl
source vivado/create_uart_npu_project.tcl
open_project build/uart_npu_project/uart_npu.xpr
```

The project includes the integrated top and `tb_npu_uart_bridge` as simulation top. Run *Flow → Run Simulation → Run Behavioral Simulation* to inspect serial and NPU FSM signals.

Or run the independent batch synthesis/place/route/bitstream script:

```tcl
source vivado/build_uart_npu.tcl
```

Outputs to `build/uart_npu/`:
`utilization_synth.rpt`, `utilization_routed.rpt`, `timing_routed.rpt`, `drc_routed.rpt`, `methodology_routed.rpt`, `uart_npu_routed.dcp` and (only if implementation proceeds) `arty_a7_uart_npu.bit`.

**Do not program the board unless implementation completes and timing/DRC are reviewed.** A generated bitstream is not proof that the host communication works physically. The scripted flow fails on negative max-delay setup slack, but you should also check hold timing, clocking, unconstrained paths, methodology and DRC status.

## 3. PC host application (Windows, with FPGA programmed)

Install Python 3.11+; open PowerShell in the repository root:

```powershell
py -m pip install -r host/requirements.txt
py host/smoke_uart.py --port COM4 --model 8
py host/gui.py
```

Choose the actual COM port from Windows Device Manager; COM4 is only an example. The GUI defaults to COM3 but the value is editable. The FPGA must be programmed with **the new `arty_a7_uart_npu.bit`**, not the original switch/LED demo.

The GUI supports model selection between 4→8→4→2, 8→16→8→2 and 32→32→32→32→8, loading signed INT8 demonstration weights via UART, up to 32 interactive signed INT8 sensor controls with mouse sliders/spinboxes and keyboard up/down arrows, one-click FPGA inference and per-class scores. The **Preview in Python** button works without a connected FPGA, and a live FPGA run compares all returned scores and the predicted class bit-for-bit against the independent Python model. Weight loading runs on a background thread so the GUI remains responsive.

**Important:** The automatically generated example weights are not trained on industrial data. FPGA classification scores therefore demonstrate arithmetic correctness, *not detection accuracy*. A future industrial demo needs representative sensor data, an actual trained/quantised model, independent labels and held-out accuracy metrics.

## 4. Hardware acceptance checklist

- Vivado 2025.2 post-route WNS >= 0 ns; no failing setup or hold endpoints.
- Inspect resource report for BRAM/DSP use, noting counts can change after integration.
- DRC and methodology: no unreviewed critical warnings.
- Verify physically with `smoke_uart.py` for all 3 selectable topologies.
- Check more than one input vector; compare FPGA scores and argmax against reference Python.
- Exercise serial checksum corruption, reset and reconnect behaviour.
- Document measured UART transfer time, inference latency, power methodology and actual board used.

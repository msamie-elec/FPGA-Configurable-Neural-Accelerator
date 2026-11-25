# Arty A7 build and hardware acceptance

Run from the repository root. Target **Arty A7-35T** first, with LANES=4 and its onboard 100 MHz oscillator. Use variant `100` if the board is the A7-100T. The S7 needs a board-specific clock, pinout and Vivado build, and has no V1 image in this release.

## 1. Build and program

In a terminal where Vivado is on PATH:

```powershell
vivado -mode batch -source hardware/vivado/build_a7.tcl -tclargs 35 4
```

This writes `hardware/build/arty_a7_35t_p4/npu.bit` after checking setup and hold slack. It also writes the routed checkpoint and timing, utilisation, CDC, DRC and estimated-power reports. Use the bitstream from this run only. Review timing and unconstrained paths in the report. UART and the pushbutton are asynchronous board inputs. LEDs and UART TX are external asynchronous observations and have no synchronous external capture clock.

Connect the A7's USB bridge and select **Open Hardware Manager → Open Target → Auto Connect → Program Device**. Program that file and tap BTN0 once. Green LED0 is busy, LED1 is valid model and LED2 is valid result. UART is 115200 8N1. List ports with `python -m serial.tools.list_ports -v` after installing pyserial.

## 2. Run the acceptance sequence

For Windows, replace `COM4` with the FTDI UART port. On Linux, replace it with the enumerated serial device, often `/dev/ttyUSB1`.

```powershell
python -m pip install pyserial
python -m serial.tools.list_ports -v
python -m verification.board_test COM4 --lanes 4 --bitstream hardware/build/arty_a7_35t_p4/npu.bit --out local_results/a7_p4.json
```

Use one programmed board throughout. The script sends A (8→16→4), B (12→8→3), A again, then 100 inputs to a 196→32→10 stress fixture. It compares every logit against the independent scalar reference and checks the committed model fingerprints. The JSON includes the input, expected and observed vectors, core counters, host job time, model load time, capability reply, Git SHA and operator-supplied programming file SHA-256. Keep the four Vivado implementation reports alongside it. The PC cannot read back or authenticate the loaded bitstream over UART, so the operator must program the same file that is passed to the script.

For the optional trained-model run, install scikit-learn and add `--trained`. It trains a 64→10 classifier from the bundled UCI digits dataset, reports the held-out floating-point and quantised accuracy, then verifies 100 held-out vectors against FPGA outputs. The example uses the ordinary model loader and contains no digit-specific RTL.

If a command times out or its reply CRC fails, tap BTN0 and rerun from the beginning. Stop-and-wait uploads intentionally use no automatic retry because the previous acknowledgement may have been lost after the FPGA applied its command.

## 3. Complete the lane comparison

Repeat the Vivado build and hardware test for lanes 1 and 8. Keep the same board, model seeds, Vivado version and 100 MHz target. Capture setup and hold slack, post-route LUT/FF/DSP/BRAM, core cycles, word reads and median host job time for each build. Label Vivado power figures as estimates. If collecting an ILA trace, probe the engine's issue, memory-read, and completion signals from a debug build and record that build separately.

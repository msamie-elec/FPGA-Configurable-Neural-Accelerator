# Power and energy assessment: method and evidence boundaries

## Existing evidence

The user-provided routed independent IP-consumer Vivado report estimated about **78 mW on-chip** (approximately 62 mW static and 16 mW dynamic); medium confidence without representative annotated SAIF. Earlier integrated UART/NPU Vivado estimated approximately 80 mW. **Neither is physical measured power.** Actual joules per inference and measured GOPS/W are not yet established.

## Reproducible Vivado estimate

Open a routed design and run a report:
~~~tcl
report_power -file build/power/power_unannotated.rpt
~~~
The power folder must exist first. Record the clock, ambient/device temperature assumptions, voltage, switching-activity confidence and vectorless/default estimates. For higher-quality estimates, capture separate idle and active inference windows in Vivado simulator, export activity as SAIF, map to the **matching** implemented design and rerun report_power. SAIF mapping is tool-specific and has not been automated or physically verified by this project.

## Optional physical measurement protocol

Use an appropriate calibrated instrument on a safely accessible supply input or isolated FPGA rail; do not probe or alter live FPGA power rails without suitable expertise. A USB inline meter measures **whole-board power**, not FPGA-only power. Maintain the same electrical scope for idle/active measurements, document ambient temperature, board version, clock, model and actual inference duty cycle.

Create a CSV of ACTUAL readings at build/power/actual_meter_readings.csv:
~~~csv
phase,scope,voltage_v,current_a,trial_id
~~~
Each row is one measured sample. Use phase=idle or phase=active, the SAME scope (e.g. whole_board_usb) and at least two readings per phase.

~~~powershell
py scripts/assess_power.py --measurements build/power/actual_meter_readings.csv
~~~

Only if you also have a measured sustained inference rate **under the same operating state**, supply it:
~~~powershell
py scripts/assess_power.py --measurements build/power/actual_meter_readings.csv --measured-fps YOUR_MEASURED_FPS
~~~
YOUR_MEASURED_FPS is a placeholder for a real number, not an estimated compute rate. The script computes mean idle/active power, incremental power and optional joules/inference. Be explicit whether the denominator measures UART transactions or an autonomous steady compute stream. Do not multiply the unannotated estimated FPGA watts by UART time and call it measured energy.

## Publication rule

Until representative SAIF and physical meter data exist, report power as **tool estimate only** and energy as **not measured**. No physically measured GOPS/W claim is permitted.

# One-command OOC core routed-power flow; Vivado Tcl Console only.
# Each stage is also independently rerunnable without rebuilding the others.
set power_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $power_root vivado build_npu_routed_power.tcl]
source [file join $power_root vivado simulate_npu_routed_power.tcl]
source [file join $power_root vivado analyze_npu_routed_power.tcl]
puts "ROUTED POWER COMPLETE: use scripts/assess_routed_power.py in PowerShell."

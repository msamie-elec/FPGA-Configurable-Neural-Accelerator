# Convenience entry point, Vivado 2025.2.1 Tcl Console:
#   source vivado/run_npu_netlist_power.tcl
# Each stage can also be run individually after a failure; rerun ONLY
# the failed stage if its preceding artifacts are still valid.
set power_root [file normalize [file join [file dirname [info script]] ..]]
source [file join $power_root vivado build_npu_netlist_power.tcl]
source [file join $power_root vivado simulate_npu_netlist_power.tcl]
source [file join $power_root vivado analyze_npu_netlist_power.tcl]
puts "NETLIST POWER FLOW COMPLETE: See build/netlist_power/reports."

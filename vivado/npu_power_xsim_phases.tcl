# Vivado XSim TCL, loaded through xsim.simulate.custom_tcl.
# The RTL testbench emits $stop before and after each phase.
# NOTE: simulator-specific script: must be verified in Vivado 2025.2.1.
if {![info exists ::env(NPU_POWER_OUT)]} {
  error "Missing NPU_POWER_OUT; run source vivado/run_npu_power_saif.tcl"
}
set power_out $::env(NPU_POWER_OUT)
file mkdir $power_out
set selected [get_objects -r /tb_npu_power_activity/u_bridge/accelerator/*]
if {[llength $selected]==0} {
  error "No accelerator signals found; cannot emit meaningful SAIF"
}
foreach phase {idle loading inference} {
  # Resume testbench to its READY_* $stop (or advance from END_*).
  run -all
  set output [file join $power_out "${phase}.saif"]
  open_saif $output
  log_saif $selected
  # Continue through the actual stimulus window to its END_* $stop.
  run -all
  close_saif
  if {![file exists $output] || [file size $output]<128} {
    error "SAIF generation failed for $phase at $output"
  }
  puts "POWER SAIF CREATED: $output ([file size $output] bytes)"
}
# Final $finish marker.
run -all
puts "THREE POWER ACTIVITY WINDOWS COMPLETED: idle / loading / inference"

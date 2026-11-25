# From repository root: vivado -mode batch -source vivado/build.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build]
file mkdir $out
set part xc7a35ticsg324-1L
read_verilog -sv [file join $root rtl npu_core.sv]
read_verilog -sv [file join $root rtl arty_a7_top.sv]
read_xdc [file join $root constraints arty_a7_35t.xdc]
synth_design -top arty_a7_top -part $part
opt_design
place_design
route_design
report_timing_summary -report_unconstrained -file [file join $out timing_summary.rpt]
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
set worst [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst] == 0} {error "No setup timing path available: review constraints"}
set slack [get_property SLACK [lindex $worst 0]]
if {$slack < 0} {error "Timing violation: worst setup slack is $slack ns"}
write_checkpoint -force [file join $out routed.dcp]
write_bitstream -force [file join $out arty_a7_npu.bit]
puts "Build complete; review reports under $out"

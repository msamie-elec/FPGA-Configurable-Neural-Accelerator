# Independent integrated UART/NPU synthesis, place, route, timing and bitstream.
# Run from anywhere: vivado -mode batch -source vivado/build_uart_npu.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build uart_npu]
file mkdir $out
set part xc7a35ticsg324-1L
foreach f {
  rtl/npu_weight_bank.sv
  rtl/npu_scalable_core.sv
  rtl/uart_8n1.sv
  rtl/npu_uart_bridge.sv
  rtl/arty_a7_uart_npu_top.sv
} {read_verilog -sv [file join $root $f]}
read_xdc [file join $root constraints arty_a7_uart_npu.xdc]
synth_design -top arty_a7_uart_npu_top -part $part
report_utilization -hierarchical -file [file join $out utilization_synth.rpt]
opt_design
place_design
route_design
report_timing_summary -report_unconstrained -file [file join $out timing_routed.rpt]
report_timing -delay_type max -max_paths 30 -nworst 1 -path_type full_clock_expanded -input_pins -file [file join $out critical_setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -nworst 1 -path_type full_clock_expanded -file [file join $out hold_paths.rpt]
report_utilization -hierarchical -file [file join $out utilization_routed.rpt]
report_drc -file [file join $out drc_routed.rpt]
report_methodology -file [file join $out methodology_routed.rpt]
set worst [get_timing_paths -delay_type max -max_paths 1]
if {[llength $worst]==0} {error "No setup timing path found"}
set slack [get_property SLACK [lindex $worst 0]]
if {$slack < 0} {error "ROUTED 100 MHz TIMING FAIL: WNS $slack ns"}
write_checkpoint -force [file join $out uart_npu_routed.dcp]
set uart_publish_source [file join $root build bitstream arty_a7_uart_npu.bit]
file mkdir [file dirname $uart_publish_source]
write_bitstream -force $uart_publish_source
set uart_publish_flow "vivado-nonproject-batch"
source [file join $root vivado publish_uart_bitstream.tcl]
puts "UART NPU ROUTED BUILD COMPLETE. Check all DRC and methodology warnings, constraints and board function."

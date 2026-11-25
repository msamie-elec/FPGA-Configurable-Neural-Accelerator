# Synthesis-only technology mapping for experimental 32-wide core.
# Run: vivado -mode batch -source vivado/synth_scalable.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build scalable_synth]
file mkdir $out
read_verilog -sv [file join $root rtl npu_weight_bank.sv]
read_verilog -sv [file join $root rtl npu_scalable_core.sv]
synth_design -top npu_scalable_core -part xc7a35ticsg324-1L
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_ram_utilization -file [file join $out ram_utilization.rpt]
write_checkpoint -force [file join $out post_synth.dcp]
puts "Scalable NPU synthesis finished. This is not a routed timing or FPGA board pass."

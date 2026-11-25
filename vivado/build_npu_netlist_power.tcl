# Build a matched core-only, post-synthesis functional NPU netlist.
# In Vivado Tcl Console, from the repository checkout:
#   source vivado/build_npu_netlist_power.tcl
# This is a NEW standalone core OOC power study, NOT the integrated UART
# routing/bitstream flow. Does not modify any prior .xpr or .bit.
set npu_root [file normalize [file join [file dirname [info script]] ..]]
set net_dir [file join $npu_root build netlist_power]
file mkdir $net_dir
catch {close_sim}
catch {close_project}
# Explicitly invoke non-project synthesis on exactly the same two core files
# that will be represented by the generated structural Verilog netlist.
read_verilog -sv [file join $npu_root rtl npu_weight_bank.sv]
read_verilog -sv [file join $npu_root rtl npu_scalable_core.sv]
synth_design -top npu_scalable_core -part xc7a35ticsg324-1L -mode out_of_context
create_clock -name core_clk -period 10.000 [get_ports clk]
set net_file [file join $net_dir npu_core_post_synth_func.v]
set checkpoint [file join $net_dir npu_core_post_synth.dcp]
write_verilog -mode funcsim -force $net_file
write_checkpoint -force $checkpoint
report_utilization -file [file join $net_dir utilization_core_synth.rpt]
if {![file exists $net_file] || [file size $net_file] < 1024} {
  error "Post-synthesis netlist not generated: $net_file"
}
if {![file exists $checkpoint] || [file size $checkpoint] < 1024} {
  error "Post-synthesis checkpoint not generated: $checkpoint"
}
puts "NETLIST POWER BUILD PASS: $net_file"
puts "MATCHING POWER CHECKPOINT: $checkpoint"
puts "NOTE: this is CORE post-synthesis, not routed UART design."

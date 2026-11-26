# Route an independent OOC NPU core and export a *matching* functional netlist.
# Existing UART/bitstream and standalone IP projects are not modified.
# Vivado 2025.2.1 Tcl Console: source vivado/build_npu_routed_power.tcl
set power_root [file normalize [file join [file dirname [info script]] ..]]
set power_dir [file join $power_root build routed_core_power]
file mkdir $power_dir
catch {close_sim}
catch {close_project}
catch {close_design}
read_verilog -sv [file join $power_root rtl npu_weight_bank.sv]
read_verilog -sv [file join $power_root rtl npu_scalable_core.sv]
synth_design -top npu_scalable_core -part xc7a35ticsg324-1L -mode out_of_context
create_clock -name core_clk -period 10.000 [get_ports clk]
write_checkpoint -force [file join $power_dir core_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
report_route_status -file [file join $power_dir route_status.rpt]
report_timing_summary -file [file join $power_dir timing_routed.rpt]
report_utilization -file [file join $power_dir utilization_routed.rpt]
set routed [file join $power_dir core_routed.dcp]
set functional [file join $power_dir core_routed_func.v]
write_checkpoint -force $routed
write_verilog -mode funcsim -force $functional
foreach file [list $routed $functional] {
    if {![file isfile $file] || [file size $file] < 1024} {
        error "Missing or empty routed output: $file"
    }
}
puts "ROUTED CORE CHECKPOINT READY: $routed"
puts "ROUTED CORE SIMULATION NETLIST READY: $functional"
puts "NOTE: OOC core only; not the UART top or a board power measurement."

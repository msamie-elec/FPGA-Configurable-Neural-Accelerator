# Simulate the EXACT core post-synthesis netlist, not the RTL core.
# Requires source vivado/build_npu_netlist_power.tcl in this checkout.
# This creates a separate XSim project in build/netlist_power/sim_project.
set npu_root [file normalize [file join [file dirname [info script]] ..]]
set net_dir [file join $npu_root build netlist_power]
set net_file [file join $net_dir npu_core_post_synth_func.v]
if {![file isfile $net_file]} {error "Missing post-synthesis core netlist: run build_npu_netlist_power.tcl"}
catch {close_sim}
catch {close_project}
catch {close_design}
create_project -force npu_netlist_power [file join $net_dir sim_project] -part xc7a35ticsg324-1L
# Behavioral simulation of a STRUCTURAL functional netlist. This does not
# compile the original npu_scalable_core.sv into the simulator.
add_files -fileset sim_1 -norecurse $net_file
set_property file_type Verilog [get_files $net_file]
set stim [file join $npu_root tb tb_npu_power_activity.sv]
add_files -fileset sim_1 -norecurse $stim
set_property file_type SystemVerilog [get_files $stim]
set_property top tb_npu_power_activity [get_filesets sim_1]
set_property target_simulator XSim [current_project]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
# XSim normally provides Xilinx UNISIM primitive models for functional netlists.
# If a UNISIM primitive is missing, do not replace the netlist with behavioral RTL.
set_property xsim.simulate.custom_tcl [file join $npu_root vivado npu_power_xsim_phases.tcl] [get_filesets sim_1]
set ::env(NPU_POWER_OUT) [file normalize $net_dir]
update_compile_order -fileset sim_1
puts "Starting post-synthesis functional-netlist XSim phase capture..."
launch_simulation -mode behavioral -simset sim_1
foreach phase {idle loading inference} {
  set saif [file join $net_dir "${phase}.saif"]
  if {![file isfile $saif] || [file size $saif]<128} {
    error "Required post-synthesis SAIF missing/empty: $saif"
  }
  puts "NETLIST SAIF READY: $saif ([file size $saif] bytes)"
}
puts "NETLIST SIMULATION PASS: phase-separated core netlist activity collected"

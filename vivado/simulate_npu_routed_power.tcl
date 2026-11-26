# Use the actual *post-route* core functional Verilog netlist with the
# existing three-window power testbench. No behavioral core RTL is compiled.
set power_root [file normalize [file join [file dirname [info script]] ..]]
set power_dir [file join $power_root build routed_core_power]
set net [file join $power_dir core_routed_func.v]
if {![file isfile $net] || [file size $net] < 1024} {
    error "Missing routed functional netlist: run build_npu_routed_power.tcl"
}
catch {close_sim}
catch {close_project}
catch {close_design}
create_project -force routed_core_power_sim [file join $power_dir sim_project] -part xc7a35ticsg324-1L
add_files -norecurse -fileset sim_1 $net
set_property file_type Verilog [get_files $net]
set stim [file join $power_root tb tb_npu_power_activity.sv]
add_files -norecurse -fileset sim_1 $stim
set_property file_type SystemVerilog [get_files $stim]
set_property top tb_npu_power_activity [get_filesets sim_1]
set_property target_simulator XSim [current_project]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
set_property xsim.simulate.custom_tcl [file join $power_root vivado npu_power_xsim_phases.tcl] [get_filesets sim_1]
set ::env(NPU_POWER_OUT) [file normalize $power_dir]
update_compile_order -fileset sim_1
puts "Simulating routed NPU functional netlist, three separate workload phases..."
launch_simulation -mode behavioral -simset sim_1
foreach phase {idle loading inference} {
    set saif [file join $power_dir "${phase}.saif"]
    if {![file isfile $saif] || [file size $saif] < 128} {
        error "Routed netlist SAIF missing or empty: $saif"
    }
    puts "ROUTED SAIF READY: $saif ([file size $saif] bytes)"
}
puts "ROUTED NPU FUNCTIONAL SIMULATION COMPLETE"

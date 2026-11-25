# Vivado Project Mode: compile core RTL and emit three PHASE-SPECIFIC SAIF.
# Call from Vivado Tcl Console in repository root:
#   source vivado/run_npu_power_saif.tcl
# All files generated under ignored build/power_activity/.
set npu_root [file normalize [file join [file dirname [info script]] ..]]
set npu_dir [file join $npu_root build power_activity]
file mkdir $npu_dir
if {[catch {current_project}]} {
  # No project open.
} else {
  catch {close_project}
}
create_project -force npu_power_activity [file join $npu_dir sim_project] -part xc7a35ticsg324-1L
foreach name {rtl/npu_weight_bank.sv rtl/npu_scalable_core.sv} {
  set f [file join $npu_root $name]
  add_files -fileset sim_1 -norecurse $f
  set_property file_type SystemVerilog [get_files $f]
}
set f [file join $npu_root tb tb_npu_power_activity.sv]
add_files -fileset sim_1 -norecurse $f
set_property file_type SystemVerilog [get_files $f]
set_property top tb_npu_power_activity [get_filesets sim_1]
set_property target_simulator XSim [current_project]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
# Custom Tcl is executed INSIDE the simulator, replacing the default run script.
set_property xsim.simulate.custom_tcl [file join $npu_root vivado npu_power_xsim_phases.tcl] [get_filesets sim_1]
set ::env(NPU_POWER_OUT) [file normalize $npu_dir]
update_compile_order -fileset sim_1
puts {Starting phase-specific Vivado simulator; Verilog stop boundaries control SAIF.}
launch_simulation -mode behavioral -simset sim_1
puts "After simulation, look for: [file join $npu_dir idle.saif]"
puts "If XSim reports a Tcl or stop-boundary error, do NOT report activity-aware power."

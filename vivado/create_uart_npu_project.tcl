# Generates a standalone GUI .xpr; leaves old baseline GUI project untouched.
set root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $root build uart_npu_project]
file mkdir $project_dir
create_project -force uart_npu $project_dir -part xc7a35ticsg324-1L
foreach f {
  rtl/npu_weight_bank.sv
  rtl/npu_scalable_core.sv
  rtl/uart_8n1.sv
  rtl/npu_uart_bridge.sv
  rtl/arty_a7_uart_npu_top.sv
} {
  set filename [file join $root $f]
  add_files -fileset sources_1 $filename
  set_property file_type SystemVerilog [get_files $filename]
}
add_files -fileset constrs_1 [file join $root constraints arty_a7_uart_npu.xdc]
add_files -fileset sim_1 [file join $root tb tb_npu_uart_bridge.sv]
set_property file_type SystemVerilog [get_files [file join $root tb tb_npu_uart_bridge.sv]]
set_property top tb_npu_uart_bridge [get_filesets sim_1]
set_property top arty_a7_uart_npu_top [get_filesets sources_1]
set_property STEPS.WRITE_BITSTREAM.TCL.POST [file join $root vivado post_write_gui_bitstream.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
close_project
puts "Open GUI project: [file join $project_dir uart_npu.xpr]"

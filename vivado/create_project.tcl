# Create a navigable Vivado .xpr project, without committing generated outputs.
# Run from repository root: vivado -mode batch -source vivado/create_project.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $root build vivado_project]
file mkdir $project_dir
create_project -force neural_accelerator $project_dir -part xc7a35ticsg324-1L
set srcs [list [file join $root rtl npu_core.sv] [file join $root rtl arty_a7_top.sv]]
add_files -fileset sources_1 $srcs
foreach src $srcs { set_property file_type SystemVerilog [get_files $src] }
add_files -fileset constrs_1 [file join $root constraints arty_a7_35t.xdc]
set_property top arty_a7_top [get_filesets sources_1]
update_compile_order -fileset sources_1
save_project
puts "Vivado project created: [file join $project_dir neural_accelerator.xpr]"

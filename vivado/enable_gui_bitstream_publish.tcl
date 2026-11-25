# Register the canonical-bitstream post-write hook in an EXISTING open GUI project.
# In Vivado Tcl Console from repository root:
#   source vivado/enable_gui_bitstream_publish.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set project_name [get_property NAME [current_project]]
if {$project_name ne "uart_npu"} {
    error "This helper expects the uart_npu GUI project, got $project_name"
}
set hook [file join $root vivado post_write_gui_bitstream.tcl]
if {![file isfile $hook]} {error "Post-write hook missing: $hook"}
set_property STEPS.WRITE_BITSTREAM.TCL.POST $hook [get_runs impl_1]
save_project
puts "GUI bitstream publisher installed for future impl_1 Generate Bitstream runs."
puts "For an already-built bitstream, run: source vivado/publish_existing_gui_bitstream.tcl"

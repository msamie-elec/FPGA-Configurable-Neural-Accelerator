# One-time publishing of an ALREADY GENERATED GUI bitstream.
# Usage in Tcl Console AFTER opening Vivado uart_npu.xpr:
#     source vivado/publish_existing_gui_bitstream.tcl
set publish_script_root [file normalize [file join [file dirname [info script]] ..]]
if {[catch {current_project} project]} {
  error "Open build/uart_npu_project/uart_npu.xpr before publishing."
}
set project_directory [get_property DIRECTORY [current_project]]
set uart_publish_source [file join $project_directory uart_npu.runs impl_1 arty_a7_uart_npu_top.bit]
if {![file exists $uart_publish_source]} {
  error "GUI .bit missing: $uart_publish_source; run Generate Bitstream first."
}
# Open the matching routed implementation to check timing before publishing.
open_run impl_1
set uart_publish_flow "vivado-project-existing-impl_1"
source [file join $publish_script_root vivado publish_uart_bitstream.tcl]

# Publish one authoritative bitstream for the Arty A7-35T UART/NPU.
# Caller provides uart_publish_source and uart_publish_flow before sourcing.
# Source may be the Vivado GUI's impl_1 bitstream or batch flow's .bit.
set uart_publish_root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists uart_publish_source] || ![file isfile $uart_publish_source]} {
  error "Cannot publish: uart_publish_source does not name an existing .bit file."
}
if {![info exists uart_publish_flow]} {set uart_publish_flow "unspecified"}
if {[llength [get_clocks -quiet]] == 0} {
  error "Cannot publish without an open routed design and defined timing clock."
}
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
  error "Cannot publish: routed setup/hold paths not available."
}
set wns [get_property SLACK [lindex $setup_paths 0]]
set whs [get_property SLACK [lindex $hold_paths 0]]
if {$wns < 0 || $whs < 0} {
  error "Cannot publish timing-failing bitstream: WNS $wns ns, WHS $whs ns."
}
set uart_publish_dir [file join $uart_publish_root build bitstream]
file mkdir $uart_publish_dir
set uart_publish_target [file join $uart_publish_dir arty_a7_uart_npu.bit]
if {[file normalize $uart_publish_source] ne [file normalize $uart_publish_target]} {
  file copy -force -- $uart_publish_source $uart_publish_target
}
set manifest [open [file join $uart_publish_dir build_info.txt] w]
puts $manifest "Bitstream: arty_a7_uart_npu.bit"
puts $manifest "Target: Digilent Arty A7-35T / xc7a35ticsg324-1L"
puts $manifest "Top: arty_a7_uart_npu_top"
puts $manifest "Vivado flow: $uart_publish_flow"
puts $manifest "Source: [file normalize $uart_publish_source]"
puts $manifest "Published: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]"
puts $manifest "Routed setup WNS (ns): $wns"
puts $manifest "Routed hold WHS (ns): $whs"
puts $manifest "Source file size (bytes): [file size $uart_publish_source]"
close $manifest
puts "CANONICAL UART NPU BITSTREAM PUBLISHED: $uart_publish_target"
puts "SETUP WNS: $wns ns; HOLD WHS: $whs ns"
unset uart_publish_source
unset uart_publish_flow

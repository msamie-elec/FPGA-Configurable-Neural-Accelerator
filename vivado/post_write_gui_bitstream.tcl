# Runs automatically after Vivado GUI Project Mode impl_1/write_bitstream.
# Vivado runs Tcl hooks in the run working directory (UG894).
set uart_publish_source [file normalize [file join [pwd] arty_a7_uart_npu_top.bit]]
set uart_publish_flow "vivado-project-impl_1-post-write-bitstream-hook"
source [file join [file dirname [info script]] publish_uart_bitstream.tcl]

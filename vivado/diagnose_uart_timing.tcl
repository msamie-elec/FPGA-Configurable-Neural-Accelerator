# Diagnose an OPEN routed UART-NPU implementation without rerunning place/route.
# In Vivado Tcl Console, with implemented design open:
#   source vivado/diagnose_uart_timing.tcl   (from project root)
# The generated reports live in build/uart_npu/timing_diagnostics.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build uart_npu timing_diagnostics]
file mkdir $out

if {[llength [get_clocks -quiet]] == 0} {
    error "No design clock found. Open the routed implementation (Open Implemented Design) before sourcing this script."
}
report_timing_summary -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 30 -nworst 1 -path_type full_clock_expanded -input_pins -file [file join $out critical_setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -nworst 1 -path_type full_clock_expanded -file [file join $out hold_paths.rpt]
report_methodology -file [file join $out methodology.rpt]
puts "TIMING DIAGNOSTICS: [file join $out critical_setup_paths.rpt]"

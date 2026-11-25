# Annotate the matching routed UART/NPU implementation with three core SAIF.
# Run in Vivado Tcl Console AFTER completing run_npu_power_saif.tcl.
# If original UART project lives in another checkout, first define:
# set ::NPU_UART_XPR {C:/.../FPGA-NN-Accelerator-9/build/uart_npu_project/uart_npu.xpr}
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build power_activity]
set reports [file join $out reports]
file mkdir $reports
set default_xpr [file join $root build uart_npu_project uart_npu.xpr]
if {![info exists ::NPU_UART_XPR]} {set ::NPU_UART_XPR $default_xpr}
if {![file isfile $::NPU_UART_XPR]} {
  error "UART/NPU .xpr not found: $::NPU_UART_XPR; set ::NPU_UART_XPR to your existing routed Track A project path"
}
foreach phase {idle loading inference} {
  set f [file join $out "${phase}.saif"]
  if {![file isfile $f] || [file size $f]<128} {
    error "Missing/empty ${phase}.saif. Complete Vivado XSim phase capture first."
  }
}
catch {close_sim}
catch {close_project}
open_project $::NPU_UART_XPR
if {[llength [get_runs impl_1]]==0} {error "Implementation run impl_1 missing in $::NPU_UART_XPR"}
open_run impl_1
set top [get_property TOP [current_design]]
if {$top ne "arty_a7_uart_npu_top"} {
  error "Expected routed UART/NPU board top arty_a7_uart_npu_top, got $top"
}
# Baseline: Vivado vectorless estimate. SAIF imports are intentionally separate.
reset_switching_activity -all
report_power -file [file join $reports power_vectorless.rpt]
foreach phase {idle loading inference} {
  reset_switching_activity -all
  set f [file join $out "${phase}.saif"]
  set unmatched [file join $reports "${phase}_unmatched.txt"]
  # tb_npu_power_activity/u_bridge/accelerator hierarchy strips the
  # simulation-only testbench scope, leaving u_bridge/accelerator.
  read_saif -strip_path tb_npu_power_activity -out_file $unmatched $f
  report_power -file [file join $reports "power_${phase}_saif.rpt"]
  report_switching_activity -file [file join $reports "activity_${phase}.rpt"]
  puts "SAIF POWER REPORT: [file join $reports "power_${phase}_saif.rpt"]"
}
puts "POWER REPORTS READY: $reports"
puts "IMPORTANT: examine Design Nets Matched, unmatched nets and confidence."
puts "RTL-core-only SAIF does NOT annotate all UART/board nets. No physical watts claimed."

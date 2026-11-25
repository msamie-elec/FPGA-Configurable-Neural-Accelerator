# Apply the three SAIF snapshots to their EXACT source synthesized checkpoint.
# This explicitly does not apply OOC core SAIF to a separately synthesized
# UART/board netlist. Keep power boundaries distinct.
set npu_root [file normalize [file join [file dirname [info script]] ..]]
set net_dir [file join $npu_root build netlist_power]
set reports [file join $net_dir reports]
file mkdir $reports
set checkpoint [file join $net_dir npu_core_post_synth.dcp]
if {![file isfile $checkpoint]} {error "Missing matching core checkpoint: $checkpoint"}
foreach phase {idle loading inference} {
  set saif [file join $net_dir "${phase}.saif"]
  if {![file isfile $saif] || [file size $saif]<128} {
    error "Missing corresponding $phase SAIF: $saif"
  }
}
catch {close_sim}
catch {close_project}
catch {close_design}
open_checkpoint $checkpoint
if {[llength [get_clocks -quiet]] == 0} {
  error "Core checkpoint has no 100 MHz clock; do not evaluate power"
}
set baseline [file join $reports power_vectorless.rpt]
reset_switching_activity -all
report_power -file $baseline
foreach phase {idle loading inference} {
  reset_switching_activity -all
  set saif [file join $net_dir "${phase}.saif"]
  set unmatched [file join $reports "${phase}_unmatched.txt"]
  # In tb_npu_power_activity.sv the DUT is:
  # tb_npu_power_activity/u_bridge/accelerator (synthesised core top).
  # Strip this EXACT simulation wrapper to map to checkpoint's root nets.
  read_saif -strip_path tb_npu_power_activity/u_bridge/accelerator -out_file $unmatched $saif
  set report [file join $reports "power_${phase}_saif.rpt"]
  report_power -file $report
  if {![file isfile $report] || [file size $report]<128} {
    error "Vivado did not generate $phase post-synthesis power report"
  }
  puts "NETLIST POWER PHASE COMPLETE: $report"
}
foreach file {power_vectorless.rpt power_idle_saif.rpt power_loading_saif.rpt power_inference_saif.rpt} {
  if {![file isfile [file join $reports $file]]} {
    error "Netlist power report missing: $file"
  }
}
puts "NETLIST POWER ANALYSIS PASS: $reports"
puts "Check SAIF match % and estimated power confidence before accepting comparisons."
puts "Estimates are core-only POST-SYNTHESIS, not routed UART FPGA power or measured watts."

# Read SAIF from the routed functional NPU netlist into its *matching*
# routed checkpoint. Full-chip device static component is included by Vivado.
set power_root [file normalize [file join [file dirname [info script]] ..]]
set power_dir [file join $power_root build routed_core_power]
set reports [file join $power_dir reports]
file mkdir $reports
set checkpoint [file join $power_dir core_routed.dcp]
if {![file isfile $checkpoint]} {error "Routed NPU checkpoint missing: $checkpoint"}
foreach phase {idle loading inference} {
    set saif [file join $power_dir "${phase}.saif"]
    if {![file isfile $saif] || [file size $saif]<128} {
        error "SAIF missing for $phase: $saif"
    }
}
catch {close_sim}
catch {close_project}
catch {close_design}
open_checkpoint $checkpoint
if {[llength [get_clocks -quiet]] == 0} {
    error "Routed core checkpoint has no 100 MHz clock"
}
reset_switching_activity -all
report_power -file [file join $reports power_vectorless.rpt]
foreach phase {idle loading inference} {
    reset_switching_activity -all
    set unmatched [file join $reports "${phase}_unmatched.txt"]
    set saif [file join $power_dir "${phase}.saif"]
    # Same instance hierarchy as previous successful post-synthesis mapping.
    read_saif -strip_path tb_npu_power_activity/u_bridge/accelerator -out_file $unmatched $saif
    set output [file join $reports "power_${phase}_saif.rpt"]
    report_power -file $output
    if {![file isfile $output] || [file size $output] < 128} {
        error "Incomplete report for $phase: $output"
    }
    puts "ROUTED POWER PHASE COMPLETE: $output"
}
foreach name {power_vectorless.rpt power_idle_saif.rpt power_loading_saif.rpt power_inference_saif.rpt} {
    set path [file join $reports $name]
    if {![file isfile $path] || [file size $path] < 128} {
        error "Missing routed power report: $path"
    }
}
puts "ROUTED POWER ANALYSIS COMPLETE: $reports"
puts "Important: core-only routed functional simulation, no SDF glitch activity, not physical power."

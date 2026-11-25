# Independent packaged-IP consumer: synthesis, place/route and signed-off reports.
# Vivado 2025.2.1 Tcl Console, current directory may be anywhere:
#     source vivado/build_ip_consumer_impl.tcl
#
# Requires: source vivado/package_npu_ip.tcl
# Output: build/ip_consumer_implementation/reports/
# Does NOT modify or program the verified UART/NPU board bitstream.
set root [file normalize [file join [file dirname [info script]] ..]]
set repo [file join $root build ip_repo]
set component [file join $repo npu_accelerator_ip_1_0 component.xml]
if {![file isfile $component]} {
  error "Packaged IP missing: first run source vivado/package_npu_ip.tcl"
}
set project_dir [file join $root build ip_consumer_implementation]
set reports [file join $project_dir reports]
file mkdir $reports
create_project -force npu_ip_impl $project_dir -part xc7a35ticsg324-1L
set_property ip_repo_paths [list $repo] [current_project]
update_ip_catalog -rebuild
set vlnv msamie-elec.github.io:user:npu_accelerator_ip:1.0
if {[llength [get_ipdefs -all $vlnv]] != 1} {error "NPU IP VLNV unavailable: $vlnv"}
create_ip -vlnv $vlnv -module_name npu0
generate_target all [get_ips npu0]
set topfile [file join $root rtl arty_a7_ip_consumer_top.sv]
set constr [file join $root constraints arty_a7_ip_consumer.xdc]
add_files -norecurse -fileset sources_1 $topfile
set_property file_type SystemVerilog [get_files $topfile]
add_files -fileset constrs_1 $constr
set_property top arty_a7_ip_consumer_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "CONSUMER: launching packaged IP integration synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
  error "Consumer synthesis failed: $synth_status"
}
open_run synth_1
report_utilization -file [file join $reports utilization_synth.rpt]
close_design
puts "CONSUMER: launching placement and routing at 100 MHz..."
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
  error "Consumer implementation failed: $impl_status"
}
open_run impl_1
report_utilization -file [file join $reports utilization_routed.rpt]
report_utilization -hierarchical -file [file join $reports utilization_hierarchical.rpt]
report_timing_summary -report_unconstrained -file [file join $reports timing_routed.rpt]
report_timing -delay_type max -max_paths 30 -nworst 1 -path_type full_clock_expanded -file [file join $reports critical_setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -nworst 1 -file [file join $reports hold_paths.rpt]
report_drc -file [file join $reports drc_routed.rpt]
report_methodology -file [file join $reports methodology_routed.rpt]
report_power -file [file join $reports power_estimated.rpt]
write_checkpoint -force [file join $reports npu_consumer_routed.dcp]
set maxpaths [get_timing_paths -delay_type max -max_paths 1]
set minpaths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $maxpaths]==0 || [llength $minpaths]==0} {
  error "No constrained synchronous setup/hold paths found: inspect timing_routed.rpt"
}
set wns [get_property SLACK [lindex $maxpaths 0]]
set whs [get_property SLACK [lindex $minpaths 0]]
set dsps [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set brams [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
set summary [open [file join $reports implementation_summary.txt] w]
puts $summary "Design: independent packaged npu0 in arty_a7_ip_consumer_top"
puts $summary "VLNV: $vlnv"
puts $summary "Device: xc7a35ticsg324-1L"
puts $summary "Constraint: 100 MHz"
puts $summary "Setup worst slack ns: $wns"
puts $summary "Hold worst slack ns: $whs"
puts $summary "DSP48E1: $dsps"
puts $summary "RAMB18E1: $brams"
puts $summary "Status: $impl_status"
puts $summary "This is a fully-routed consumer design, not an IP-only OOC timing measurement."
puts $summary "No experimental power or neural-task accuracy is implied."
close $summary
puts "CONSUMER IMPLEMENTATION: WNS=$wns ns WHS=$whs ns DSP=$dsps BRAM18=$brams"
puts "CONSUMER REPORTS: $reports"
if {$dsps < 8 || $brams < 8} {
  error "Unexpected loss of NPU hardware: DSP=$dsps, BRAM18=$brams; inspect hierarchy/optimisation reports"
}
if {$wns < 0 || $whs < 0} {
  error "Consumer routed implementation FAILED 100 MHz sign-off (WNS $wns, WHS $whs)"
}
puts "CONSUMER IMPLEMENTATION PASS: packaged-IP representative top placed/routed at 100 MHz"
# Leave implemented design open for inspecting timing/resource diagrams in GUI.

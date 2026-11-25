# Demonstrate discovery of packaged IP in fresh Vivado project.
# Run AFTER source vivado/package_npu_ip.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set ip_root [file join $root build ip_repo]
set projectdir [file join $root build ip_catalog_smoke_project]
if {![file exists [file join $ip_root npu_accelerator_ip_1_0 component.xml]]} {
    error "Package IP first: source vivado/package_npu_ip.tcl"
}
create_project -force npu_ip_catalog_smoke $projectdir -part xc7a35ticsg324-1L
set_property ip_repo_paths [list $ip_root] [current_project]
update_ip_catalog -rebuild
set defs [get_ipdefs -all *npu_accelerator_ip*]
if {[llength $defs]==0} {error "Custom NPU IP is missing from Vivado IP catalog"}
puts "CATALOG DISCOVERY PASS: $defs"
close_project

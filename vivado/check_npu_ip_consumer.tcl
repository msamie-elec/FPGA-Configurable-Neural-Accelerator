# Consumer-project test: independent Vivado project instantiates the packaged
# IP via its registered VLNV, rather than adding RTL source modules directly.
# Run after: source vivado/package_npu_ip.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set ip_root [file join $root build ip_repo]
set packaged [file join $ip_root npu_accelerator_ip_1_0 component.xml]
if {![file isfile $packaged]} {error "Package missing: $packaged"}
set projectdir [file join $root build ip_consumer_project]
create_project -force npu_ip_consumer $projectdir -part xc7a35ticsg324-1L
set_property ip_repo_paths [list $ip_root] [current_project]
update_ip_catalog -rebuild
set vlnv msamie-elec.github.io:user:npu_accelerator_ip:1.0
if {[llength [get_ipdefs -all $vlnv]] == 0} {
    error "Custom NPU not found in consumer IP Catalog: $vlnv"
}
create_ip -vlnv $vlnv -module_name npu0
generate_target all [get_ips npu0]
set xcis [get_files -quiet *.xci]
if {[llength $xcis] == 0} {
    error "IP instantiated but no .xci component created"
}
puts "CONSUMER IP INSTANTIATION PASS: $vlnv"
puts "GENERATED IP: $xcis"
puts "Next: review IP output products and run synthesis in a consuming top."
# create_project and create_ip already persist the .xpr/.xci metadata.
# Vivado 2025.2.1 does not support bare save_project (17-163).
close_project
puts "CONSUMER PROJECT COMPLETED: [file join $projectdir npu_ip_consumer.xpr]"

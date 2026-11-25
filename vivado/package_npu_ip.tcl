# Reproducible reusable, application-independent Vivado Catalog IP package.
# Vivado 2025.2.1 Tcl Console from any working directory:
#   source vivado/package_npu_ip.tcl
# Output: build/ip_repo/npu_accelerator_ip_1_0/component.xml
# Source RTL remains authoritative in rtl; packaging copies required source.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build ip_repo npu_accelerator_ip_1_0]
set projectdir [file join $root build ip_packaging_project]
file mkdir [file dirname $out]
if {[file exists $out]} {file delete -force $out}
create_project -force npu_ip_packaging $projectdir -part xc7a35ticsg324-1L
set files [list \
    [file join $root rtl npu_weight_bank.sv] \
    [file join $root rtl npu_scalable_core.sv] \
    [file join $root rtl npu_accelerator_ip.sv]]
foreach f $files {
    add_files -norecurse -fileset sources_1 $f
    set_property file_type SystemVerilog [get_files $f]
}
set_property top npu_accelerator_ip [get_filesets sources_1]
update_compile_order -fileset sources_1
# AMD UG1118: packaging produces IP-XACT component.xml and catalog metadata.
ipx::package_project -root_dir $out -vendor msamie-elec.github.io \
    -library user -taxonomy /UserIP -import_files -set_current true
set core [ipx::current_core]
set_property name npu_accelerator_ip $core
set_property version 1.0 $core
set_property display_name {Configurable INT8 Neural Inference Accelerator} $core
set_property description {Application-independent 8-lane INT8 signed MLP inference IP with runtime weight and bias loading} $core
# Reconcile port metadata with the chosen RTL wrapper, not the UART board top.
ipx::merge_project_changes ports $core
ipx::merge_project_changes files $core
ipx::save_core $core
set component [file join $out component.xml]
if {![file exists $component]} {error "IP packaging failed to create $component"}
puts "PACKAGED IP: $component"
puts "Import in another Vivado project with:"
puts "  set_property ip_repo_paths [list [file join $root build ip_repo]] [current_project]"
puts "  update_ip_catalog -rebuild"
close_project

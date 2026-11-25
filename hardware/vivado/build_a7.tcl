# vivado -mode batch -source hardware/vivado/build_a7.tcl -tclargs 35 4
if {$argc != 2} { error "Usage: -tclargs (35|100) (1|4|8)" }
lassign $argv variant lanes
if {$variant ni {35 100} || $lanes ni {1 4 8}} { error "Invalid board variant or lane count" }
set root [file normalize [file join [file dirname [info script]] ../..]]
set build [file join $root hardware build arty_a7_${variant}t_p${lanes}]
file mkdir $build
foreach dir {compute memory control host top} {
    read_verilog -sv [glob [file join $root hardware rtl $dir *.sv]]
}
read_verilog -sv [file join $root hardware boards arty_a7 arty_a7.sv]
read_xdc [file join $root hardware boards arty_a7 arty_a7.xdc]
if {$variant == 35} { set part xc7a35ticsg324-1L } else { set part xc7a100tcsg324-1 }
synth_design -top arty_a7 -part $part -generic LANES=$lanes
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $build routed.dcp]
report_timing_summary -report_unconstrained -file [file join $build timing.rpt]
report_timing -delay_type max -max_paths 20 -nworst 1 -file [file join $build setup_paths.rpt]
report_utilization -hierarchical -file [file join $build utilization.rpt]
report_power -file [file join $build power_estimate.rpt]
report_drc -file [file join $build drc.rpt]
report_cdc -file [file join $build cdc.rpt]
check_timing -verbose -file [file join $build check_timing.rpt]
foreach type {max min} {
    set path [get_timing_paths -quiet -delay_type $type -max_paths 1]
    if {[llength $path] == 0} {
        error "No $type timing path found. Review reports in $build."
    }
    set slack [get_property SLACK $path]
    if {$slack < 0} {
        error "Post-route $type slack is $slack ns. Review reports in $build."
    }
}
write_bitstream -force [file join $build npu.bit]

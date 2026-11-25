# Independent resource exploration for new MLP engine; no board I/O yet.
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7a35ticsg324-1L
foreach lanes {1 4 8} {
    set out [file join $root build mlp_synth lanes_$lanes]
    file mkdir $out
    read_verilog -sv [file join $root rtl mlp_engine.sv]
    synth_design -top mlp_engine -part $part -generic LANES=$lanes
    report_utilization -hierarchical -file [file join $out utilization.rpt]
    report_timing_summary -file [file join $out synthesis_timing_unconstrained.rpt]
    write_checkpoint -force [file join $out post_synth.dcp]
    close_design
    puts "MLP synthesis completed for LANES=$lanes"
}

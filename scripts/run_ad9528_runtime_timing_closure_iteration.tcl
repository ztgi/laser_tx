# Clean synthesis/implementation timing iteration after pattern-engine changes.
# Optional argv[0] names the report subdirectory.  The flow stops after route
# and intentionally does not generate bit/LTX/XSA.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set iteration_name [expr {$argc > 0 ? [lindex $argv 0] : "timing_closure_iteration"}]
set impl_strategy [expr {$argc > 1 ? [lindex $argv 1] : "Vivado Implementation Defaults"}]
set out [file join $root reports ad9528_gt_rate_planner $iteration_name]
file mkdir $out

open_project [file join $root laser_tx.xpr]
set_property top laser_tx_board_top [get_filesets sources_1]

set wizard_xci [get_files -quiet */gtwizard_0.xci]
if {![llength $wizard_xci]} { error "gtwizard_0.xci not found" }
set_property IS_ENABLED false $wizard_xci
set wrapper_root [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0]
set wrapper_sources [concat \
    [glob -nocomplain [file join $wrapper_root *.v]] \
    [glob -nocomplain [file join $wrapper_root gtwizard_0 example_design *.v]]]
foreach source $wrapper_sources {
    if {![llength [get_files -quiet $source]]} {
        add_files -fileset sources_1 -norecurse $source
    }
}
update_compile_order -fileset sources_1

# laser_tx_core is a BD module-reference IP with its own OOC synthesis run.
# Rebuild that run first so implementation cannot silently load a stale DCP
# after pattern_tx_engine RTL changes.
set core_ooc_run [get_runs -quiet system_laser_tx_core_0_0_synth_1]
if {![llength $core_ooc_run]} {
    error "system_laser_tx_core_0_0_synth_1 not found"
}
set core_ip [get_ips -quiet system_laser_tx_core_0_0]
if {![llength $core_ip]} {
    error "system_laser_tx_core_0_0 IP object not found"
}
# Vivado's module-reference cache key does not reliably track edits inside
# the referenced RTL hierarchy.  Disable cache only for this IP so the OOC
# checkpoint is built from the current pattern_tx_engine source.
config_ip_cache -disable_for_ip $core_ip
reset_run $core_ooc_run
launch_runs $core_ooc_run -jobs 4
wait_on_run $core_ooc_run
set core_ooc_status [get_property STATUS $core_ooc_run]
if {![string match "*Complete*" $core_ooc_status]} {
    error "laser_tx_core OOC synthesis failed: $core_ooc_status"
}
open_run $core_ooc_run
set pattern_index_cells [llength [get_cells -quiet -hier *pattern_index_reg*]]
set pattern_cursor_cells [llength [get_cells -quiet -hier *pattern_cursor_reg*]]
close_design
if {$pattern_index_cells == 0 || $pattern_cursor_cells != 0} {
    error "stale laser_tx_core OOC DCP: pattern_index=$pattern_index_cells pattern_cursor=$pattern_cursor_cells"
}

reset_run impl_1
reset_run synth_1
set_property strategy $impl_strategy [get_runs impl_1]
set_property STEPS.OPT_DESIGN.TCL.PRE \
    [file join $root scripts gt_profile0_impl_pre.tcl] [get_runs impl_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}

launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 failed: $impl_status"
}
open_run impl_1

report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -delay_type min_max -file [file join $out clock_interaction.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_exceptions -summary -file [file join $out exceptions.rpt]
report_timing_summary -delay_type max -max_paths 100 -report_unconstrained \
    -file [file join $out timing_summary.rpt]
report_timing_summary -delay_type min -max_paths 50 -report_unconstrained \
    -file [file join $out hold_top50.rpt]
report_timing -delay_type max -max_paths 100 -path_type full_clock_expanded \
    -file [file join $out setup_top100.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out full_clock_expanded_top50.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -input_pins -nets -file [file join $out primitive_datapath_top50.rpt]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $out high_fanout.rpt]
report_design_analysis -congestion -file [file join $out congestion.rpt]
report_utilization -hierarchical -file [file join $out hierarchical_utilization.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint -force [file join $out routed.dcp]

set txusrclk_obj [get_clocks -quiet GT_TXUSRCLK_RUNTIME_MAX]
set txusrclk2_obj [get_clocks -quiet GT_TXUSRCLK2_RUNTIME_MAX]
if {![llength $txusrclk_obj] || ![llength $txusrclk2_obj]} {
    error "runtime TX user-clock constraints are missing"
}
set txusrclk_period [get_property PERIOD $txusrclk_obj]
set txusrclk2_period [get_property PERIOD $txusrclk2_obj]
if {abs($txusrclk_period - 3.103) > 0.001 || abs($txusrclk2_period - 6.206) > 0.001} {
    error "unexpected runtime clock periods: TXUSRCLK=$txusrclk_period TXUSRCLK2=$txusrclk2_period"
}

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_wns [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : -999.0}]
set hold_whs [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : -999.0}]
set fd [open [file join $out iteration_status.txt] w]
puts $fd "iteration=$iteration_name"
puts $fd "implementation_strategy=$impl_strategy"
puts $fd "core_ooc_status=$core_ooc_status"
puts $fd "pattern_index_cells=$pattern_index_cells"
puts $fd "pattern_cursor_cells=$pattern_cursor_cells"
puts $fd "txusrclk_period_ns=$txusrclk_period"
puts $fd "txusrclk2_period_ns=$txusrclk2_period"
puts $fd "synth_status=$synth_status"
puts $fd "impl_status=$impl_status"
puts $fd "setup_wns_ns=$setup_wns"
puts $fd "hold_whs_ns=$hold_whs"
puts $fd "bitstream_generated=0"
close $fd

puts "TIMING_CLOSURE_ITERATION_COMPLETE"
puts "ITERATION=$iteration_name"
puts "SETUP_WNS_NS=$setup_wns"
puts "HOLD_WHS_NS=$hold_whs"
close_project

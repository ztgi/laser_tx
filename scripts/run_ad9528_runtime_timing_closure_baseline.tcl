# Clean synthesis/implementation baseline for the maximum runtime GT user clocks.
# This flow intentionally stops after route and never promotes bit/LTX/XSA.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports ad9528_gt_rate_planner timing_closure_baseline]
file mkdir $out

open_project [file join $root laser_tx.xpr]
set_property top laser_tx_board_top [get_filesets sources_1]

# Match the tracked QPLL/GTNORTH-capable wrapper source policy used by Stage 6.
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

reset_run impl_1
reset_run synth_1
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
report_clock_networks -file [file join $out clock_networks.rpt]
report_clock_interaction -delay_type min_max -file [file join $out clock_interaction.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_exceptions -summary -file [file join $out exceptions.rpt]
report_timing_summary -delay_type max -max_paths 100 -report_unconstrained \
    -file [file join $out timing_summary.rpt]
report_timing_summary -delay_type min -max_paths 50 -report_unconstrained \
    -file [file join $out hold_top50.rpt]
report_timing -delay_type max -max_paths 100 -path_type full_clock_expanded \
    -file [file join $out setup_top100.rpt]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $out high_fanout.rpt]
report_design_analysis -congestion -file [file join $out congestion.rpt]
report_utilization -hierarchical -file [file join $out hierarchical_utilization.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_wns [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : -999.0}]
set hold_whs [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : -999.0}]
set fd [open [file join $out baseline_status.txt] w]
puts $fd "baseline_commit=0652ca13e7cadeecc85f2634628ad6e4c59002cb"
puts $fd "synth_status=$synth_status"
puts $fd "impl_status=$impl_status"
puts $fd "setup_wns_ns=$setup_wns"
puts $fd "hold_whs_ns=$hold_whs"
puts $fd "bitstream_generated=0"
close $fd

puts "TIMING_CLOSURE_BASELINE_COMPLETE"
puts "SETUP_WNS_NS=$setup_wns"
puts "HOLD_WHS_NS=$hold_whs"
close_project

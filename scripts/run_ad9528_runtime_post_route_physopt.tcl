set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports ad9528_gt_rate_planner timing_closure_iteration_3_post_route_physopt]
file mkdir $out

open_checkpoint [file join $root laser_tx.runs impl_1 laser_tx_board_top_routed.dcp]
phys_opt_design -directive AggressiveExplore

report_timing_summary -delay_type max -max_paths 100 -report_unconstrained \
    -file [file join $out timing_summary.rpt]
report_timing_summary -delay_type min -max_paths 50 -report_unconstrained \
    -file [file join $out hold_top50.rpt]
report_timing -delay_type max -max_paths 100 -path_type full_clock_expanded \
    -file [file join $out setup_top100.rpt]
report_utilization -hierarchical -file [file join $out hierarchical_utilization.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint -force [file join $out laser_tx_board_top_post_route_physopt.dcp]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_wns [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : -999.0}]
set hold_whs [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : -999.0}]
set fd [open [file join $out iteration_status.txt] w]
puts $fd "iteration=timing_closure_iteration_3_post_route_physopt"
puts $fd "directive=AggressiveExplore"
puts $fd "setup_wns_ns=$setup_wns"
puts $fd "hold_whs_ns=$hold_whs"
puts $fd "bitstream_generated=0"
close $fd
puts "POST_ROUTE_PHYSOPT_COMPLETE setup_wns_ns=$setup_wns hold_whs_ns=$hold_whs"
close_design

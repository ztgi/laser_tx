# Archive and audit the already-routed iteration-5 reproduction.
# This script is read-only with respect to project sources and does not run
# synthesis, implementation, phys_opt, or bitstream generation.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set source_dir [file join $root reports ad9528_gt_rate_planner timing_closure_iteration_5_reproduced]
set out [file join $root reports ad9528_gt_rate_planner timing_iteration5_reproduced]
set ooc_dcp [file join $root laser_tx.runs system_laser_tx_core_0_0_synth_1 system_laser_tx_core_0_0.dcp]
set routed_dcp [file join $source_dir routed.dcp]
file mkdir $out

if {![file exists $ooc_dcp]} { error "OOC DCP not found: $ooc_dcp" }
if {![file exists $routed_dcp]} { error "routed DCP not found: $routed_dcp" }

open_checkpoint $ooc_dcp
set signature_patterns [dict create \
    pattern_index_reg *pattern_index_reg* \
    pattern_cursor_reg *pattern_cursor_reg* \
    next_phase_pattern_base_q *next_phase_pattern_base_q* \
    cross_next_valid_count_q *cross_next_valid_count_q* \
    current_pattern_q *current_pattern_q* \
    rotated_pattern_reg *rotated_pattern_reg*]
set signature_fd [open [file join $out ooc_rtl_signature.txt] w]
puts $signature_fd "ooc_dcp=$ooc_dcp"
dict for {name pattern} $signature_patterns {
    set count [llength [get_cells -quiet -hier $pattern]]
    puts $signature_fd "$name=$count"
    set signature_count($name) $count
}
close $signature_fd
if {$signature_count(pattern_index_reg) == 0 ||
    $signature_count(pattern_cursor_reg) != 0 ||
    $signature_count(next_phase_pattern_base_q) != 0 ||
    $signature_count(cross_next_valid_count_q) != 0 ||
    $signature_count(current_pattern_q) != 0 ||
    $signature_count(rotated_pattern_reg) != 0} {
    error "OOC RTL signature does not match iteration 5"
}
close_design

open_checkpoint $routed_dcp
set txusrclk [get_clocks -quiet GT_TXUSRCLK_RUNTIME_MAX]
set txusrclk2 [get_clocks -quiet GT_TXUSRCLK2_RUNTIME_MAX]
if {![llength $txusrclk] || ![llength $txusrclk2]} {
    error "runtime TX user clocks missing from routed checkpoint"
}
set txusrclk_period [get_property PERIOD $txusrclk]
set txusrclk2_period [get_property PERIOD $txusrclk2]
if {abs($txusrclk_period - 3.103) > 0.001 || abs($txusrclk2_period - 6.206) > 0.001} {
    error "runtime clock mismatch: $txusrclk_period / $txusrclk2_period"
}

write_checkpoint -force [file join $out iteration5_routed.dcp]
report_timing_summary -delay_type max -max_paths 100 -report_unconstrained \
    -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -path_type full_clock_expanded \
    -file [file join $out setup_top100.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out setup_top50_full_clock_expanded.rpt]
report_timing -delay_type min -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out hold_top50.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -input_pins -nets -file [file join $out primitive_paths_top50.rpt]
report_high_fanout_nets -timing -load_types -max_nets 100 \
    -file [file join $out high_fanout.rpt]
report_design_analysis -congestion -file [file join $out congestion.rpt]
report_clock_interaction -delay_type min_max -file [file join $out clock_interaction.rpt]
report_route_status -file [file join $out route_status.rpt]
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
report_drc -file [file join $out drc.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 10000 -nworst 1 -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 10000 -nworst 1 -slack_lesser_than 0]
set setup_wns [expr {[llength $setup_paths] ? [get_property SLACK [lindex $setup_paths 0]] : 0.0}]
set hold_whs [expr {[llength $hold_paths] ? [get_property SLACK [lindex $hold_paths 0]] : [get_property SLACK [lindex [get_timing_paths -delay_type min -max_paths 1] 0]]}]
set setup_tns 0.0
foreach path $setup_paths { set setup_tns [expr {$setup_tns + [get_property SLACK $path]}] }
set hold_ths 0.0
foreach path $hold_paths { set hold_ths [expr {$hold_ths + [get_property SLACK $path]}] }
set metrics_fd [open [file join $out audit_metrics.txt] w]
puts $metrics_fd "txusrclk_period_ns=$txusrclk_period"
puts $metrics_fd "txusrclk2_period_ns=$txusrclk2_period"
puts $metrics_fd "setup_wns_ns=$setup_wns"
puts $metrics_fd "setup_tns_ns=$setup_tns"
puts $metrics_fd "setup_failing_endpoints=[llength $setup_paths]"
puts $metrics_fd "hold_whs_ns=$hold_whs"
puts $metrics_fd "hold_ths_ns=$hold_ths"
puts $metrics_fd "hold_failing_endpoints=[llength $hold_paths]"
puts $metrics_fd "post_route_physopt_executed=0"
puts $metrics_fd "bitstream_generated=0"
close $metrics_fd
close_design
puts "ITERATION5_ARCHIVE_COMPLETE"

# Archive/audit iteration 7 without rerunning implementation or generating
# bit/LTX/XSA.  The source run must already be fully routed.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set source [file join $root reports ad9528_gt_rate_planner \
    timing_closure_iteration_7_split_output_network]
set out [file join $root reports ad9528_gt_rate_planner \
    timing_iteration7_split_output_network]
set ooc_dcp [file join $root laser_tx.runs \
    system_laser_tx_core_0_0_synth_1 system_laser_tx_core_0_0.dcp]
set routed_dcp [file join $source routed.dcp]
file mkdir $out

open_checkpoint $ooc_dcp
set patterns [dict create \
    pattern_index_reg *pattern_index_reg* \
    pattern_cursor_reg *pattern_cursor_reg* \
    pattern_mode_63_active *pattern_mode_63_active* \
    len_active_reg *len_active_reg* \
    next_phase_pattern_base_q *next_phase_pattern_base_q* \
    cross_next_valid_count_q *cross_next_valid_count_q* \
    current_pattern_q *current_pattern_q* \
    rotated_pattern_reg *rotated_pattern_reg*]
set fd [open [file join $out ooc_rtl_signature.txt] w]
puts $fd "ooc_dcp=$ooc_dcp"
dict for {name pattern} $patterns {
    set count [llength [get_cells -quiet -hier $pattern]]
    set count_by_name($name) $count
    puts $fd "$name=$count"
}
close $fd
if {$count_by_name(pattern_index_reg) == 0 ||
    $count_by_name(pattern_cursor_reg) != 0 ||
    $count_by_name(pattern_mode_63_active) == 0 ||
    $count_by_name(len_active_reg) != 0 ||
    $count_by_name(next_phase_pattern_base_q) != 0 ||
    $count_by_name(cross_next_valid_count_q) != 0 ||
    $count_by_name(current_pattern_q) != 0 ||
    $count_by_name(rotated_pattern_reg) != 0} {
    error "iteration-7 OOC RTL signature failed"
}
close_design

open_checkpoint $routed_dcp
set txusrclk_period [get_property PERIOD [get_clocks GT_TXUSRCLK_RUNTIME_MAX]]
set txusrclk2_period [get_property PERIOD [get_clocks GT_TXUSRCLK2_RUNTIME_MAX]]
if {abs($txusrclk_period - 3.103) > 0.001 ||
    abs($txusrclk2_period - 6.206) > 0.001} {
    error "runtime clock mismatch"
}

write_checkpoint -force [file join $out iteration7_split_output_network_routed.dcp]
report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded \
    -file [file join $out setup_top20.rpt]
report_timing -delay_type max -max_paths 100 -path_type full_clock_expanded \
    -file [file join $out setup_top100.rpt]
report_timing -delay_type min -max_paths 50 -path_type full_clock_expanded \
    -file [file join $out hold_top50.rpt]
report_timing -delay_type max -max_paths 50 -path_type full_clock_expanded \
    -input_pins -file [file join $out primitive_paths_top50.rpt]
report_high_fanout_nets -timing -load_types -max_nets 500 \
    -file [file join $out high_fanout_top500.rpt]
report_design_analysis -congestion -file [file join $out congestion.rpt]
report_route_status -file [file join $out route_status.rpt]
report_utilization -hierarchical \
    -file [file join $out utilization_hierarchical.rpt]
report_drc -file [file join $out drc.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 10000 \
    -nworst 1 -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 10000 \
    -nworst 1 -slack_lesser_than 0]
set setup_tns 0.0
foreach path $setup_paths {
    set setup_tns [expr {$setup_tns + [get_property SLACK $path]}]
}
set hold_ths 0.0
foreach path $hold_paths {
    set hold_ths [expr {$hold_ths + [get_property SLACK $path]}]
}
set setup_wns [get_property SLACK \
    [lindex [get_timing_paths -delay_type max -max_paths 1] 0]]
set hold_whs [get_property SLACK \
    [lindex [get_timing_paths -delay_type min -max_paths 1] 0]]
set fd [open [file join $out audit_metrics.txt] w]
puts $fd "txusrclk_period_ns=$txusrclk_period"
puts $fd "txusrclk2_period_ns=$txusrclk2_period"
puts $fd "setup_wns_ns=$setup_wns"
puts $fd "setup_tns_ns=$setup_tns"
puts $fd "setup_failing_endpoints=[llength $setup_paths]"
puts $fd "hold_whs_ns=$hold_whs"
puts $fd "hold_ths_ns=$hold_ths"
puts $fd "hold_failing_endpoints=[llength $hold_paths]"
puts $fd "bitstream_generated=0"
close $fd

set selected_nets [concat \
    [get_nets -quiet -hier -regexp \
        {.*u_pattern_tx_engine/p_0_in\[[0-9]+\]$}] \
    [get_nets -quiet -hier -regexp \
        {.*u_pattern_tx_engine/.*pattern_mode_63_active.*}] \
    [get_nets -quiet -hier -regexp \
        {.*u_pattern_tx_engine/.*rotate_sequence_(63|127).*}]]
set fd [open [file join $out selected_net_fanout.tsv] w]
puts $fd "net\tflat_pin_count\tdriver\tila_load_count"
foreach net [lsort -unique $selected_nets] {
    set pins [get_pins -quiet -of_objects $net]
    set drivers [filter $pins {DIRECTION == OUT}]
    set ila_count 0
    foreach pin [filter $pins {DIRECTION == IN}] {
        set cell_name [get_property -quiet NAME \
            [get_cells -quiet -of_objects $pin]]
        if {[string match "*ila*" [string tolower $cell_name]]} {
            incr ila_count
        }
    }
    puts $fd [join [list [get_property NAME $net] [llength $pins] \
        $drivers $ila_count] "\t"]
}
close $fd

close_design
puts "ITERATION7_SPLIT_OUTPUT_NETWORK_ARCHIVE_COMPLETE"

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ".."]]
set out [file join $root reports tx_sequence_v2_append_two_stage]
file mkdir $out

open_project [file join $root laser_tx.xpr]
open_run impl_1

report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join $out setup_top50.rpt]
report_timing -delay_type min -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join $out hold_top50.rpt]
report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $out clock_interaction.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_drc -file [file join $out drc.rpt]
report_utilization -hierarchical \
    -file [file join $out utilization.rpt]
report_route_status -file [file join $out route_status.rpt]
report_high_fanout_nets -fanout_greater_than 64 -max_nets 100 \
    -file [file join $out high_fanout.rpt]
report_design_analysis -congestion \
    -file [file join $out congestion.rpt]

proc sum_slack {paths} {
    set total 0.0
    foreach path $paths {
        set total [expr {$total + [get_property SLACK $path]}]
    }
    return $total
}

set setup_paths [get_timing_paths -quiet -delay_type max \
    -max_paths 100000 -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min \
    -max_paths 100000 -slack_lesser_than 0]
set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -quiet -delay_type min -max_paths 1]
set k1_paths [get_timing_paths -quiet -delay_type max \
    -group GT_TXUSRCLK2_RUNTIME_MAX -max_paths 100000 \
    -slack_lesser_than 0]
set k1_worst [get_timing_paths -quiet -delay_type max \
    -group GT_TXUSRCLK2_RUNTIME_MAX -max_paths 1]
set k2_paths [get_timing_paths -quiet -delay_type max \
    -group GT_TXUSRCLK2_RUNTIME_K2_MAX -max_paths 100000 \
    -slack_lesser_than 0]
set k2_worst [get_timing_paths -quiet -delay_type max \
    -group GT_TXUSRCLK2_RUNTIME_K2_MAX -max_paths 1]
set runtime_clocks [concat \
    [get_clocks -quiet GT_TXUSRCLK_RUNTIME*] \
    [get_clocks -quiet GT_TXUSRCLK2_RUNTIME*] \
    [get_clocks -quiet GT_EOM_CLK_RUNTIME*]]
set check_fp [open [file join $out check_timing.rpt] r]
set check_text [read $check_fp]
close $check_fp
set no_clock_count -1
set unconstrained_count -1
regexp {checking no_clock \(([0-9]+)\)} \
    $check_text -> no_clock_count
regexp {checking unconstrained_internal_endpoints \(([0-9]+)\)} \
    $check_text -> unconstrained_count
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set unrouted [get_nets -quiet -hier -filter {ROUTE_STATUS == UNROUTED}]

set metrics [open [file join $out metrics.txt] w]
puts $metrics "impl_strategy=[get_property STRATEGY [get_runs impl_1]]"
puts $metrics "wns_ns=[get_property SLACK $worst_setup]"
puts $metrics "tns_ns=[sum_slack $setup_paths]"
puts $metrics "setup_failing_endpoints=[llength $setup_paths]"
puts $metrics "whs_ns=[get_property SLACK $worst_hold]"
puts $metrics "ths_ns=[sum_slack $hold_paths]"
puts $metrics "hold_failing_endpoints=[llength $hold_paths]"
puts $metrics "k1_wns_ns=[get_property SLACK $k1_worst]"
puts $metrics "k1_tns_ns=[sum_slack $k1_paths]"
puts $metrics "k1_setup_failing_endpoints=[llength $k1_paths]"
puts $metrics "k2_wns_ns=[get_property SLACK $k2_worst]"
puts $metrics "k2_tns_ns=[sum_slack $k2_paths]"
puts $metrics "k2_setup_failing_endpoints=[llength $k2_paths]"
puts $metrics "runtime_clock_count=[llength $runtime_clocks]"
puts $metrics "no_clock_register_count=$no_clock_count"
puts $metrics "unconstrained_internal_endpoint_count=$unconstrained_count"
puts $metrics "drc_error_count=[llength $drc_errors]"
puts $metrics "unrouted_net_count=[llength $unrouted]"
puts $metrics "worst_setup_start=[get_property STARTPOINT_PIN $worst_setup]"
puts $metrics "worst_setup_end=[get_property ENDPOINT_PIN $worst_setup]"
puts $metrics \
    "worst_setup_logic_levels=[get_property LOGIC_LEVELS $worst_setup]"
puts $metrics \
    "worst_setup_logic_delay=[get_property DATAPATH_LOGIC_DELAY $worst_setup]"
puts $metrics \
    "worst_setup_net_delay=[get_property DATAPATH_NET_DELAY $worst_setup]"
close $metrics

puts "PATTERN_APPEND_TWO_STAGE_REPORT_COLLECTION_PASS"
close_project

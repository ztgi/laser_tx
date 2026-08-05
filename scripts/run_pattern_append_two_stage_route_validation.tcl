set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ".."]]
set project_path [file join $root laser_tx.xpr]
set out [file join $root reports tx_sequence_v2_append_two_stage]
file mkdir $out

proc require_complete {run_name} {
    set run_obj [get_runs $run_name]
    set progress [get_property PROGRESS $run_obj]
    set status [get_property STATUS $run_obj]
    puts "APPEND_TWO_STAGE: $run_name progress=$progress status=$status"
    if {$progress ne "100%" ||
        [string match -nocase "*error*" $status] ||
        [string match -nocase "*fail*" $status]} {
        error "$run_name did not complete successfully: $status"
    }
}

open_project $project_path
set impl_run [get_runs impl_1]
set expected_hook [file normalize \
    [file join $root scripts gt_profile0_impl_pre.tcl]]
set actual_hook [file normalize \
    [get_property STEPS.OPT_DESIGN.TCL.PRE $impl_run]]
if {$actual_hook ne $expected_hook} {
    error "impl_1 pre-hook mismatch: actual=$actual_hook expected=$expected_hook"
}

set core_ooc system_laser_tx_core_0_0_synth_1
if {[llength [get_runs -quiet $core_ooc]] == 0} {
    set bd_file [get_files -quiet */system.bd]
    generate_target all $bd_file
    create_ip_run $bd_file
}
reset_run $core_ooc
launch_runs $core_ooc -jobs 4
wait_on_run $core_ooc
require_complete $core_ooc

open_run $core_ooc
set meta_cells [get_cells -quiet -hier *append_meta_valid_q_reg*]
set next_cells [get_cells -quiet -hier *next_append_plan_valid_q_reg*]
set current_cells [get_cells -quiet -hier *current_append_plan_valid_q_reg*]
set old_append_cells [concat \
    [get_cells -quiet -hier *append_word_data_state_reg*] \
    [get_cells -quiet -hier *append_word_mask_state_reg*]]
if {[llength $meta_cells] == 0 ||
    [llength $next_cells] == 0 ||
    [llength $current_cells] == 0} {
    error "Two-stage append pipeline signature is missing"
}
if {[llength $old_append_cells] != 0} {
    error "Legacy single-cycle append plan registers remain"
}
report_utilization -hierarchical \
    -file [file join $out ooc_utilization.rpt]
set signature [open [file join $out ooc_signature.txt] w]
puts $signature "append_meta_valid_cells=[llength $meta_cells]"
puts $signature "next_append_plan_valid_cells=[llength $next_cells]"
puts $signature "current_append_plan_valid_cells=[llength $current_cells]"
puts $signature "legacy_append_plan_cells=[llength $old_append_cells]"
close $signature
close_design

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
require_complete synth_1

launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1
require_complete impl_1
open_run impl_1

report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join $out setup_top50.rpt]
report_timing -delay_type min -max_paths 50 \
    -path_type full_clock_expanded \
    -file [file join $out hold_top50.rpt]
report_timing_summary -delay_type min_max -max_paths 50 \
    -file [file join $out pulse_width_and_timing_summary.rpt]
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

proc sum_slack {paths} {
    set total 0.0
    foreach path $paths {
        set total [expr {$total + [get_property SLACK $path]}]
    }
    return $total
}

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
puts $metrics "impl_strategy=[get_property STRATEGY $impl_run]"
puts $metrics "impl_pre_hook=$actual_hook"
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
if {[llength $worst_setup]} {
    puts $metrics \
        "worst_setup_start=[get_property STARTPOINT_PIN $worst_setup]"
    puts $metrics \
        "worst_setup_end=[get_property ENDPOINT_PIN $worst_setup]"
    puts $metrics \
        "worst_setup_logic_levels=[get_property LOGIC_LEVELS $worst_setup]"
    puts $metrics \
        "worst_setup_logic_delay=[get_property DATAPATH_LOGIC_DELAY $worst_setup]"
    puts $metrics \
        "worst_setup_net_delay=[get_property DATAPATH_NET_DELAY $worst_setup]"
}
close $metrics

puts "PATTERN_APPEND_TWO_STAGE_ROUTE_VALIDATION_PASS"
close_project

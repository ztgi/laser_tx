set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ".."]]
set project_path [file join $root laser_tx.xpr]
set out [file join $root reports tx_scope_debug_outputs]
file mkdir $out

proc require_complete {run_name} {
    set run_obj [get_runs $run_name]
    set progress [get_property PROGRESS $run_obj]
    set status [get_property STATUS $run_obj]
    puts "TX_SCOPE_ROUTE: $run_name progress=$progress status=$status"
    if {$progress ne "100%"} {
        error "$run_name did not complete: $status"
    }
    if {[string match -nocase "*error*" $status] ||
        [string match -nocase "*fail*" $status]} {
        error "$run_name failed: $status"
    }
}

open_project $project_path

set impl_run [get_runs impl_1]
set expected_hook [file normalize [file join $root scripts gt_profile0_impl_pre.tcl]]
set actual_hook [file normalize \
    [get_property STEPS.OPT_DESIGN.TCL.PRE $impl_run]]
if {$actual_hook ne $expected_hook} {
    error "impl_1 pre-hook mismatch: actual=$actual_hook expected=$expected_hook"
}
puts "TX_SCOPE_ROUTE: impl_strategy=[get_property STRATEGY $impl_run]"
puts "TX_SCOPE_ROUTE: impl_pre_hook=$actual_hook"

set core_ooc system_laser_tx_core_0_0_synth_1
if {[llength [get_runs -quiet $core_ooc]] == 0} {
    set bd_file [get_files -quiet */system.bd]
    if {[llength $bd_file] != 1} {
        error "Expected exactly one system.bd; found: $bd_file"
    }
    generate_target all $bd_file
    # Vivado 2022.2 requires create_ip_run on the parent BD rather than on an
    # individual child XCI. This recreates the module-reference OOC run after
    # Refresh Module Reference invalidated the prior run object.
    create_ip_run $bd_file
}
if {[llength [get_runs -quiet $core_ooc]] != 1} {
    error "Affected OOC run is unavailable after create_ip_run: $core_ooc"
}
reset_run $core_ooc
launch_runs $core_ooc -jobs 4
wait_on_run $core_ooc
require_complete $core_ooc

reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
require_complete synth_1

# The selected Performance_ExplorePostRoutePhysOpt strategy includes a
# post-route physical-optimization step.  Run through that step so the
# reported QoR is comparable with the existing timing baseline, while still
# stopping before write_bitstream.
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1
require_complete impl_1
open_run impl_1

report_timing_summary -delay_type min_max -max_paths 100 \
    -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -path_type full_clock_expanded \
    -file [file join $out setup_top10.rpt]
report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -delay_type min_max \
    -file [file join $out clock_interaction.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_drc -file [file join $out drc.rpt]
report_io -file [file join $out io.rpt]
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_route_status -file [file join $out route_status.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max \
    -max_paths 100000 -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min \
    -max_paths 100000 -slack_lesser_than 0]
set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [expr {[llength $worst_setup] ?
    [get_property SLACK $worst_setup] : 0.0}]
set whs [expr {[llength $worst_hold] ?
    [get_property SLACK $worst_hold] : 0.0}]
set tns 0.0
foreach path $setup_paths {
    set tns [expr {$tns + [get_property SLACK $path]}]
}
set ths 0.0
foreach path $hold_paths {
    set ths [expr {$ths + [get_property SLACK $path]}]
}

set runtime_clocks [concat \
    [get_clocks -quiet GT_TXUSRCLK_RUNTIME_K*] \
    [get_clocks -quiet GT_TXUSRCLK2_RUNTIME_K*] \
    [get_clocks -quiet GT_EOM_CLK_RUNTIME_K*]]
set check_timing_file [open [file join $out check_timing.rpt] r]
set check_timing_text [read $check_timing_file]
close $check_timing_file
set no_clock_count -1
set unconstrained_count -1
regexp {checking no_clock \(([0-9]+)\)} \
    $check_timing_text -> no_clock_count
regexp {checking unconstrained_internal_endpoints \(([0-9]+)\)} \
    $check_timing_text -> unconstrained_count
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
set unrouted [get_nets -quiet -hier -filter {ROUTE_STATUS == UNROUTED}]
set oddr_cells [get_cells -quiet -hier -filter {REF_NAME == ODDR}]

set metrics [open [file join $out metrics.txt] w]
puts $metrics "impl_strategy=[get_property STRATEGY $impl_run]"
puts $metrics "impl_pre_hook=$actual_hook"
puts $metrics "wns_ns=$wns"
puts $metrics "tns_ns=$tns"
puts $metrics "setup_failing_endpoints=[llength $setup_paths]"
puts $metrics "whs_ns=$whs"
puts $metrics "ths_ns=$ths"
puts $metrics "hold_failing_endpoints=[llength $hold_paths]"
puts $metrics "runtime_clock_count=[llength $runtime_clocks]"
puts $metrics "no_clock_register_count=$no_clock_count"
puts $metrics "unconstrained_internal_endpoint_count=$unconstrained_count"
puts $metrics "drc_error_count=[llength $drc_errors]"
puts $metrics "unrouted_net_count=[llength $unrouted]"
puts $metrics "oddr_count=[llength $oddr_cells]"
puts $metrics "oddr_cells=$oddr_cells"
foreach p {gt_sequence_sync_out txusrclk2_monitor_out} {
    set port [get_ports -quiet $p]
    puts $metrics "$p.package_pin=[get_property PACKAGE_PIN $port]"
    puts $metrics "$p.iostandard=[get_property IOSTANDARD $port]"
    puts $metrics "$p.drive=[get_property DRIVE $port]"
    puts $metrics "$p.slew=[get_property SLEW $port]"
}
close $metrics

puts "TX_SCOPE_DEBUG_ROUTE_VALIDATION_PASS"
close_project

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set snapshot_dir [file join $repo_dir "reports" "pre_refresh_route"]
set dcp_path [file join $snapshot_dir "laser_tx_board_top_routed.dcp"]
set analysis_dir [file join $snapshot_dir "analysis"]
file mkdir $analysis_dir

if {![file exists $dcp_path]} {
    error "Pre-refresh routed checkpoint is missing: $dcp_path"
}

open_checkpoint $dcp_path

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 100 \
    -file [file join $analysis_dir "timing_summary_check_verbose.rpt"]

report_timing \
    -delay_type max \
    -path_type full_clock_expanded \
    -max_paths 100 \
    -nworst 2 \
    -sort_by group \
    -file [file join $analysis_dir "setup_top100_full_clock_expanded.rpt"]

report_timing \
    -delay_type min \
    -path_type full_clock_expanded \
    -max_paths 50 \
    -nworst 2 \
    -sort_by group \
    -file [file join $analysis_dir "hold_top50_full_clock_expanded.rpt"]

report_cdc \
    -details \
    -file [file join $analysis_dir "cdc_details.rpt"]

report_clock_interaction \
    -delay_type min_max \
    -file [file join $analysis_dir "clock_interaction.rpt"]

report_route_status \
    -file [file join $analysis_dir "route_status.rpt"]

report_drc \
    -ruledeck default \
    -file [file join $analysis_dir "drc_default.rpt"]

set summary_path [file join $analysis_dir "top_path_inventory.tsv"]
set summary_fp [open $summary_path "w"]
puts $summary_fp "kind\tslack_ns\tstart_clock\tend_clock\tstartpoint\tendpoint"

foreach {kind delay_type max_paths} {
    setup max 100
    hold min 50
} {
    foreach path [get_timing_paths -delay_type $delay_type -max_paths $max_paths -nworst 2] {
        set startpoint [get_property STARTPOINT_PIN $path]
        set endpoint [get_property ENDPOINT_PIN $path]
        set start_clock [get_property STARTPOINT_CLOCK $path]
        set end_clock [get_property ENDPOINT_CLOCK $path]
        set slack [get_property SLACK $path]
        puts $summary_fp "$kind\t$slack\t$start_clock\t$end_clock\t$startpoint\t$endpoint"
    }
}
close $summary_fp

close_design
puts "TX_SEQUENCE_V2_PRE_REFRESH_ROUTE_ANALYSIS_PASS"

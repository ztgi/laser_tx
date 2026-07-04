# Generate implementation timing/QoR reports, or fall back to synthesis when
# impl_1 has not completed. Run from the project root with Vivado batch mode.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set report_dir [file join $project_dir reports]
file mkdir $report_dir

if {[llength [get_projects -quiet]] == 0} {
    if {![file exists $project_file]} { error "Project not found: $project_file" }
    open_project $project_file
}

set impl_status [get_property STATUS [get_runs impl_1]]
if {[string match "*Complete*" $impl_status]} {
    puts "INFO: Opening completed impl_1 ($impl_status)."
    open_run impl_1
    report_timing_summary -file [file join $report_dir timing_summary_impl.rpt]
    report_timing -max_paths 50 -sort_by group -file [file join $report_dir worst_timing_paths.rpt]
    report_utilization -hierarchical -file [file join $report_dir util_impl_hier.rpt]
    report_high_fanout_nets -file [file join $report_dir high_fanout_nets.rpt]
    report_qor_suggestions -file [file join $report_dir qor_suggestions.rpt]
} else {
    set synth_status [get_property STATUS [get_runs synth_1]]
    if {![string match "*Complete*" $synth_status]} {
        error "Neither impl_1 nor synth_1 is complete (impl='$impl_status', synth='$synth_status')."
    }
    puts "WARNING: impl_1 is not complete ($impl_status); reporting completed synth_1 instead."
    open_run synth_1
    report_timing_summary -file [file join $report_dir timing_summary_synth.rpt]
    report_timing -max_paths 50 -sort_by group -file [file join $report_dir worst_timing_paths_synth.rpt]
    report_utilization -hierarchical -file [file join $report_dir util_synth_hier.rpt]
    report_high_fanout_nets -file [file join $report_dir high_fanout_nets_synth.rpt]
}

puts "INFO: Timing debug reports written to $report_dir"

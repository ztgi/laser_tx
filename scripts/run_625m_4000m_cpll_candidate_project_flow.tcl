# Reproducible project-flow build for the 625M/4000M candidate profiles.
# This script only runs project synthesis/implementation and writes reports
# beneath reports/.  It does not alter source-management, BD, XDC, or XSA.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set project_path [file join $repo_root laser_tx.xpr]
set report_dir [file join $repo_root reports dynamic_rate_625m_4000m_candidates]
file mkdir $report_dir

proc first_error_in_log {path} {
    if {![file exists $path]} {
        return ""
    }
    set fp [open $path r]
    set text [read $fp]
    close $fp
    foreach line [split $text "\n"] {
        if {[string first "ERROR:" $line] >= 0} {
            return $line
        }
    }
    return ""
}

proc write_summary {path lines} {
    set fp [open $path w]
    foreach line $lines {
        puts $fp $line
    }
    close $fp
}

open_project $project_path

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_run [get_runs synth_1]
set synth_status [get_property STATUS $synth_run]
set synth_dir [get_property DIRECTORY $synth_run]
set synth_error [first_error_in_log [file join $synth_dir runme.log]]

if {![string match "*Complete*" $synth_status]} {
    write_summary [file join $report_dir build_status_summary.txt] [list \
        "synth_status=$synth_status" \
        "synth_first_error=$synth_error"]
    puts "ERROR: synthesis did not complete: $synth_error"
    close_project
    exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_run [get_runs impl_1]
set impl_status [get_property STATUS $impl_run]
set impl_dir [get_property DIRECTORY $impl_run]
set impl_error [first_error_in_log [file join $impl_dir runme.log]]

write_summary [file join $report_dir build_status_summary.txt] [list \
    "synth_status=$synth_status" \
    "synth_first_error=$synth_error" \
    "impl_status=$impl_status" \
    "impl_first_error=$impl_error" \
    "bit_path=[file join $impl_dir laser_tx_board_top.bit]" \
    "ltx_path=[file join $impl_dir laser_tx_board_top.ltx]"]

if {![string match "*Complete*" $impl_status]} {
    puts "ERROR: implementation did not complete: $impl_error"
    close_project
    exit 1
}

open_run impl_1
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_io -file [file join $report_dir io.rpt]
report_debug_core -full_path -file [file join $report_dir debug_cores.rpt]
write_debug_probes -force [file join $impl_dir laser_tx_board_top.ltx]

puts "INFO: candidate build completed"
close_project

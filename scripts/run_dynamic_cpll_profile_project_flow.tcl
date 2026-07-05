set project_path "D:/FPGA_Learn/laser_tx/laser_tx.xpr"
set report_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_drp_profile"
set artifact_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_drp_profile/artifacts"
file mkdir $report_dir
file mkdir $artifact_dir

proc write_text_file {path text} {
    set fp [open $path w]
    puts $fp $text
    close $fp
}

proc first_error_in_log {path} {
    if {![file exists $path]} {
        return ""
    }
    set fp [open $path r]
    set log_data [read $fp]
    close $fp
    foreach line [split $log_data "\n"] {
        if {[string first "ERROR:" $line] >= 0} {
            return $line
        }
    }
    return ""
}

open_project $project_path

set fs [get_filesets sources_1]
set system_bd_path "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd"

# Keep the corrected project source-management properties. This script does
# not change RTL/BD functional connections; it only drives a reproducible
# project-flow build and report/artifact export.
set_property source_mgmt_mode All [current_project]
set_property top laser_tx_board_top $fs
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v $fs
set bd [get_files -quiet -of_objects $fs $system_bd_path]
if {[llength $bd] > 0} {
    set_property USED_IN {synthesis simulation} $bd
}
update_compile_order -fileset sources_1

set pre ""
append pre "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]\n"
append pre "top=[get_property top $fs]\n"
append pre "top_file=[get_property top_file $fs]\n"
append pre "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]\n"
append pre "system_bd_files=[get_files -of_objects $fs *system.bd]\n"
if {[llength $bd] > 0} {
    append pre "system_bd_USED_IN=[get_property USED_IN $bd]\n"
    append pre "system_bd_USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $bd]\n"
    append pre "system_bd_IS_AUTO_DISABLED=[get_property IS_AUTO_DISABLED $bd]\n"
}
write_text_file "$report_dir/pre_impl_project_properties.txt" $pre
report_compile_order -of_objects $fs -file "$report_dir/report_compile_order_before_impl.rpt"

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
set synth_dir [get_property DIRECTORY [get_runs synth_1]]
set synth_first_error [first_error_in_log "$synth_dir/runme.log"]

if {![string match "*Complete*" $synth_status]} {
    set summary ""
    append summary "synth_1_STATUS=$synth_status\n"
    append summary "synth_1_PROGRESS=$synth_progress\n"
    append summary "synth_1_DIR=$synth_dir\n"
    append summary "first_ERROR=$synth_first_error\n"
    write_text_file "$report_dir/build_failed_summary.txt" $summary
    puts $summary
    puts "ERROR: synth_1 did not complete. First error: $synth_first_error"
    close_project
    exit 1
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set impl_first_error [first_error_in_log "$impl_dir/runme.log"]

set bit_path "$impl_dir/laser_tx_board_top.bit"
set ltx_path "$impl_dir/laser_tx_board_top.ltx"
set bit_exists [file exists $bit_path]
set ltx_exists [file exists $ltx_path]

set summary ""
append summary "synth_1_STATUS=$synth_status\n"
append summary "synth_1_PROGRESS=$synth_progress\n"
append summary "synth_1_DIR=$synth_dir\n"
append summary "synth_1_first_ERROR=$synth_first_error\n"
append summary "impl_1_STATUS=$impl_status\n"
append summary "impl_1_PROGRESS=$impl_progress\n"
append summary "impl_1_DIR=$impl_dir\n"
append summary "impl_1_first_ERROR=$impl_first_error\n"
append summary "bit_path=$bit_path\n"
append summary "bit_exists=$bit_exists\n"
append summary "ltx_path=$ltx_path\n"
append summary "ltx_exists=$ltx_exists\n"
write_text_file "$report_dir/build_status_summary.txt" $summary
puts $summary

if {![string match "*Complete*" $impl_status]} {
    puts "ERROR: impl_1 did not complete. First error: $impl_first_error"
    close_project
    exit 1
}

open_run impl_1
report_timing_summary -file "$report_dir/timing_summary_dynamic_cpll_drp_profile.rpt"
report_clocks -file "$report_dir/clocks_dynamic_cpll_drp_profile.rpt"
report_utilization -file "$report_dir/utilization_dynamic_cpll_drp_profile.rpt"
report_debug_core -full_path -file "$report_dir/debug_cores_dynamic_cpll_drp_profile.rpt"
write_debug_probes -force $ltx_path

if {[file exists $bit_path]} {
    file copy -force $bit_path "$artifact_dir/laser_tx_board_top_dynamic_cpll_drp_profile.bit"
}
if {[file exists $ltx_path]} {
    file copy -force $ltx_path "$artifact_dir/laser_tx_board_top_dynamic_cpll_drp_profile.ltx"
}
file copy -force "$report_dir/timing_summary_dynamic_cpll_drp_profile.rpt" "$artifact_dir/timing_summary_dynamic_cpll_drp_profile.rpt"
file copy -force "$report_dir/debug_cores_dynamic_cpll_drp_profile.rpt" "$artifact_dir/debug_cores_dynamic_cpll_drp_profile.rpt"
file copy -force "$report_dir/utilization_dynamic_cpll_drp_profile.rpt" "$artifact_dir/utilization_dynamic_cpll_drp_profile.rpt"

set final ""
set artifact_bit_path "$artifact_dir/laser_tx_board_top_dynamic_cpll_drp_profile.bit"
set artifact_ltx_path "$artifact_dir/laser_tx_board_top_dynamic_cpll_drp_profile.ltx"
append final "synth_1_STATUS=$synth_status\n"
append final "impl_1_STATUS=$impl_status\n"
append final "impl_1_PROGRESS=$impl_progress\n"
append final "bit_path=$bit_path\n"
append final "bit_exists=[file exists $bit_path]\n"
append final "ltx_path=$ltx_path\n"
append final "ltx_exists=[file exists $ltx_path]\n"
append final "artifact_bit=$artifact_bit_path\n"
append final "artifact_bit_exists=[file exists $artifact_bit_path]\n"
append final "artifact_ltx=$artifact_ltx_path\n"
append final "artifact_ltx_exists=[file exists $artifact_ltx_path]\n"
append final "timing_report=$report_dir/timing_summary_dynamic_cpll_drp_profile.rpt\n"
append final "utilization_report=$report_dir/utilization_dynamic_cpll_drp_profile.rpt\n"
append final "debug_report=$report_dir/debug_cores_dynamic_cpll_drp_profile.rpt\n"
write_text_file "$report_dir/final_artifact_summary.txt" $final
puts $final

close_project

set project_path "D:/FPGA_Learn/laser_tx/laser_tx.xpr"
set report_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/project_impl1"
set artifact_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts"
file mkdir $report_dir
file mkdir $artifact_dir

proc write_text_file {path text} {
    set fp [open $path w]
    puts $fp $text
    close $fp
}

open_project $project_path

set fs [get_filesets sources_1]
set system_bd_path "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd"

# Keep current corrected project source attributes. These are source-management
# properties only; no RTL/BD functional connection is changed here.
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

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
set impl_dir [get_property DIRECTORY [get_runs impl_1]]

set bit_path "$impl_dir/laser_tx_board_top.bit"
set ltx_path "$impl_dir/laser_tx_board_top.ltx"
set bit_exists [file exists $bit_path]
set ltx_exists [file exists $ltx_path]

set first_error ""
set project_1840 ""
set write_bitstream_lines ""
set synth_top_lines ""
set runme "$impl_dir/runme.log"
if {[file exists $runme]} {
    set fp [open $runme r]
    set log_data [read $fp]
    close $fp
    foreach line [split $log_data "\n"] {
        if {$first_error eq "" && [string first "ERROR:" $line] >= 0} {
            set first_error $line
        }
        if {[string first "Project 1-840" $line] >= 0} {
            append project_1840 "$line\n"
        }
        if {[string first "write_bitstream" $line] >= 0 ||
            [string first "Bitstream" $line] >= 0 ||
            [string first "bitstream" $line] >= 0} {
            append write_bitstream_lines "$line\n"
        }
    }
}

set summary ""
append summary "impl_1_STATUS=$impl_status\n"
append summary "impl_1_PROGRESS=$impl_progress\n"
append summary "impl_1_DIR=$impl_dir\n"
append summary "impl_1_runme=$runme\n"
append summary "first_ERROR=$first_error\n"
append summary "project_1_840_matches=\n$project_1840\n"
append summary "write_bitstream_lines=\n$write_bitstream_lines\n"
append summary "bit_path=$bit_path\n"
append summary "bit_exists=$bit_exists\n"
append summary "ltx_path=$ltx_path\n"
append summary "ltx_exists=$ltx_exists\n"
write_text_file "$report_dir/impl1_status_summary.txt" $summary

puts $summary

if {![string match "*Complete*" $impl_status]} {
    puts "ERROR: impl_1 did not complete. First error: $first_error"
    close_project
    exit 1
}

open_run impl_1
report_timing_summary -file "$report_dir/impl1_timing_summary.rpt"
report_clocks -file "$report_dir/impl1_clocks.rpt"
report_utilization -file "$report_dir/impl1_utilization.rpt"
report_debug_core -full_path -file "$report_dir/impl1_debug_core_full_path.rpt"

write_debug_probes -force $ltx_path

if {[file exists $bit_path]} {
    file copy -force $bit_path "$artifact_dir/laser_tx_board_top_dynamic_500m_1000m.bit"
}
if {[file exists $ltx_path]} {
    file copy -force $ltx_path "$artifact_dir/laser_tx_board_top_dynamic_500m_1000m.ltx"
}
file copy -force "$report_dir/impl1_timing_summary.rpt" "$artifact_dir/impl1_timing_summary.rpt"
file copy -force "$report_dir/impl1_debug_core_full_path.rpt" "$artifact_dir/impl1_debug_core_full_path.rpt"

set final ""
append final "impl_1_STATUS=$impl_status\n"
append final "impl_1_PROGRESS=$impl_progress\n"
append final "bit_path=$bit_path\n"
append final "bit_exists=[file exists $bit_path]\n"
append final "ltx_path=$ltx_path\n"
append final "ltx_exists=[file exists $ltx_path]\n"
append final "artifact_bit=$artifact_dir/laser_tx_board_top_dynamic_500m_1000m.bit\n"
append final "artifact_bit_exists=[file exists "$artifact_dir/laser_tx_board_top_dynamic_500m_1000m.bit"]\n"
append final "artifact_ltx=$artifact_dir/laser_tx_board_top_dynamic_500m_1000m.ltx\n"
append final "artifact_ltx_exists=[file exists "$artifact_dir/laser_tx_board_top_dynamic_500m_1000m.ltx"]\n"
append final "timing_report=$report_dir/impl1_timing_summary.rpt\n"
append final "debug_report=$report_dir/impl1_debug_core_full_path.rpt\n"
write_text_file "$report_dir/final_artifact_summary.txt" $final
puts $final

close_project

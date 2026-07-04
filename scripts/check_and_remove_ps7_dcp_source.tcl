set project_path "D:/FPGA_Learn/laser_tx/laser_tx.xpr"
set report_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/ps7_dcp_source_check"
file mkdir $report_dir

proc write_file {path text} {
    set fp [open $path w]
    puts $fp $text
    close $fp
}

open_project $project_path
set fs [get_filesets sources_1]
set dcp_pattern "*system_processing_system7_0_0.dcp"
set system_bd_path "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd"

set_property source_mgmt_mode All [current_project]
set_property top laser_tx_board_top $fs
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v $fs

set bd [get_files -quiet -of_objects $fs $system_bd_path]
if {[llength $bd] > 0} {
    set_property USED_IN {synthesis simulation} $bd
}

update_compile_order -fileset sources_1

set before_src [get_files -quiet -of_objects $fs $dcp_pattern]
set before_all [get_files -quiet -all $dcp_pattern]

set txt ""
append txt "=== BEFORE REMOVE ===\n"
append txt "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]\n"
append txt "top=[get_property top $fs]\n"
append txt "top_file=[get_property top_file $fs]\n"
append txt "system_bd=[get_files -quiet -of_objects $fs $system_bd_path]\n"
if {[llength $bd] > 0} {
    append txt "system_bd_USED_IN=[get_property USED_IN $bd]\n"
    append txt "system_bd_USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $bd]\n"
    append txt "system_bd_IS_AUTO_DISABLED=[get_property IS_AUTO_DISABLED $bd]\n"
}
append txt "sources_1_dcp=$before_src\n"
append txt "all_dcp=$before_all\n"
append txt "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]\n"

write_file "$report_dir/before_summary.txt" $txt

set prop_file "$report_dir/system_processing_system7_0_0_dcp_properties_before.rpt"
set prop_fp [open $prop_file w]
if {[llength $before_src] > 0} {
    foreach f $before_src {
        puts $prop_fp "===== FILE OBJECT: $f ====="
        foreach p {FILESET_NAME USED_IN USED_IN_SYNTHESIS USED_IN_IMPLEMENTATION USED_IN_SIMULATION IS_AUTO_DISABLED IS_GENERATED IS_AVAILABLE FILE_TYPE NAME} {
            if {![catch {set v [get_property $p $f]}]} {
                puts $prop_fp "$p=$v"
            }
        }
        puts $prop_fp ""
        catch {report_property $f} rpt
        puts $prop_fp $rpt
        puts $prop_fp ""
    }
} else {
    puts $prop_fp "No $dcp_pattern file object found in sources_1."
}
close $prop_fp

# If the DCP exists as a fileset source object, remove only that project source
# object. Do not delete the DCP from disk; BD/IP OOC products may still exist
# under laser_tx.gen and can be managed by Vivado.
if {[llength $before_src] > 0} {
    puts "Removing DCP file object(s) from sources_1 only: $before_src"
    remove_files $before_src
}

update_compile_order -fileset sources_1

set after_src [get_files -quiet -of_objects $fs $dcp_pattern]
set after_all [get_files -quiet -all $dcp_pattern]

set txt ""
append txt "=== AFTER REMOVE BEFORE REOPEN ===\n"
append txt "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]\n"
append txt "top=[get_property top $fs]\n"
append txt "top_file=[get_property top_file $fs]\n"
append txt "sources_1_dcp=$after_src\n"
append txt "all_dcp=$after_all\n"
append txt "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]\n"
set bd [get_files -quiet -of_objects $fs $system_bd_path]
if {[llength $bd] > 0} {
    append txt "system_bd_USED_IN=[get_property USED_IN $bd]\n"
    append txt "system_bd_USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $bd]\n"
    append txt "system_bd_IS_AUTO_DISABLED=[get_property IS_AUTO_DISABLED $bd]\n"
}
write_file "$report_dir/after_remove_before_reopen_summary.txt" $txt

report_compile_order -of_objects $fs -file "$report_dir/report_compile_order_after_remove_before_reopen.rpt"

close_project

# Reopen and verify whether the DCP comes back automatically.
open_project $project_path
set fs [get_filesets sources_1]
update_compile_order -fileset sources_1

set reopen_src [get_files -quiet -of_objects $fs $dcp_pattern]
set reopen_all [get_files -quiet -all $dcp_pattern]
set bd [get_files -quiet -of_objects $fs $system_bd_path]

set txt ""
append txt "=== AFTER REOPEN ===\n"
append txt "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]\n"
append txt "top=[get_property top $fs]\n"
append txt "top_file=[get_property top_file $fs]\n"
append txt "sources_1_dcp=$reopen_src\n"
append txt "all_dcp=$reopen_all\n"
append txt "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]\n"
if {[llength $bd] > 0} {
    append txt "system_bd_USED_IN=[get_property USED_IN $bd]\n"
    append txt "system_bd_USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $bd]\n"
    append txt "system_bd_IS_AUTO_DISABLED=[get_property IS_AUTO_DISABLED $bd]\n"
}
write_file "$report_dir/after_reopen_summary.txt" $txt
report_compile_order -of_objects $fs -file "$report_dir/report_compile_order_after_reopen.rpt"

reset_run synth_1
launch_runs synth_1
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set log_path "D:/FPGA_Learn/laser_tx/laser_tx.runs/synth_1/runme.log"
set project_1840_matches ""
set synth_top_lines ""
if {[file exists $log_path]} {
    set fp [open $log_path r]
    set log_data [read $fp]
    close $fp
    foreach line [split $log_data "\n"] {
        if {[string first "Project 1-840" $line] >= 0} {
            append project_1840_matches "$line\n"
        }
        if {[string first "synth_design" $line] >= 0} {
            append synth_top_lines "$line\n"
        }
    }
}

set txt ""
append txt "synth_1_status=$synth_status\n"
append txt "synth_design_lines=\n$synth_top_lines\n"
append txt "project_1_840_matches=\n$project_1840_matches\n"
write_file "$report_dir/synth_1_check_summary.txt" $txt

puts "REPORT_DIR=$report_dir"
puts "AFTER_REOPEN_sources_1_dcp=$reopen_src"
puts "AFTER_REOPEN_all_dcp=$reopen_all"
puts "synth_1_status=$synth_status"
puts "project_1_840_matches=$project_1840_matches"

if {![string match "*Complete*" $synth_status]} {
    puts "ERROR: synth_1 did not complete successfully"
    exit 1
}

if {$project_1840_matches ne ""} {
    puts "ERROR: Project 1-840 still appears in synth_1 runme.log"
    exit 2
}

close_project

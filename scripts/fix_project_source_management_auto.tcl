set project_path "D:/FPGA_Learn/laser_tx/laser_tx.xpr"
set report_dir "D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/source_mgmt_fix"
file mkdir $report_dir

open_project $project_path

set fs [get_filesets sources_1]
set imported_wrapper "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v"
set generated_wrapper "D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v"
set top_file "D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v"
set system_bd "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd"

puts "==== BEFORE ===="
puts "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]"
puts "top=[get_property top $fs]"
puts "top_file=[get_property top_file $fs]"
puts "system_wrapper_files_before=[get_files -of_objects $fs *system_wrapper.v]"

# Restore automatic source management. Module Reference is not supported in
# manual compile order mode, so the project must allow Vivado to resolve BD
# module references automatically.
set_property source_mgmt_mode All [current_project]

# Keep only the imported wrapper as a normal project source. The generated BD
# wrapper may exist under laser_tx.gen, but it must not also be added to
# sources_1 as a regular HDL source.
set gen_matches [get_files -quiet -of_objects $fs $generated_wrapper]
if {[llength $gen_matches] > 0} {
    puts "Removing generated wrapper from sources_1 ordinary sources: $gen_matches"
    remove_files $gen_matches
}

set imported_matches [get_files -quiet -of_objects $fs $imported_wrapper]
if {[llength $imported_matches] == 0} {
    puts "Adding imported wrapper to sources_1: $imported_wrapper"
    add_files -norecurse -fileset $fs $imported_wrapper
}

set bd_matches [get_files -quiet -of_objects $fs $system_bd]
if {[llength $bd_matches] > 0} {
    puts "Enabling BD for synthesis/simulation: $bd_matches"
    set_property USED_IN {synthesis simulation} $bd_matches
}

# Remove generated HDL copies that were imported only for an earlier
# direct/manual build path. In automatic source management mode, BD/IP generated
# HDL must be resolved through the BD/XCI flow; keeping these imported copies as
# ordinary sources causes duplicate GT definitions and unresolved BD internal IP
# modules such as system_axi_bram_ctrl_0_0.
set imported_generated_root "D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/sources_1"
set imported_generated_files {}
foreach f [get_files -quiet -of_objects $fs "$imported_generated_root/*"] {
    lappend imported_generated_files $f
}
foreach f [get_files -quiet -of_objects $fs "$imported_generated_root/bd/*"] {
    lappend imported_generated_files $f
}
foreach f [get_files -quiet -of_objects $fs "$imported_generated_root/ip/*"] {
    lappend imported_generated_files $f
}
foreach f [get_files -quiet -of_objects $fs "$imported_generated_root/ip/*/*"] {
    lappend imported_generated_files $f
}
foreach f [get_files -quiet -of_objects $fs "$imported_generated_root/ip/*/*/*"] {
    lappend imported_generated_files $f
}
foreach f [lsort -unique $imported_generated_files] {
    if {[file normalize $f] ne [file normalize $imported_wrapper]} {
        puts "Removing imported generated HDL ordinary source: $f"
        remove_files $f
    }
}

# Let Vivado rebuild compile order first, then force the intended board top.
update_compile_order -fileset sources_1
set_property top laser_tx_board_top $fs
set_property top_file $top_file $fs

set fs [get_filesets sources_1]
update_compile_order -fileset sources_1
set_property top laser_tx_board_top $fs
set_property top_file $top_file $fs

set summary_file "$report_dir/source_mgmt_fix_summary.txt"
set fp [open $summary_file w]
puts $fp "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]"
puts $fp "top=[get_property top $fs]"
puts $fp "top_file=[get_property top_file $fs]"
puts $fp "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]"
puts $fp "laser_tx_board_top_files=[get_files -of_objects $fs *laser_tx_board_top.v]"
puts $fp "system_bd_files=[get_files -of_objects $fs *system.bd]"
set bd_check [get_files -quiet -of_objects $fs $system_bd]
if {[llength $bd_check] > 0} {
    puts $fp "system_bd_USED_IN=[get_property USED_IN $bd_check]"
    puts $fp "system_bd_USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $bd_check]"
    puts $fp "system_bd_IS_AUTO_DISABLED=[get_property IS_AUTO_DISABLED $bd_check]"
}
puts $fp "imported_generated_hdl_files=[get_files -quiet -of_objects $fs D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/sources_1/*]"
close $fp

puts "==== AFTER ===="
puts "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]"
puts "top=[get_property top $fs]"
puts "top_file=[get_property top_file $fs]"
puts "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]"
puts "system_bd_files=[get_files -of_objects $fs *system.bd]"
set bd_check [get_files -quiet -of_objects $fs $system_bd]
if {[llength $bd_check] > 0} {
    puts "system_bd_USED_IN=[get_property USED_IN $bd_check]"
    puts "system_bd_USED_IN_SYNTHESIS=[get_property USED_IN_SYNTHESIS $bd_check]"
    puts "system_bd_IS_AUTO_DISABLED=[get_property IS_AUTO_DISABLED $bd_check]"
}
puts "imported_generated_hdl_files=[get_files -quiet -of_objects $fs D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/sources_1/*]"

report_compile_order -fileset sources_1 -file "$report_dir/report_compile_order_sources_1.rpt"

reset_run synth_1
launch_runs synth_1
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
set fp [open "$report_dir/synth_1_status.txt" w]
puts $fp "synth_1_status=$synth_status"
puts $fp "source_mgmt_mode=[get_property source_mgmt_mode [current_project]]"
puts $fp "top=[get_property top $fs]"
puts $fp "top_file=[get_property top_file $fs]"
puts $fp "system_wrapper_files=[get_files -of_objects $fs *system_wrapper.v]"
puts $fp "system_bd_files=[get_files -of_objects $fs *system.bd]"
close $fp

if {[file exists "D:/FPGA_Learn/laser_tx/laser_tx.runs/synth_1/runme.log"]} {
    set log_data [read [open "D:/FPGA_Learn/laser_tx/laser_tx.runs/synth_1/runme.log" r]]
    set out [open "$report_dir/synth_1_runme_synth_design_lines.txt" w]
    foreach line [split $log_data "\n"] {
        if {[string match "*synth_design*" $line]} {
            puts $out $line
        }
    }
    close $out
}

puts "synth_1_status=$synth_status"
puts "summary_file=$summary_file"
puts "compile_order_report=$report_dir/report_compile_order_sources_1.rpt"
puts "synth_design_lines=$report_dir/synth_1_runme_synth_design_lines.txt"

if {![string match "*Complete*" $synth_status]} {
    puts "ERROR: synth_1 did not complete successfully"
    exit 1
}

close_project

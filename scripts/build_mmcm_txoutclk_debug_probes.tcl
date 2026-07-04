set proj D:/FPGA_Learn/laser_tx/laser_tx.xpr
set rpt_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m
set art_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts
file mkdir $rpt_dir
file mkdir $art_dir

open_project $proj
set_property source_mgmt_mode None [current_project]
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "SOURCE_MGMT_FOR_BUILD=[get_property source_mgmt_mode [current_project]]"
puts "TOP_FOR_BUILD=[get_property top [get_filesets sources_1]]"
puts "TOP_FILE_FOR_BUILD=[get_property top_file [get_filesets sources_1]]"
set system_bd D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd
set system_synth_v D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/synth/system.v
if {[file exists $system_synth_v] && [llength [get_files -quiet $system_synth_v]] == 0} {
    add_files -fileset sources_1 -norecurse $system_synth_v
}
if {[llength [get_files -quiet $system_synth_v]]} {
    set_property used_in_synthesis true [get_files $system_synth_v]
    set_property used_in_implementation true [get_files $system_synth_v]
}
if {[llength [get_files -quiet $system_bd]]} {
    set_property used_in_synthesis false [get_files $system_bd]
    set_property used_in_implementation false [get_files $system_bd]
}
if {[llength [get_files -quiet $system_bd]]} { puts "SYSTEM_BD_USED_SYNTH=[get_property used_in_synthesis [get_files $system_bd]]" } else { puts "SYSTEM_BD_USED_SYNTH=missing" }
puts "SYSTEM_SYNTH_V_PRESENT=[llength [get_files -quiet $system_synth_v]]"

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {[string first "synth_design Complete" $synth_status] < 0} {
    error "synth_1 did not complete successfully: $synth_status"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
if {[string first "write_bitstream Complete" $impl_status] < 0} {
    error "impl_1 did not complete bitstream successfully: $impl_status"
}

open_run impl_1
report_timing_summary -file [file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt]
report_clocks -file [file join $rpt_dir mmcm_txoutclk_debug_clocks.rpt]

set dbg_file [file join $rpt_dir mmcm_txoutclk_debug_core_full_path.rpt]
if {[file exists $dbg_file]} { file delete -force $dbg_file }
redirect -file $dbg_file {
    foreach c [get_debug_cores] {
        puts "============================================================"
        puts "DEBUG_CORE=$c"
        report_debug_core -full_path $c
    }
}

write_debug_probes -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
write_debug_probes -force [file join $art_dir laser_tx_board_top_dynamic_500m_1000m.ltx]
file copy -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit [file join $art_dir laser_tx_board_top_dynamic_500m_1000m.bit]
file copy -force [file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt] [file join $art_dir mmcm_txoutclk_debug_timing_summary.rpt]
file copy -force $dbg_file [file join $art_dir mmcm_txoutclk_debug_core_full_path.rpt]

set top_now [get_property top [current_fileset]]
puts "TOP_NOW=$top_now"
puts "BIT_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit"
puts "LTX_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx"
puts "ARTIFACT_BIT=[file join $art_dir laser_tx_board_top_dynamic_500m_1000m.bit]"
puts "ARTIFACT_LTX=[file join $art_dir laser_tx_board_top_dynamic_500m_1000m.ltx]"
puts "TIMING_REPORT=[file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt]"
puts "DEBUG_REPORT=$dbg_file"
close_project






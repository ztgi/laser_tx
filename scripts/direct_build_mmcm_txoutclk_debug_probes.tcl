set proj D:/FPGA_Learn/laser_tx/laser_tx.xpr
set rpt_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m
set art_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts
file mkdir $rpt_dir
file mkdir $art_dir

open_project $proj
set_property source_mgmt_mode None [current_project]
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "DIRECT_SOURCE_MGMT=[get_property source_mgmt_mode [current_project]]"
puts "DIRECT_TOP=[get_property top [get_filesets sources_1]]"

synth_design -top laser_tx_board_top -part xc7z100ffg900-2
write_checkpoint -force [file join $rpt_dir mmcm_txoutclk_debug_synth.dcp]

source D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $rpt_dir mmcm_txoutclk_debug_impl.dcp]

report_timing_summary -file [file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt]
report_clocks -file [file join $rpt_dir mmcm_txoutclk_debug_clocks.rpt]
report_utilization -file [file join $rpt_dir mmcm_txoutclk_debug_utilization.rpt]

set dbg_file [file join $rpt_dir mmcm_txoutclk_debug_core_full_path.rpt]
if {[file exists $dbg_file]} { file delete -force $dbg_file }
redirect -file $dbg_file {
    foreach c [get_debug_cores] {
        puts "============================================================"
        puts "DEBUG_CORE=$c"
        report_debug_core -full_path $c
    }
}

write_bitstream -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
write_debug_probes -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
write_bitstream -force [file join $art_dir laser_tx_board_top_dynamic_500m_1000m.bit]
write_debug_probes -force [file join $art_dir laser_tx_board_top_dynamic_500m_1000m.ltx]
file copy -force [file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt] [file join $art_dir mmcm_txoutclk_debug_timing_summary.rpt]
file copy -force $dbg_file [file join $art_dir mmcm_txoutclk_debug_core_full_path.rpt]

puts "BIT_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit"
puts "LTX_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx"
puts "ARTIFACT_BIT=[file join $art_dir laser_tx_board_top_dynamic_500m_1000m.bit]"
puts "ARTIFACT_LTX=[file join $art_dir laser_tx_board_top_dynamic_500m_1000m.ltx]"
puts "TIMING_REPORT=[file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt]"
puts "DEBUG_REPORT=$dbg_file"
close_project

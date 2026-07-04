set rpt_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m
set art_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts
file mkdir $rpt_dir
file mkdir $art_dir
file mkdir D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1
open_checkpoint [file join $rpt_dir mmcm_txoutclk_debug_impl.dcp]
report_timing_summary -file [file join $rpt_dir mmcm_txoutclk_debug_timing_summary.rpt]
report_clocks -file [file join $rpt_dir mmcm_txoutclk_debug_clocks.rpt]
report_utilization -file [file join $rpt_dir mmcm_txoutclk_debug_utilization.rpt]
set dbg_file [file join $rpt_dir mmcm_txoutclk_debug_core_full_path.rpt]
if {[file exists $dbg_file]} { file delete -force $dbg_file }
report_debug_core -full_path -file $dbg_file
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




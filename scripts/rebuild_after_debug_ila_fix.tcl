set report_dir D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts
file mkdir $report_dir

open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set_property top laser_tx_board_top [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {[string first "synth_design Complete" $synth_status] < 0} {
    error "synth_1 did not complete successfully: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
if {[string first "write_bitstream Complete" $impl_status] < 0} {
    error "impl_1 did not complete bitstream successfully: $impl_status"
}

open_run impl_1
report_timing_summary -file D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_timing_summary.rpt
report_debug_core -file D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_debug_core.rpt
report_clocks -file D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_clocks.rpt

write_debug_probes -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
write_debug_probes -force [file join $report_dir laser_tx_board_top_dynamic_500m_1000m.ltx]

file copy -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit \
    [file join $report_dir laser_tx_board_top_dynamic_500m_1000m.bit]

puts "BIT_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit"
puts "LTX_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx"
puts "ARTIFACT_BIT=[file join $report_dir laser_tx_board_top_dynamic_500m_1000m.bit]"
puts "ARTIFACT_LTX=[file join $report_dir laser_tx_board_top_dynamic_500m_1000m.ltx]"

close_project

open_project ./laser_tx.xpr
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
set prog [get_property PROGRESS [get_runs impl_1]]
puts "IMPL_1_STATUS=$st"
puts "IMPL_1_PROGRESS=$prog"
if {[string match -nocase *fail* $st]} {
    puts "IMPL_1_RESULT=FAILED"
    exit 1
}
open_run impl_1
report_timing_summary -file reports/dynamic_rate_500m_1000m/gui_project_timing_summary_impl_1.rpt
report_clock_utilization -file reports/dynamic_rate_500m_1000m/gui_project_clock_utilization_impl_1.rpt
write_debug_probes -force reports/dynamic_rate_500m_1000m/gui_project_laser_tx_board_top.ltx
puts "BIT_PATH=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit"
puts "LTX_PATH=D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_laser_tx_board_top.ltx"
close_project

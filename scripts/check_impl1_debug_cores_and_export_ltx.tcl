open_project ./laser_tx.xpr
open_run impl_1

set debug_cores [get_debug_cores -quiet]
puts "DEBUG_CORE_COUNT=[llength $debug_cores]"
foreach c $debug_cores {
    puts "DEBUG_CORE=$c"
}

set ila_cells [get_cells -hier -quiet -filter {NAME =~ "*ila*"}]
puts "ILA_CELL_COUNT=[llength $ila_cells]"
foreach c $ila_cells {
    puts "ILA_CELL=$c"
}

set dbg_hub_cells [get_cells -hier -quiet -filter {NAME =~ "*dbg_hub*"}]
puts "DBG_HUB_CELL_COUNT=[llength $dbg_hub_cells]"
foreach c $dbg_hub_cells {
    puts "DBG_HUB_CELL=$c"
}

if {[llength $debug_cores] > 0} {
    write_debug_probes -force D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
    write_debug_probes -force D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
    report_debug_core -file D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_debug_cores_impl_1.rpt
    puts "LTX_REEXPORTED=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx"
    puts "LTX_ARTIFACT_REEXPORTED=D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx"
} else {
    puts "NO_DEBUG_CORES_FOUND_SKIP_LTX_EXPORT"
}

close_project

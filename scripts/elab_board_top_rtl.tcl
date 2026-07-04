open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "TRY_TOP=[get_property top [get_filesets sources_1]]"
synth_design -rtl -top laser_tx_board_top -part xc7z100ffg900-2
close_project

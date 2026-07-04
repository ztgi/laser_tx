open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
puts "TOP_AFTER_UPDATE=[get_property top [get_filesets sources_1]]"
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "TOP_AFTER_SET=[get_property top [get_filesets sources_1]]"
puts "TOP_FILE_AFTER_SET=[get_property top_file [get_filesets sources_1]]"
save_project
close_project
open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
puts "TOP_AFTER_REOPEN=[get_property top [get_filesets sources_1]]"
puts "TOP_FILE_AFTER_REOPEN=[get_property top_file [get_filesets sources_1]]"
close_project

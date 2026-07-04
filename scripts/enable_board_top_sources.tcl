open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set critical_files [list \
 D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile0.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v]
foreach f $critical_files {
  puts "BEFORE $f auto=[get_property IS_AUTO_DISABLED [get_files $f]] enabled=[get_property IS_ENABLED [get_files $f]]"
  catch {set_property IS_AUTO_DISABLED false [get_files $f]} res
  puts "SET_AUTO_RESULT=$res"
  set_property used_in_synthesis true [get_files $f]
  set_property used_in_implementation true [get_files $f]
  puts "AFTER $f auto=[get_property IS_AUTO_DISABLED [get_files $f]] enabled=[get_property IS_ENABLED [get_files $f]]"
}
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "TOP_NOW=[get_property top [get_filesets sources_1]]"
close_project

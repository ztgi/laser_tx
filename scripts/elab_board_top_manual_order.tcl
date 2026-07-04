open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set_property source_mgmt_mode None [current_project]
set files [list \
 D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile0.v \
 D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v]
foreach f $files {
  puts "$f auto=[get_property IS_AUTO_DISABLED [get_files $f]] enabled=[get_property IS_ENABLED [get_files $f]]"
}
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "MANUAL_TOP=[get_property top [get_filesets sources_1]]"
synth_design -rtl -top laser_tx_board_top -part xc7z100ffg900-2
close_project

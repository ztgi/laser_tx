open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set files [list \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_cpll_railing.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_init.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_multi_gt.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_rx_startup_fsm.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_sync_block.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_tx_startup_fsm.v]
foreach f $files {
  if {![file exists $f]} { error "Missing generated GT HDL: $f" }
  if {[llength [get_files -quiet $f]] == 0} {
    puts "ADD_GT_HDL=$f"
    add_files -fileset sources_1 -norecurse $f
  } else {
    puts "GT_HDL_ALREADY_PRESENT=$f"
  }
  set_property used_in_synthesis true [get_files $f]
  set_property used_in_implementation true [get_files $f]
  set_property used_in_simulation true [get_files $f]
}
set gen_wrap D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v
if {[llength [get_files -quiet $gen_wrap]]} {
  set_property used_in_synthesis false [get_files $gen_wrap]
  set_property used_in_implementation false [get_files $gen_wrap]
  set_property used_in_simulation false [get_files $gen_wrap]
}
set_property source_mgmt_mode All [current_project]
update_compile_order -fileset sources_1
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "TOP_AFTER_ADD=[get_property top [get_filesets sources_1]]"
update_compile_order -fileset sources_1
puts "TOP_AFTER_FINAL_UPDATE=[get_property top [get_filesets sources_1]]"
close_project

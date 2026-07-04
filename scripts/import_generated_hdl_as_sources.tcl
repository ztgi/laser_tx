open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set import_files_list [list \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/synth/system.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_cpll_railing.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_init.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_multi_gt.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_rx_startup_fsm.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_sync_block.v \
  D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_tx_startup_fsm.v]
foreach f $import_files_list {
  if {![file exists $f]} { error "Missing generated HDL: $f" }
}
import_files -fileset sources_1 -norecurse -force $import_files_list
foreach f $import_files_list {
  set imported [get_files -quiet -all [file tail $f]]
  puts "IMPORTED_TAIL=[file tail $f] MATCHES=$imported"
}
set_property source_mgmt_mode None [current_project]
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
close_project

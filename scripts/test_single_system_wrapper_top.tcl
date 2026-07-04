open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
set gen_wrap D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v
set imp_wrap D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
puts "BEFORE_TOP=[get_property top [get_filesets sources_1]]"
puts "GEN_USED_SYNTH=[get_property used_in_synthesis [get_files $gen_wrap]]"
puts "IMP_USED_SYNTH=[get_property used_in_synthesis [get_files $imp_wrap]]"
set_property used_in_synthesis false [get_files $gen_wrap]
set_property used_in_implementation false [get_files $gen_wrap]
set_property used_in_simulation false [get_files $gen_wrap]
set_property used_in_synthesis true [get_files $imp_wrap]
set_property used_in_implementation true [get_files $imp_wrap]
set_property used_in_simulation true [get_files $imp_wrap]
update_compile_order -fileset sources_1
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
puts "AFTER_TOP=[get_property top [get_filesets sources_1]]"
update_compile_order -fileset sources_1
puts "AFTER_UPDATE_TOP=[get_property top [get_filesets sources_1]]"
puts "GEN_USED_SYNTH_AFTER=[get_property used_in_synthesis [get_files $gen_wrap]]"
puts "IMP_USED_SYNTH_AFTER=[get_property used_in_synthesis [get_files $imp_wrap]]"
close_project

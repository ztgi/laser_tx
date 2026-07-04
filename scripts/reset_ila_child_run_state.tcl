open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
if {[llength [get_runs system_ila_laser_axi_cfg_0_synth_1]]} {
    puts "BEFORE_STATUS=[get_property STATUS [get_runs system_ila_laser_axi_cfg_0_synth_1]]"
    reset_run system_ila_laser_axi_cfg_0_synth_1
    puts "AFTER_STATUS=[get_property STATUS [get_runs system_ila_laser_axi_cfg_0_synth_1]]"
}
puts "DCP_EXISTS=[file exists D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/ip/system_ila_laser_axi_cfg_0/system_ila_laser_axi_cfg_0.dcp]"
close_project

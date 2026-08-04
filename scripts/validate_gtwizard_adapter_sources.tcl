set root [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set gen [file join $root laser_tx.gen sources_1 ip gtwizard_0]
set rtl [file join $root laser_tx.srcs sources_1 new gtwizard_0_adapter.v]
read_verilog -sv [file join $gen gtwizard_0_gt.v]
read_verilog -sv [file join $gen gtwizard_0_cpll_railing.v]
read_verilog -sv [file join $gen gtwizard_0 example_design gtwizard_0_tx_startup_fsm.v]
read_verilog -sv [file join $gen gtwizard_0 example_design gtwizard_0_rx_startup_fsm.v]
read_verilog -sv [file join $gen gtwizard_0 example_design gtwizard_0_sync_block.v]
read_verilog -sv $rtl
read_verilog -sv [file join $root laser_tx.srcs sources_1 new laser_gt_tx_profile0.v]
read_verilog -sv [file join $root laser_tx.srcs sources_1 new laser_gt_usrclk_profile0.v]
read_verilog -sv [file join $root rtl laser_gt_rate_control_mux.v]
read_verilog -sv [file join $root rtl laser_gt_rate_resource_arbiter.v]
set_property top gtwizard_0_adapter [current_fileset]
set_property top_auto_set 0 [current_fileset]
update_compile_order -fileset sources_1
puts "GTWIZARD_ADAPTER_SOURCE_PARSE_PASS"
puts "GTWIZARD_ADAPTER_TOP=gtwizard_0_adapter"
synth_design -rtl -top gtwizard_0_adapter -part xc7z100ffg900-2
puts "GTWIZARD_ADAPTER_WRAPPER_RTL_SYNTH_PASS"
close_project

open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
open_bd_design D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd

proc ensure_input_port {name width} {
    set p [get_bd_ports -quiet $name]
    if {[llength $p] == 0} {
        if {$width == 1} {
            set p [create_bd_port -dir I $name]
        } else {
            set msb [expr {$width - 1}]
            set p [create_bd_port -dir I -from $msb -to 0 $name]
        }
    }
    return $p
}

proc connect_port_to_pin {port_name pin_name} {
    set port [get_bd_ports $port_name]
    set pin  [get_bd_pins $pin_name]
    set nets [get_bd_nets -quiet -of_objects $pin]
    if {[llength $nets] != 0} {
        disconnect_bd_net [lindex $nets 0] $pin
    }
    connect_bd_net $port $pin
}

set ila [get_bd_cells ila_laser_axi_cfg]
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {24} \
    CONFIG.C_PROBE0_WIDTH {32} \
    CONFIG.C_PROBE1_WIDTH {32} \
    CONFIG.C_PROBE2_WIDTH {1} \
    CONFIG.C_PROBE3_WIDTH {32} \
    CONFIG.C_PROBE4_WIDTH {32} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {8} \
    CONFIG.C_PROBE7_WIDTH {16} \
    CONFIG.C_PROBE8_WIDTH {16} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {8} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {1} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {1} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {32} \
    CONFIG.C_PROBE21_WIDTH {1} \
    CONFIG.C_PROBE22_WIDTH {1} \
    CONFIG.C_PROBE23_WIDTH {1} \
] $ila

ensure_input_port dbg_rate_state 8
ensure_input_port dbg_target_rate_mbps 16
ensure_input_port dbg_current_rate_mbps 16
ensure_input_port dbg_rate_error 1
ensure_input_port dbg_rate_error_code 8
ensure_input_port dbg_gt_drp_write_attempted 1
ensure_input_port dbg_mmcm_drp_write_attempted 1
ensure_input_port dbg_gt_drp_busy 1
ensure_input_port dbg_gt_drp_done 1
ensure_input_port dbg_gt_drp_error 1
ensure_input_port dbg_mmcm_drp_busy 1
ensure_input_port dbg_mmcm_drp_done 1
ensure_input_port dbg_mmcm_drp_error 1
ensure_input_port dbg_txusrclk2_alive_axi 1
ensure_input_port dbg_txusrclk2_freq_counter_axi 32
ensure_input_port dbg_tx_quiesce_req 1
ensure_input_port dbg_tx_idle_seen 1
ensure_input_port dbg_apply_enable_blocked 1

connect_port_to_pin dbg_rate_state                  ila_laser_axi_cfg/probe6
connect_port_to_pin dbg_target_rate_mbps            ila_laser_axi_cfg/probe7
connect_port_to_pin dbg_current_rate_mbps           ila_laser_axi_cfg/probe8
connect_port_to_pin dbg_rate_error                  ila_laser_axi_cfg/probe9
connect_port_to_pin dbg_rate_error_code             ila_laser_axi_cfg/probe10
connect_port_to_pin dbg_gt_drp_write_attempted      ila_laser_axi_cfg/probe11
connect_port_to_pin dbg_mmcm_drp_write_attempted    ila_laser_axi_cfg/probe12
connect_port_to_pin dbg_gt_drp_busy                 ila_laser_axi_cfg/probe13
connect_port_to_pin dbg_gt_drp_done                 ila_laser_axi_cfg/probe14
connect_port_to_pin dbg_gt_drp_error                ila_laser_axi_cfg/probe15
connect_port_to_pin dbg_mmcm_drp_busy               ila_laser_axi_cfg/probe16
connect_port_to_pin dbg_mmcm_drp_done               ila_laser_axi_cfg/probe17
connect_port_to_pin dbg_mmcm_drp_error              ila_laser_axi_cfg/probe18
connect_port_to_pin dbg_txusrclk2_alive_axi         ila_laser_axi_cfg/probe19
connect_port_to_pin dbg_txusrclk2_freq_counter_axi  ila_laser_axi_cfg/probe20
connect_port_to_pin dbg_tx_quiesce_req              ila_laser_axi_cfg/probe21
connect_port_to_pin dbg_tx_idle_seen                ila_laser_axi_cfg/probe22
connect_port_to_pin dbg_apply_enable_blocked        ila_laser_axi_cfg/probe23

validate_bd_design
save_bd_design
make_wrapper -files [get_files D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd] -top -force
add_files -norecurse D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v
update_compile_order -fileset sources_1
close_project

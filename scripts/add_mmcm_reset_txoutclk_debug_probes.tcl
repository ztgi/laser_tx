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
set cfg [list CONFIG.C_NUM_OF_PROBES {50}]
set widths {
    0 32  1 32  2 1   3 32  4 32  5 1
    6 8   7 16  8 16  9 1   10 8  11 1
    12 1  13 1  14 1  15 1  16 1  17 1
    18 1  19 1  20 32 21 1  22 1  23 1
    24 1  25 1  26 1  27 1  28 1  29 1
    30 1  31 1  32 1  33 1  34 1  35 7
    36 16 37 16 38 1  39 1  40 1  41 9
    42 16 43 16 44 1  45 1  46 1  47 16
    48 1  49 32
}
foreach {idx width} $widths {
    lappend cfg CONFIG.C_PROBE${idx}_WIDTH [list $width]
}
set_property -dict $cfg $ila

set port_widths {
    dbg_rate_state 8
    dbg_target_rate_mbps 16
    dbg_current_rate_mbps 16
    dbg_rate_error 1
    dbg_rate_error_code 8
    dbg_gt_drp_write_attempted 1
    dbg_mmcm_drp_write_attempted 1
    dbg_gt_drp_busy 1
    dbg_gt_drp_done 1
    dbg_gt_drp_error 1
    dbg_mmcm_drp_busy 1
    dbg_mmcm_drp_done 1
    dbg_mmcm_drp_error 1
    dbg_txusrclk2_alive_axi 1
    dbg_txusrclk2_freq_counter_axi 32
    dbg_tx_quiesce_req 1
    dbg_tx_idle_seen 1
    dbg_apply_enable_blocked 1
    dbg_tx_mmcm_reset_wizard 1
    dbg_tx_mmcm_reset_rate 1
    dbg_tx_mmcm_reset 1
    dbg_tx_mmcm_locked_raw 1
    dbg_tx_mmcm_locked_sync 1
    dbg_rate_gt_tx_reset 1
    dbg_gt0_gttxreset_effective 1
    dbg_rate_txuserrdy_block 1
    dbg_gt0_txuserrdy_effective 1
    dbg_txresetdone_sync 1
    dbg_gt_ready 1
    dbg_mmcm_drp_addr 7
    dbg_mmcm_drp_di 16
    dbg_mmcm_drp_do 16
    dbg_mmcm_drp_en 1
    dbg_mmcm_drp_we 1
    dbg_mmcm_drp_rdy 1
    dbg_gt_drp_addr 9
    dbg_gt_drp_di 16
    dbg_gt_drp_do 16
    dbg_gt_drp_en 1
    dbg_gt_drp_we 1
    dbg_gt_drp_rdy 1
    dbg_gt_drp_readback_value 16
    dbg_txoutclk_alive_axi 1
    dbg_timeout_count 32
}
foreach {name width} $port_widths {
    ensure_input_port $name $width
}

set probe_map {
    6  dbg_rate_state
    7  dbg_target_rate_mbps
    8  dbg_current_rate_mbps
    9  dbg_rate_error
    10 dbg_rate_error_code
    11 dbg_gt_drp_write_attempted
    12 dbg_mmcm_drp_write_attempted
    13 dbg_gt_drp_busy
    14 dbg_gt_drp_done
    15 dbg_gt_drp_error
    16 dbg_mmcm_drp_busy
    17 dbg_mmcm_drp_done
    18 dbg_mmcm_drp_error
    19 dbg_txusrclk2_alive_axi
    20 dbg_txusrclk2_freq_counter_axi
    21 dbg_tx_quiesce_req
    22 dbg_tx_idle_seen
    23 dbg_apply_enable_blocked
    24 dbg_tx_mmcm_reset_wizard
    25 dbg_tx_mmcm_reset_rate
    26 dbg_tx_mmcm_reset
    27 dbg_tx_mmcm_locked_raw
    28 dbg_tx_mmcm_locked_sync
    29 dbg_rate_gt_tx_reset
    30 dbg_gt0_gttxreset_effective
    31 dbg_rate_txuserrdy_block
    32 dbg_gt0_txuserrdy_effective
    33 dbg_txresetdone_sync
    34 dbg_gt_ready
    35 dbg_mmcm_drp_addr
    36 dbg_mmcm_drp_di
    37 dbg_mmcm_drp_do
    38 dbg_mmcm_drp_en
    39 dbg_mmcm_drp_we
    40 dbg_mmcm_drp_rdy
    41 dbg_gt_drp_addr
    42 dbg_gt_drp_di
    43 dbg_gt_drp_do
    44 dbg_gt_drp_en
    45 dbg_gt_drp_we
    46 dbg_gt_drp_rdy
    47 dbg_gt_drp_readback_value
    48 dbg_txoutclk_alive_axi
    49 dbg_timeout_count
}
foreach {idx name} $probe_map {
    connect_port_to_pin $name ila_laser_axi_cfg/probe$idx
}

validate_bd_design
save_bd_design
make_wrapper -files [get_files D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd] -top -force
set gen_wrapper D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v
set import_wrapper D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
file copy -force $gen_wrapper $import_wrapper
update_compile_order -fileset sources_1
close_project

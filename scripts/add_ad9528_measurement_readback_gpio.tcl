# Add a dedicated dual-channel, read-only AXI GPIO for the AD9528 OUT0
# measurement snapshot. Existing control/status GPIO definitions are not
# changed or repurposed.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set bd_file [file join $project_dir laser_tx.srcs sources_1 bd system system.bd]

open_project $project_file
open_bd_design $bd_file

set cell_name axi_gpio_ad9528_measure
set gpio [get_bd_cells -quiet $cell_name]
if {![llength $gpio]} {
    set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $cell_name]
}
set_property -dict [list \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_INPUTS {1} \
    CONFIG.C_ALL_OUTPUTS {0} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS_2 {0}] $gpio

set smc [get_bd_cells axi_smc]
if {[get_property CONFIG.NUM_MI $smc] < 4} {
    set_property CONFIG.NUM_MI {4} $smc
}

if {![llength [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins $cell_name/S_AXI]]]} {
    connect_bd_intf_net [get_bd_intf_pins axi_smc/M03_AXI] \
        [get_bd_intf_pins $cell_name/S_AXI]
}

foreach {source target} [list \
    processing_system7_0/FCLK_CLK0 $cell_name/s_axi_aclk \
    rst_ps7_0_50M/peripheral_aresetn $cell_name/s_axi_aresetn] {
    if {![llength [get_bd_nets -quiet -of_objects [get_bd_pins $target]]]} {
        connect_bd_net [get_bd_pins $source] [get_bd_pins $target]
    }
}

foreach {pin port_name} [list \
    $cell_name/gpio_io_i ad9528_measure_count_in \
    $cell_name/gpio2_io_i ad9528_measure_status_in] {
    set port [get_bd_ports -quiet $port_name]
    if {![llength $port]} {
        set port [create_bd_port -dir I -from 31 -to 0 $port_name]
    }
    if {![llength [get_bd_nets -quiet -of_objects [get_bd_pins $pin]]]} {
        connect_bd_net [get_bd_pins $pin] $port
    }
}

set addr_seg [get_bd_addr_segs $cell_name/S_AXI/Reg]
set existing_seg [get_bd_addr_segs -quiet \
    processing_system7_0/Data/SEG_axi_gpio_ad9528_measure_Reg]
if {![llength $existing_seg]} {
    assign_bd_address -offset 0x40030000 -range 64K $addr_seg
} else {
    set_property offset 0x40030000 $existing_seg
    set_property range 64K $existing_seg
}

validate_bd_design
save_bd_design
generate_target all [get_files $bd_file]

set wrapper_file [file join $project_dir laser_tx.gen sources_1 bd system hdl system_wrapper.v]
make_wrapper -files [get_files $bd_file] -top -force
if {![file exists $wrapper_file]} {
    error "Generated wrapper not found: $wrapper_file"
}
file copy -force $wrapper_file \
    [file join $project_dir laser_tx.srcs sources_1 imports hdl system_wrapper.v]

puts "INFO: Added $cell_name at 0x40030000 with count/status input channels."
close_project
# Add the independent dynamic-rate mailbox GPIO and 4 KiB descriptor BRAM.
# Existing AXI address segments and legacy control/status interfaces are kept.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set bd_file [file join $project_dir laser_tx.srcs sources_1 bd system system.bd]
set mailbox_sources [list \
    [file join $project_dir rtl laser_dynamic_rate_descriptor_reader.v] \
    [file join $project_dir rtl laser_dynamic_rate_mailbox.v] \
    [file join $project_dir rtl laser_gt_dynamic_rate_executor.v] \
    [file join $project_dir rtl laser_gt_rate_resource_arbiter.v] \
    [file join $project_dir rtl laser_gt_rate_control_mux.v]]

open_project $project_file
set wizard_xci [get_files -quiet */gtwizard_0.xci]
if {![llength $wizard_xci]} { error "gtwizard_0.xci not found" }
set_property IS_ENABLED false $wizard_xci
set wrapper_root [file join $project_dir laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0]
set wrapper_sources [concat \
    [glob -nocomplain [file join $wrapper_root *.v]] \
    [glob -nocomplain [file join $wrapper_root gtwizard_0 example_design *.v]]]
foreach source $wrapper_sources {
    if {![llength [get_files -quiet $source]]} {
        add_files -fileset sources_1 -norecurse $source
    }
}
foreach source $mailbox_sources {
    if {![llength [get_files -quiet $source]]} {
        add_files -fileset sources_1 -norecurse $source
    }
}
set_property include_dirs [list [file join $project_dir rtl]] [get_filesets sources_1]
open_bd_design $bd_file

# The existing debug/control input is also the functional quiesce gate for the
# TX module reference. Refresh only this changed module reference and connect
# the already-exported signal; no new external interface is introduced.
set tx_core [get_bd_cells -quiet laser_tx_core_0]
if {[llength $tx_core]} {
    update_compile_order -fileset sources_1
    update_module_reference system_laser_tx_core_0_0
    set quiesce_pin [get_bd_pins -quiet laser_tx_core_0/rate_apply_enable_blocked]
    set quiesce_port [get_bd_ports -quiet dbg_apply_enable_blocked]
    if {[llength $quiesce_pin] && [llength $quiesce_port]} {
        set quiesce_net [get_bd_nets -quiet -of_objects $quiesce_port]
        if {![llength $quiesce_net]} {
            error "dbg_apply_enable_blocked external port has no BD net"
        }
        set pin_nets [get_bd_nets -quiet -of_objects $quiesce_pin]
        puts "INFO: TX quiesce pin existing_nets=$pin_nets target_net=$quiesce_net"
        if {[lsearch -exact $pin_nets $quiesce_net] < 0} {
            connect_bd_net -net $quiesce_net $quiesce_pin
        }
    }
}

set smc [get_bd_cells axi_smc]
if {[get_property CONFIG.NUM_MI $smc] < 6} {
    set_property CONFIG.NUM_MI {6} $smc
}

set gpio_name axi_gpio_dynamic_mailbox
set gpio [get_bd_cells -quiet $gpio_name]
if {![llength $gpio]} {
    set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 $gpio_name]
}
set_property -dict [list \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO_WIDTH {4} \
    CONFIG.C_ALL_INPUTS {0} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS_2 {0}] $gpio

set bram_ctrl_name axi_bram_dyn_desc
set bram_ctrl [get_bd_cells -quiet $bram_ctrl_name]
if {![llength $bram_ctrl]} {
    set bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 $bram_ctrl_name]
}
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {0}] $bram_ctrl

set bram_name blk_mem_dyn_desc
set bram [get_bd_cells -quiet $bram_name]
if {![llength $bram]} {
    set bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 $bram_name]
}
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Write_Width_A {32} CONFIG.Read_Width_A {32} \
    CONFIG.Write_Depth_A {1024} \
    CONFIG.Write_Width_B {32} CONFIG.Read_Width_B {32} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Use_Byte_Write_Enable {true} CONFIG.Byte_Size {8}] $bram
puts "INFO: $bram_name Memory_Type=[get_property CONFIG.Memory_Type $bram] interfaces=[get_bd_intf_pins -of_objects $bram]"

# Export Port B before connecting the AXI controller to Port A. This prevents
# IP-Integrator connection automation from collapsing an otherwise unused
# second port while it propagates the Port A controller parameters.
set portb [get_bd_intf_ports -quiet dynamic_descriptor_bram_portb]
if {![llength $portb]} {
    make_bd_intf_pins_external [get_bd_intf_pins $bram_name/BRAM_PORTB]
    set portb [get_bd_intf_ports BRAM_PORTB_0]
    set_property name dynamic_descriptor_bram_portb $portb
}

foreach {master slave} [list \
    axi_smc/M04_AXI $gpio_name/S_AXI \
    axi_smc/M05_AXI $bram_ctrl_name/S_AXI \
    $bram_ctrl_name/BRAM_PORTA $bram_name/BRAM_PORTA] {
    if {![llength [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins $slave]]]} {
        connect_bd_intf_net [get_bd_intf_pins $master] [get_bd_intf_pins $slave]
    }
}

foreach cell [list $gpio_name $bram_ctrl_name] {
    foreach {source suffix} [list \
        processing_system7_0/FCLK_CLK0 s_axi_aclk \
        rst_ps7_0_50M/peripheral_aresetn s_axi_aresetn] {
        set target $cell/$suffix
        if {![llength [get_bd_nets -quiet -of_objects [get_bd_pins $target]]]} {
            connect_bd_net [get_bd_pins $source] [get_bd_pins $target]
        }
    }
}

foreach {pin port_name direction width} [list \
    $gpio_name/gpio_io_o dynamic_mailbox_control_out O 4 \
    $gpio_name/gpio2_io_i dynamic_mailbox_status_in I 32] {
    set port [get_bd_ports -quiet $port_name]
    if {![llength $port]} {
        set port [create_bd_port -dir $direction -from [expr {$width - 1}] -to 0 $port_name]
    }
    if {![llength [get_bd_nets -quiet -of_objects [get_bd_pins $pin]]]} {
        connect_bd_net [get_bd_pins $pin] $port
    }
}

proc ensure_addr {space segment offset range} {
    set existing [get_bd_addr_segs -quiet $space]
    if {![llength $existing]} {
        assign_bd_address -offset $offset -range $range $segment
    } else {
        set_property offset $offset $existing
        set_property range $range $existing
    }
}
ensure_addr processing_system7_0/Data/SEG_axi_gpio_dynamic_mailbox_Reg \
    [get_bd_addr_segs $gpio_name/S_AXI/Reg] 0x40040000 64K
ensure_addr processing_system7_0/Data/SEG_axi_bram_dyn_desc_Mem0 \
    [get_bd_addr_segs $bram_ctrl_name/S_AXI/Mem0] 0x42000000 4K

validate_bd_design
save_bd_design
generate_target all [get_files $bd_file]
make_wrapper -files [get_files $bd_file] -top -force
set generated_wrapper [file join $project_dir laser_tx.gen sources_1 bd system hdl system_wrapper.v]
if {![file exists $generated_wrapper]} {
    error "Generated wrapper not found: $generated_wrapper"
}
file copy -force $generated_wrapper \
    [file join $project_dir laser_tx.srcs sources_1 imports hdl system_wrapper.v]
puts "INFO: dynamic mailbox GPIO=0x40040000 descriptor BRAM=0x42000000/4K"
close_project

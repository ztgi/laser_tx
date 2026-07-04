# Connect laser_tx_core_0 to the existing Zynq/BRAM/GPIO infrastructure.
# Usage from the project root:
#   vivado -mode batch -source scripts/bd_connect_laser_tx_core.tcl
# The final integration uses the GT-user-clock adapter in laser_tx_board_top.
# Set USE_TEMP_TXCLK=1 only for the old PL-core/ILA-only bring-up build.
if {![info exists USE_TEMP_TXCLK]} { set USE_TEMP_TXCLK 0 }

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]

proc laser_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc laser_require_cell {name} {
    set obj [get_bd_cells -quiet $name]
    if {[llength $obj] != 1} { laser_fail "Required BD cell '$name' was not found." }
    return $obj
}

proc laser_require_pin {name} {
    set obj [get_bd_pins -quiet $name]
    if {[llength $obj] != 1} { laser_fail "Required BD pin '$name' was not found." }
    return $obj
}

proc laser_require_intf_pin {name} {
    set obj [get_bd_intf_pins -quiet $name]
    if {[llength $obj] != 1} { laser_fail "Required BD interface pin '$name' was not found." }
    return $obj
}

proc laser_connect_net {pin_a_name pin_b_name} {
    set pin_a [laser_require_pin $pin_a_name]
    set pin_b [laser_require_pin $pin_b_name]
    set net_a [get_bd_nets -quiet -of_objects $pin_a]
    set net_b [get_bd_nets -quiet -of_objects $pin_b]
    if {[llength $net_a] && [llength $net_b]} {
        if {$net_a eq $net_b} { return }
        laser_fail "Pins '$pin_a_name' and '$pin_b_name' are already on different nets."
    }
    if {[llength $net_a]} {
        connect_bd_net -net $net_a $pin_b
    } elseif {[llength $net_b]} {
        connect_bd_net -net $net_b $pin_a
    } else {
        connect_bd_net $pin_a $pin_b
    }
}

proc laser_connect_intf {pin_a_name pin_b_name} {
    set pin_a [laser_require_intf_pin $pin_a_name]
    set pin_b [laser_require_intf_pin $pin_b_name]
    set net_a [get_bd_intf_nets -quiet -of_objects $pin_a]
    set net_b [get_bd_intf_nets -quiet -of_objects $pin_b]
    if {[llength $net_a] && [llength $net_b]} {
        if {$net_a eq $net_b} { return }
        laser_fail "Interfaces '$pin_a_name' and '$pin_b_name' are already on different nets."
    }
    connect_bd_intf_net $pin_a $pin_b
}

proc laser_disconnect_if_same_net {source_name target_name} {
    set source_pin [laser_require_pin $source_name]
    set target_pin [laser_require_pin $target_name]
    set source_net [get_bd_nets -quiet -of_objects $source_pin]
    set target_net [get_bd_nets -quiet -of_objects $target_pin]
    if {[llength $source_net] && $source_net eq $target_net} {
        disconnect_bd_net $source_net $target_pin
        puts "INFO: Removed temporary connection $source_name -> $target_name"
    }
}

proc laser_make_external_once {pin_name preferred_name} {
    set pin [laser_require_pin $pin_name]
    set net [get_bd_nets -quiet -of_objects $pin]
    if {[llength $net]} {
        set ext [get_bd_ports -quiet -of_objects $net]
        if {[llength $ext]} {
            if {[llength $ext] != 1} {
                laser_fail "Pin '$pin_name' has multiple external ports: $ext"
            }
            if {[get_property NAME $ext] ne $preferred_name} {
                if {[llength [get_bd_ports -quiet $preferred_name]]} {
                    laser_fail "External port '$preferred_name' exists but is not connected to '$pin_name'."
                }
                set_property name $preferred_name $ext
            }
            puts "INFO: $pin_name is already external as [get_property NAME $ext]"
            return
        }
    }
    if {[llength [get_bd_ports -quiet $preferred_name]]} {
        laser_fail "External port '$preferred_name' exists but is not connected to '$pin_name'."
    }
    # make_bd_pins_external creates the port but does not reliably return its
    # object in Vivado 2022.2.  Resolve it from the newly-created net instead.
    make_bd_pins_external $pin
    set new_net [get_bd_nets -quiet -of_objects $pin]
    set new_port [get_bd_ports -quiet -of_objects $new_net]
    if {[llength $new_port] != 1} {
        laser_fail "Could not determine the external port created for '$pin_name'."
    }
    set_property name $preferred_name $new_port
}

proc laser_add_gt_status_gpio {} {
    set cell [get_bd_cells -quiet axi_gpio_gt_status]
    if {![llength $cell]} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_gt_status
        set_property -dict [list \
            CONFIG.C_IS_DUAL {0} \
            CONFIG.C_GPIO_WIDTH {32} \
            CONFIG.C_ALL_INPUTS {1} \
            CONFIG.C_ALL_OUTPUTS {0}] [get_bd_cells axi_gpio_gt_status]

        set smc [get_bd_cells axi_smc]
        set mi_count [get_property CONFIG.NUM_MI $smc]
        if {$mi_count < 3} {
            set_property CONFIG.NUM_MI {3} $smc
        }
        laser_connect_intf axi_smc/M02_AXI axi_gpio_gt_status/S_AXI
        laser_connect_net processing_system7_0/FCLK_CLK0 axi_gpio_gt_status/s_axi_aclk
        laser_connect_net rst_ps7_0_50M/peripheral_aresetn axi_gpio_gt_status/s_axi_aresetn
        assign_bd_address -offset 0x40020000 -range 64K \
            [get_bd_addr_segs axi_gpio_gt_status/S_AXI/Reg]
        puts "INFO: Added read-only axi_gpio_gt_status at 0x40020000."
    }
}

proc laser_externalize_gt_boundary {pin_name port_name direction {msb ""}} {
    set pin [laser_require_pin $pin_name]
    set net [get_bd_nets -quiet -of_objects $pin]
    set port [get_bd_ports -quiet $port_name]
    if {[llength $port]} {
        if {[llength $port] != 1} { laser_fail "Multiple BD ports named '$port_name'." }
        if {$msb ne "" && [get_property LEFT $port] ne $msb} {
            # Repair the scalar port made by an earlier interrupted run.
            delete_bd_objs $port
            set port {}
        }
    }
    if {[llength $port]} {
        if {[get_property DIR $port] ne $direction} {
            laser_fail "BD port '$port_name' direction is not '$direction'."
        }
        if {[llength $net] && [get_bd_nets -quiet -of_objects $port] ne $net} {
            laser_fail "BD port '$port_name' is not connected to '$pin_name'."
        }
        return
    }
    if {$msb eq ""} {
        set port [create_bd_port -dir $direction $port_name]
    } else {
        set port [create_bd_port -dir $direction -from $msb -to 0 $port_name]
    }
    if {[llength $net]} {
        connect_bd_net -net $net $port
    } else {
        connect_bd_net $pin $port
    }
}

if {[llength [get_projects -quiet]] == 0} {
    if {![file exists $project_file]} { laser_fail "Project not found: $project_file" }
    open_project $project_file
}

set system_bd [get_files -quiet */system.bd]
if {[llength $system_bd] != 1} { laser_fail "Expected exactly one system.bd in the project." }
if {[llength [get_bd_designs -quiet system]] == 0} { open_bd_design $system_bd }
current_bd_design system

foreach cell_name {
    processing_system7_0 rst_ps7_0_50M axi_smc axi_bram_ctrl_0
    blk_mem_gen_0 axi_gpio_0 laser_tx_core_0
} {
    laser_require_cell $cell_name
}

# Keep the original two-channel parameter GPIO unchanged.  GT health and
# word-count status use a separate, read-only AXI GPIO so no existing status
# bit is repurposed.
laser_add_gt_status_gpio

# Refresh the module-reference boundary after adding debug-only mirror ports.
set module_ref_ip [get_ips -quiet system_laser_tx_core_0_0]
if {[llength $module_ref_ip] != 1} {
    laser_fail "Generated module-reference IP system_laser_tx_core_0_0 was not found."
}
if {[catch {update_module_reference $module_ref_ip} refresh_msg]} {
    laser_fail "Could not refresh laser_tx_core_0 module reference: $refresh_msg"
}

# Enforce the supported AXI GPIO configuration.
set_property -dict [list \
    CONFIG.C_IS_DUAL {1} \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS_2 {0}] [get_bd_cells axi_gpio_0]

# Enforce dual-port memory and one-cycle, 32-bit Port B read behavior.
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Core {false}] [get_bd_cells blk_mem_gen_0]

foreach old_intf_port {BRAM_PORTB_0 gpio_rtl_0} {
    set old_obj [get_bd_intf_ports -quiet $old_intf_port]
    if {[llength $old_obj]} {
        puts "INFO: Removing obsolete external interface $old_intf_port"
        delete_bd_objs $old_obj
    }
}

laser_connect_intf laser_tx_core_0/BRAM_PORTB blk_mem_gen_0/BRAM_PORTB
laser_connect_net axi_gpio_0/gpio_io_o laser_tx_core_0/gpio_ctrl
laser_connect_net laser_tx_core_0/gpio_status axi_gpio_0/gpio2_io_i
laser_connect_net processing_system7_0/FCLK_CLK0 laser_tx_core_0/axi_clk
laser_connect_net rst_ps7_0_50M/peripheral_aresetn laser_tx_core_0/axi_rstn

if {$USE_TEMP_TXCLK} {
    laser_connect_net processing_system7_0/FCLK_CLK0 laser_tx_core_0/txusrclk2
    laser_connect_net rst_ps7_0_50M/peripheral_reset laser_tx_core_0/tx_rst
    puts "WARNING: txusrclk2 is temporarily connected to FCLK_CLK0 for PL-core bring-up only. Do not use this for final GTX transmission."
} else {
    laser_disconnect_if_same_net processing_system7_0/FCLK_CLK0 laser_tx_core_0/txusrclk2
    laser_disconnect_if_same_net rst_ps7_0_50M/peripheral_reset laser_tx_core_0/tx_rst
    puts "INFO: USE_TEMP_TXCLK=0. GT user-clock/reset are externalized to laser_tx_board_top."
}

# The GT adapter lives outside system.bd so its clock/data/status boundary is
# intentionally externalized through system_wrapper and connected only by
# laser_tx_board_top.  No generated wrapper HDL is edited manually.
foreach {pin_name port_name direction msb} {
    processing_system7_0/FCLK_CLK0 gt_ctrl_clk O {}
    rst_ps7_0_50M/peripheral_reset gt_ctrl_rst O {}
    laser_tx_core_0/txusrclk2 txusrclk2 I {}
    laser_tx_core_0/tx_rst tx_rst I {}
    laser_tx_core_0/gt_ready gt_ready I {}
    laser_tx_core_0/txdata txdata O {}
    laser_tx_core_0/valid_mask valid_mask O {}
    axi_gpio_gt_status/gpio_io_i gt_status_in I 31
} {
    laser_externalize_gt_boundary $pin_name $port_name $direction $msb
}

laser_make_external_once laser_tx_core_0/eom_out eom_out_0
laser_make_external_once laser_tx_core_0/soa_gate_out soa_gate_out_0
laser_make_external_once laser_tx_core_0/acq_trig_out acq_trig_out_0
laser_make_external_once laser_tx_core_0/acq_gate_out acq_gate_out_0

set gt_cells {}
foreach cell [get_bd_cells -quiet -hier] {
    set vlnv [get_property -quiet VLNV $cell]
    if {[string match "*:gtwizard:*" $vlnv] || [string match "*:gtwizard_ultrascale:*" $vlnv]} {
        lappend gt_cells $cell
    }
}
if {[llength $gt_cells]} {
    puts "INFO: GT Wizard candidate(s) found inside the BD: $gt_cells"
} else {
    puts "INFO: GT Wizard is intentionally instantiated in laser_tx_board_top, outside system.bd."
}
puts "INFO: txdata/valid_mask are externalized to laser_tx_board_top and feed laser_gt_tx_profile0."

set read_width_b [get_property -quiet CONFIG.Read_Width_B [get_bd_cells blk_mem_gen_0]]
set write_width_b [get_property -quiet CONFIG.Write_Width_B [get_bd_cells blk_mem_gen_0]]
if {$read_width_b ne "32" || $write_width_b ne "32"} {
    laser_fail "Block Memory Generator Port B width is not 32 bits (read=$read_width_b write=$write_width_b)."
}
if {[get_property CONFIG.Memory_Type [get_bd_cells blk_mem_gen_0]] ne "True_Dual_Port_RAM"} {
    laser_fail "blk_mem_gen_0 is not configured as True Dual Port RAM."
}

validate_bd_design
save_bd_design
puts "INFO: laser_tx_core BD integration completed successfully."

# Add separate AXI/config and TX-domain ILAs.
# Run bd_connect_laser_tx_core.tcl first so debug mirror ports are refreshed.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]

proc laser_ila_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc laser_ila_pin {name} {
    set obj [get_bd_pins -quiet $name]
    if {[llength $obj] != 1} { laser_ila_fail "Required ILA source/destination pin '$name' was not found." }
    return $obj
}

proc laser_ila_connect {source_name probe_name} {
    set source_pin [laser_ila_pin $source_name]
    set probe_pin [laser_ila_pin $probe_name]
    set source_net [get_bd_nets -quiet -of_objects $source_pin]
    set probe_net [get_bd_nets -quiet -of_objects $probe_pin]
    if {[llength $probe_net]} {
        if {[llength $source_net] && $probe_net eq $source_net} { return }
        # The script owns ILA probe mapping, so replace stale/previous mappings.
        disconnect_bd_net $probe_net $probe_pin
        set probe_net {}
    }
    if {[llength $source_net]} {
        connect_bd_net -net $source_net $probe_pin
    } else {
        # Debug-only mirror outputs intentionally have no functional consumer.
        connect_bd_net $source_pin $probe_pin
    }
}

proc laser_ila_connect_clock {source_name clock_name} {
    set source_pin [laser_ila_pin $source_name]
    set clock_pin [laser_ila_pin $clock_name]
    set source_net [get_bd_nets -quiet -of_objects $source_pin]
    set clock_net [get_bd_nets -quiet -of_objects $clock_pin]
    if {[llength $source_net] == 0} {
        laser_ila_fail "Clock source '$source_name' is not connected."
    }
    if {[llength $clock_net] && $clock_net ne $source_net} {
        disconnect_bd_net $clock_net $clock_pin
        set clock_net {}
    }
    if {[llength $clock_net] == 0} {
        connect_bd_net -net $source_net $clock_pin
    }
}

proc laser_get_or_create_ila {name probe_count} {
    set cell [get_bd_cells -quiet $name]
    if {[llength $cell] == 0} {
        set defs [get_ipdefs -all -quiet xilinx.com:ip:ila:*]
        if {[llength $defs] == 0} { laser_ila_fail "No Xilinx ILA IP definition is installed." }
        set cell [create_bd_cell -type ip -vlnv [lindex $defs end] $name]
    } elseif {[llength $cell] != 1 || ![string match "xilinx.com:ip:ila:*" [get_property VLNV $cell]]} {
        laser_ila_fail "BD object '$name' exists but is not an ILA IP."
    }
    set_property CONFIG.C_MONITOR_TYPE {Native} $cell
    set_property CONFIG.C_NUM_OF_PROBES $probe_count $cell
    set_property CONFIG.C_DATA_DEPTH {4096} $cell
    set_property CONFIG.C_ADV_TRIGGER {true} $cell
    return $cell
}

if {[llength [get_projects -quiet]] == 0} {
    if {![file exists $project_file]} { laser_ila_fail "Project not found: $project_file" }
    open_project $project_file
}
set system_bd [get_files -quiet */system.bd]
if {[llength $system_bd] != 1} { laser_ila_fail "Expected exactly one system.bd in the project." }
if {[llength [get_bd_designs -quiet system]] == 0} { open_bd_design $system_bd }
current_bd_design system

foreach required {processing_system7_0 laser_tx_core_0} {
    if {[llength [get_bd_cells -quiet $required]] != 1} { laser_ila_fail "Required BD cell '$required' was not found." }
}

set ila_axi [laser_get_or_create_ila ila_laser_axi_cfg 6]
set_property -dict [list \
    CONFIG.C_PROBE0_WIDTH {32} CONFIG.C_PROBE1_WIDTH {32} \
    CONFIG.C_PROBE2_WIDTH {1}  CONFIG.C_PROBE3_WIDTH {32} \
    CONFIG.C_PROBE4_WIDTH {32} CONFIG.C_PROBE5_WIDTH {1}] $ila_axi

laser_ila_connect_clock processing_system7_0/FCLK_CLK0 ila_laser_axi_cfg/clk
laser_ila_connect laser_tx_core_0/gpio_ctrl ila_laser_axi_cfg/probe0
laser_ila_connect laser_tx_core_0/gpio_status ila_laser_axi_cfg/probe1
laser_ila_connect laser_tx_core_0/dbg_bram_en ila_laser_axi_cfg/probe2
laser_ila_connect laser_tx_core_0/dbg_bram_addr ila_laser_axi_cfg/probe3
laser_ila_connect laser_tx_core_0/dbg_bram_dout ila_laser_axi_cfg/probe4
laser_ila_connect laser_tx_core_0/dbg_bram_rst ila_laser_axi_cfg/probe5

set ila_tx [laser_get_or_create_ila ila_laser_tx 16]
set_property -dict [list \
    CONFIG.C_PROBE0_WIDTH {64} CONFIG.C_PROBE1_WIDTH {64} \
    CONFIG.C_PROBE2_WIDTH {1}  CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1}  CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1}  CONFIG.C_PROBE7_WIDTH {1} \
    CONFIG.C_PROBE8_WIDTH {1}  CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {8} CONFIG.C_PROBE11_WIDTH {8} \
    CONFIG.C_PROBE12_WIDTH {1} CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} CONFIG.C_PROBE15_WIDTH {10}] $ila_tx

laser_ila_connect_clock laser_tx_core_0/txusrclk2 ila_laser_tx/clk
laser_ila_connect laser_tx_core_0/txdata ila_laser_tx/probe0
laser_ila_connect laser_tx_core_0/valid_mask ila_laser_tx/probe1
laser_ila_connect laser_tx_core_0/eom_out ila_laser_tx/probe2
laser_ila_connect laser_tx_core_0/soa_gate_out ila_laser_tx/probe3
laser_ila_connect laser_tx_core_0/acq_trig_out ila_laser_tx/probe4
laser_ila_connect laser_tx_core_0/acq_gate_out ila_laser_tx/probe5
laser_ila_connect laser_tx_core_0/dbg_busy_tx ila_laser_tx/probe6
laser_ila_connect laser_tx_core_0/dbg_done_tx ila_laser_tx/probe7
laser_ila_connect laser_tx_core_0/dbg_phase_active_tx ila_laser_tx/probe8
laser_ila_connect laser_tx_core_0/dbg_phase_start_pulse_tx ila_laser_tx/probe9
laser_ila_connect laser_tx_core_0/dbg_phase_offset_tx ila_laser_tx/probe10
laser_ila_connect laser_tx_core_0/dbg_current_state_tx ila_laser_tx/probe11
laser_ila_connect laser_tx_core_0/dbg_cfg_update_pulse_tx ila_laser_tx/probe12
laser_ila_connect laser_tx_core_0/dbg_pattern_valid_tx ila_laser_tx/probe13
laser_ila_connect laser_tx_core_0/dbg_engine_start_tx ila_laser_tx/probe14
laser_ila_connect laser_tx_core_0/dbg_gpio9_tx_bus ila_laser_tx/probe15

validate_bd_design
save_bd_design
puts "INFO: Added/updated ila_laser_axi_cfg and ila_laser_tx."

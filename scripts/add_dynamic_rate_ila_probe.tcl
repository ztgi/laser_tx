# Adds one packed, read-only dynamic-rate summary bus to the existing stable
# AXI/FCLK ILA. The functional mailbox/executor wiring is not modified.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
open_project [file join $root_dir laser_tx.xpr]

set bd_file [get_files -quiet */system.bd]
if {[llength $bd_file] != 1} {
    error "Expected exactly one system.bd, got: $bd_file"
}
open_bd_design $bd_file

set dbg_port [get_bd_ports -quiet dynamic_rate_debug_bus]
if {[llength $dbg_port] == 0} {
    set dbg_port [create_bd_port -dir I -from 31 -to 0 dynamic_rate_debug_bus]
}

set ila [get_bd_cells -quiet ila_laser_axi_cfg]
if {[llength $ila] != 1} {
    error "ila_laser_axi_cfg was not found"
}
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {51} \
    CONFIG.C_PROBE50_WIDTH {32}] $ila

set probe [get_bd_pins -quiet ila_laser_axi_cfg/probe50]
if {[llength [get_bd_nets -quiet -of_objects $probe]] == 0} {
    connect_bd_net $dbg_port $probe
}

validate_bd_design
save_bd_design
generate_target all $bd_file
close_bd_design [current_bd_design]
close_project

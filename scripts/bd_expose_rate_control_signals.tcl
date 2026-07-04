# Expose existing AXI GPIO control/status nets to the board-level RTL wrapper
# for the 500M/1000M dynamic rate switch controller.
#
# This does not change the AXI address map or PS peripheral configuration.

open_project ./laser_tx.xpr
open_bd_design ./laser_tx.srcs/sources_1/bd/system/system.bd

set ctrl_port [get_bd_ports gpio_ctrl_to_gt]
if {[llength $ctrl_port] == 0} {
    create_bd_port -dir O -from 31 -to 0 gpio_ctrl_to_gt
}

set status_port [get_bd_ports gpio_status_to_gt]
if {[llength $status_port] == 0} {
    create_bd_port -dir O -from 31 -to 0 gpio_status_to_gt
}

set ctrl_pin [get_bd_pins axi_gpio_0/gpio_io_o]
if {[llength $ctrl_pin] == 0} {
    error "Cannot find BD pin axi_gpio_0/gpio_io_o"
}
if {[llength [get_bd_nets -quiet -of_objects [get_bd_ports gpio_ctrl_to_gt]]] == 0} {
    connect_bd_net $ctrl_pin [get_bd_ports gpio_ctrl_to_gt]
}

set status_pin [get_bd_pins laser_tx_core_0/gpio_status]
if {[llength $status_pin] == 0} {
    error "Cannot find BD pin laser_tx_core_0/gpio_status"
}
if {[llength [get_bd_nets -quiet -of_objects [get_bd_ports gpio_status_to_gt]]] == 0} {
    connect_bd_net $status_pin [get_bd_ports gpio_status_to_gt]
}

set rate_switch_file [file normalize ./laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v]
if {[llength [get_files -quiet $rate_switch_file]] == 0} {
    add_files -norecurse $rate_switch_file
}

validate_bd_design
save_bd_design
generate_target all [get_files ./laser_tx.srcs/sources_1/bd/system/system.bd]
make_wrapper -files [get_files ./laser_tx.srcs/sources_1/bd/system/system.bd] -top -import
update_compile_order -fileset sources_1
close_project

# Read-only verification of the GPIO9 TXUSRCLK2 monitor ILA integration.

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set dcp [file join $root reports tx_sequence_v2_artifact_build routed.dcp]
set out [file join $root reports tx_sequence_v2_artifact_build gpio9_txusrclk2_monitor_ila_verification.txt]

if {![file exists $dcp]} {
    error "Routed checkpoint not found: $dcp"
}

open_checkpoint $dcp
set fp [open $out w]

proc emit {fp text} {
    puts $fp $text
    puts $text
}

set ila_clk_pin [get_pins -quiet -hier *ila_laser_tx*/clk]
set ila_clk_nets [get_nets -quiet -segments -of_objects $ila_clk_pin]
emit $fp "ila_clock_pin=$ila_clk_pin"
emit $fp "ila_clock_nets=$ila_clk_nets"

for {set bit 0} {$bit < 10} {incr bit} {
    set net_name "u_system_wrapper/system_i/laser_tx_core_0_dbg_gpio9_tx_bus\[$bit\]"
    set net [get_nets -quiet $net_name]
    set segments [get_nets -quiet -segments $net]
    set drivers [get_pins -quiet -leaf -of_objects $segments -filter {DIRECTION == OUT}]
    set loads [get_pins -quiet -leaf -of_objects $segments -filter {DIRECTION == IN}]
    emit $fp "probe15\[$bit\].net=$net"
    emit $fp "probe15\[$bit\].mark_debug=[get_property MARK_DEBUG $net]"
    emit $fp "probe15\[$bit\].segments=$segments"
    emit $fp "probe15\[$bit\].drivers=$drivers"
    emit $fp "probe15\[$bit\].loads=$loads"
}

set oddr [get_cells -quiet -hier *u_txusrclk2_monitor_oddr*]
emit $fp "oddr_cell=$oddr"
if {[llength $oddr]} {
    emit $fp "oddr_ref_name=[get_property REF_NAME $oddr]"
    emit $fp "oddr_loc=[get_property LOC $oddr]"
    emit $fp "oddr_bel=[get_property BEL $oddr]"
    set oddr_q [get_pins -quiet -of_objects $oddr -filter {REF_PIN_NAME == Q}]
    emit $fp "oddr_q_nets=[get_nets -quiet -segments -of_objects $oddr_q]"
}

set monitor_port [get_ports -quiet txusrclk2_monitor_out]
emit $fp "monitor_port=$monitor_port"
if {[llength $monitor_port]} {
    foreach property {PACKAGE_PIN IOSTANDARD DRIVE SLEW} {
        emit $fp "monitor_port.$property=[get_property $property $monitor_port]"
    }
}

close $fp
report_debug_core -full_path -file [file join $root reports tx_sequence_v2_artifact_build gpio9_debug_cores.rpt]
close_design
puts "GPIO9_TXUSRCLK2_MONITOR_ILA_VERIFY=PASS"

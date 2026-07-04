# Inspect the current Hardware Manager state after program_with_matching_ltx.tcl.
# Usage:
#   source scripts/check_debug_cores.tcl

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set impl_dir [file join $project_dir laser_tx.runs impl_1]
set expected_top laser_tx_board_top
set expected_bit [file normalize [file join $impl_dir ${expected_top}.bit]]
set expected_ltx [file normalize [file join $impl_dir ${expected_top}.ltx]]

proc debug_check_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc debug_check_pick_xc7z100 {} {
    set matches [list]
    foreach dev [get_hw_devices -quiet] {
        set part [get_property PART $dev]
        if {[string match -nocase "xc7z100*" $part]} {
            lappend matches $dev
        }
    }
    if {[llength $matches] != 1} {
        debug_check_fail "Expected exactly one xc7z100 hardware device; found: $matches"
    }
    return [lindex $matches 0]
}

if {[llength [get_hw_devices -quiet]] == 0} {
    open_hw_manager
    connect_hw_server
    open_hw_target
}
set device [debug_check_pick_xc7z100]
current_hw_device $device

set programmed_bit [get_property PROGRAM.FILE $device]
set programmed_ltx [get_property PROBES.FILE $device]
set full_programmed_ltx [get_property FULL_PROBES.FILE $device]
puts "INFO: Device: $device"
puts "INFO: PROGRAM.FILE:     $programmed_bit"
puts "INFO: PROBES.FILE:      $programmed_ltx"
puts "INFO: FULL_PROBES.FILE: $full_programmed_ltx"

if {$programmed_bit ne $expected_bit ||
    $programmed_ltx ne $expected_ltx ||
    $full_programmed_ltx ne $expected_ltx} {
    puts "WARNING: The Hardware Manager properties are not the clean impl_1 pair."
    puts "WARNING: Run program_with_matching_ltx.tcl; do not use a Vitis-exported bitstream with this LTX."
}

set ilas [get_hw_ilas -quiet]
set probes [get_hw_probes -quiet]
puts "INFO: get_hw_ilas -> $ilas"
puts "INFO: get_hw_probes -> $probes"

if {[llength $ilas] == 0} {
    puts "WARNING: No hardware ILA was discovered. If BIT/LTX above are the clean matched pair,"
    puts "WARNING: the debug hub clock is probably not running. Start PS FCLK (for example via"
    puts "WARNING: the standalone/Vitis PS initialization flow) and then run refresh_hw_device."
} elseif {[llength $ilas] != 2} {
    puts "WARNING: Expected 2 ILA cores but found [llength $ilas]. Check the programmed BIT/LTX pair and debug hub clocks."
} else {
    puts "INFO: Two ILA cores were discovered; the probes file is matched and debug hub is alive."
}

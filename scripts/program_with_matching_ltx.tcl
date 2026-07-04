# Program only the bit/LTX pair emitted by laser_tx.runs/impl_1.
# Usage:
#   vivado -mode tcl -source scripts/program_with_matching_ltx.tcl

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set impl_dir [file join $project_dir laser_tx.runs impl_1]
set expected_top laser_tx_board_top
set bit_file [file normalize [file join $impl_dir ${expected_top}.bit]]
set ltx_file [file normalize [file join $impl_dir ${expected_top}.ltx]]
set manifest [file normalize [file join $impl_dir ${expected_top}.bit_ltx_manifest.txt]]

proc debug_program_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc debug_program_pick_xc7z100 {} {
    set matches [list]
    foreach dev [get_hw_devices -quiet] {
        set part [get_property PART $dev]
        if {[string match -nocase "xc7z100*" $part]} {
            lappend matches $dev
        }
    }
    if {[llength $matches] != 1} {
        debug_program_fail "Expected exactly one xc7z100 hardware device; found: $matches"
    }
    return [lindex $matches 0]
}

foreach artifact [list $bit_file $ltx_file $manifest] {
    if {![file exists $artifact]} {
        debug_program_fail "Missing clean-rebuild artifact: $artifact. Run clean_rebuild_bit_ltx.tcl first."
    }
}

set manifest_text [read [set fd [open $manifest r]]]
close $fd
if {[string first "top=$expected_top" $manifest_text] < 0 ||
    [string first "bit_file=$bit_file" $manifest_text] < 0 ||
    [string first "ltx_file=$ltx_file" $manifest_text] < 0} {
    debug_program_fail "Manifest does not describe this impl_1 bit/LTX pair. Re-run clean_rebuild_bit_ltx.tcl."
}

open_hw_manager
connect_hw_server
open_hw_target
set device [debug_program_pick_xc7z100]
current_hw_device $device

set_property PROGRAM.FILE $bit_file $device
set_property PROBES.FILE $ltx_file $device
set_property FULL_PROBES.FILE $ltx_file $device
program_hw_devices $device
refresh_hw_device $device

puts "INFO: Hardware programmed from one implementation directory:"
puts "INFO: Device: $device"
puts "INFO: BIT:    $bit_file"
puts "INFO: LTX:    $ltx_file"
puts "INFO: Use check_debug_cores.tcl to verify the two matched ILA cores."

# Read-only preflight for the board-top debug build.
# Usage:
#   vivado -mode batch -source scripts/verify_debug_build_inputs.tcl

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set expected_top laser_tx_board_top

proc debug_preflight_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc debug_preflight_require_cells {stage pattern} {
    set cells [get_cells -hierarchical -quiet $pattern]
    if {[llength $cells] == 0} {
        debug_preflight_fail "$stage: required cell '$pattern' was not found."
    }
    puts "INFO: $stage: $pattern -> $cells"
}

if {[llength [get_projects -quiet]] == 0} {
    if {![file exists $project_file]} {
        debug_preflight_fail "Project not found: $project_file"
    }
    open_project $project_file
}

set actual_top [get_property top [current_fileset]]
puts "INFO: sources_1 top = $actual_top"
if {$actual_top ne $expected_top} {
    debug_preflight_fail "Expected top '$expected_top', got '$actual_top'."
}

set bad_xdc_refs [list]
foreach xdc [get_files -quiet -of_objects [get_filesets constrs_1]] {
    if {[file extension $xdc] ne ".xdc" || ![file exists $xdc]} {
        continue
    }
    set fd [open $xdc r]
    set contents [read $fd]
    close $fd
    if {[string first "SPI_1_0_ss2_o" $contents] >= 0} {
        lappend bad_xdc_refs $xdc
    }
}
if {[llength $bad_xdc_refs] != 0} {
    debug_preflight_fail "XDC constrains removed top port SPI_1_0_ss2_o: $bad_xdc_refs"
}
puts "INFO: constrs_1 contains no SPI_1_0_ss2_o constraint."

foreach run_name {synth_1 impl_1} {
    if {[llength [get_runs -quiet $run_name]] != 1} {
        debug_preflight_fail "Run '$run_name' was not found."
    }
    set status [get_property STATUS [get_runs $run_name]]
    if {![string match "*Complete*" $status]} {
        puts "WARNING: $run_name is not complete ($status); cell and port checks are skipped."
        continue
    }
    open_run $run_name
    puts "INFO: Checking $run_name."
    debug_preflight_require_cells $run_name *ila_laser_tx*
    debug_preflight_require_cells $run_name *ila_laser_axi_cfg*
    debug_preflight_require_cells $run_name *dbg_hub*

    set ss2_ports [get_ports -quiet *ss2*]
    if {[llength $ss2_ports] != 0} {
        debug_preflight_fail "$run_name: removed physical top port(s) still present: $ss2_ports"
    }
    set expected_spi_ports [lsort [list \
        SPI_1_0_io0_io SPI_1_0_io1_io SPI_1_0_sck_io \
        SPI_1_0_ss_io SPI_1_0_ss1_o]]
    set actual_spi_ports [lsort [get_ports -quiet SPI_1_0*]]
    if {$actual_spi_ports ne $expected_spi_ports} {
        debug_preflight_fail "$run_name: SPI_1_0 top ports differ. Expected $expected_spi_ports; got $actual_spi_ports"
    }
    puts "INFO: $run_name: physical SPI ports = $actual_spi_ports"
}

puts "INFO: Debug-build preflight passed. No design state was modified."

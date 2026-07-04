# Clean, board-top-only rebuild of the matching bitstream and ILA probes.
# Usage:
#   vivado -mode batch -source scripts/clean_rebuild_bit_ltx.tcl
# Optional before sourcing: set BUILD_JOBS <N>

if {![info exists BUILD_JOBS]} { set BUILD_JOBS 6 }

set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set expected_top laser_tx_board_top

proc debug_build_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc debug_build_require_cells {stage pattern} {
    set cells [get_cells -hierarchical -quiet $pattern]
    if {[llength $cells] == 0} {
        debug_build_fail "$stage: required cell '$pattern' was not found."
    }
    puts "INFO: $stage: $pattern -> $cells"
}

proc debug_build_check_xdc {} {
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
        debug_build_fail "XDC constrains removed top port SPI_1_0_ss2_o: $bad_xdc_refs"
    }
}

proc debug_build_check_design {stage expected_spi_ports} {
    debug_build_require_cells $stage *ila_laser_tx*
    debug_build_require_cells $stage *ila_laser_axi_cfg*
    debug_build_require_cells $stage *dbg_hub*

    set ss2_ports [get_ports -quiet *ss2*]
    if {[llength $ss2_ports] != 0} {
        debug_build_fail "$stage: removed physical top port(s) still present: $ss2_ports"
    }
    set actual_spi_ports [lsort [get_ports -quiet SPI_1_0*]]
    if {$actual_spi_ports ne $expected_spi_ports} {
        debug_build_fail "$stage: SPI_1_0 top ports differ. Expected $expected_spi_ports; got $actual_spi_ports"
    }
    puts "INFO: $stage: physical SPI ports = $actual_spi_ports"
}

if {[llength [get_projects -quiet]] == 0} {
    if {![file exists $project_file]} {
        debug_build_fail "Project not found: $project_file"
    }
    open_project $project_file
}

set_property top $expected_top [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[get_property top [current_fileset]] ne $expected_top} {
    debug_build_fail "sources_1 top must be $expected_top."
}
debug_build_check_xdc

set expected_spi_ports [lsort [list \
    SPI_1_0_io0_io SPI_1_0_io1_io SPI_1_0_sck_io \
    SPI_1_0_ss_io SPI_1_0_ss1_o]]

puts "INFO: Resetting synth_1 and impl_1 for a clean bit/LTX pair."
reset_run impl_1
reset_run synth_1

puts "INFO: Launching synthesis with top $expected_top."
launch_runs synth_1 -jobs $BUILD_JOBS
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    debug_build_fail "Synthesis did not complete successfully: $synth_status"
}
open_run synth_1
debug_build_check_design synth_1 $expected_spi_ports

puts "INFO: Launching implementation through write_bitstream."
launch_runs impl_1 -to_step write_bitstream -jobs $BUILD_JOBS
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    debug_build_fail "Implementation/bitstream did not complete successfully: $impl_status"
}
open_run impl_1
debug_build_check_design impl_1 $expected_spi_ports

set impl_dir [file normalize [get_property DIRECTORY [get_runs impl_1]]]
set bit_file [file join $impl_dir ${expected_top}.bit]
set ltx_file [file join $impl_dir ${expected_top}.ltx]
set debug_ltx_file [file join $impl_dir debug_nets.ltx]
foreach artifact [list $bit_file $ltx_file $debug_ltx_file] {
    if {![file exists $artifact]} {
        debug_build_fail "Required generated debug artifact is missing: $artifact"
    }
}

set manifest [file join $impl_dir ${expected_top}.bit_ltx_manifest.txt]
set fd [open $manifest w]
puts $fd "top=$expected_top"
puts $fd "bit_file=$bit_file"
puts $fd "bit_bytes=[file size $bit_file]"
puts $fd "bit_mtime=[clock format [file mtime $bit_file] -format {%Y-%m-%dT%H:%M:%S}]"
puts $fd "ltx_file=$ltx_file"
puts $fd "ltx_bytes=[file size $ltx_file]"
puts $fd "ltx_mtime=[clock format [file mtime $ltx_file] -format {%Y-%m-%dT%H:%M:%S}]"
puts $fd "debug_ltx_file=$debug_ltx_file"
puts $fd "build_run=impl_1"
close $fd

puts "INFO: Clean rebuild completed. Program only this matched pair:"
puts "BIT file: $bit_file"
puts "LTX file: $ltx_file"
puts "Manifest: $manifest"

# Clean project build for the AD9528-assisted runtime GT rate planner/mailbox.
# Generated reports/artifacts remain under reports/ and are not Git inputs.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports ad9528_gt_rate_planner stage6_build]
file mkdir $out
set impl_only [expr {$argc > 0 && [lindex $argv 0] eq "impl_only"}]

open_project [file join $root laser_tx.xpr]
set_property top laser_tx_board_top [get_filesets sources_1]

# Preserve the Stage-3 source policy: the XCI is parameter provenance, while
# the tracked wrapper sources expose the dynamic GTNORTHREFCLK controls.
set wizard_xci [get_files -quiet */gtwizard_0.xci]
if {![llength $wizard_xci]} { error "gtwizard_0.xci not found" }
set_property IS_ENABLED false $wizard_xci
set wrapper_root [file join $root laser_tx.srcs sources_1 imports sources_1 ip gtwizard_0]
set wrapper_sources [concat \
    [glob -nocomplain [file join $wrapper_root *.v]] \
    [glob -nocomplain [file join $wrapper_root gtwizard_0 example_design *.v]]]
foreach source $wrapper_sources {
    if {![llength [get_files -quiet $source]]} {
        add_files -fileset sources_1 -norecurse $source
    }
}

set bd_file [get_files -quiet */system.bd]
open_bd_design $bd_file
validate_bd_design
save_bd_design
generate_target all $bd_file
close_bd_design [current_bd_design]
update_compile_order -fileset sources_1

reset_run impl_1
if {!$impl_only} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
}
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 is not complete: $synth_status"
}

launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 failed: $impl_status"
}

open_run impl_1
report_timing_summary -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out utilization.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_clock_networks -file [file join $out clock_networks.rpt]
report_io -file [file join $out io.rpt]
report_debug_core -full_path -file [file join $out debug_cores.rpt]

# A completed implementation run is not a timing-pass result.  Gate artifact
# generation on the routed setup/hold slack so a diagnostic build cannot be
# mislabeled as board-ready.
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path  [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_wns  [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : -999.0}]
set hold_whs   [expr {[llength $hold_path]  ? [get_property SLACK $hold_path]  : -999.0}]

set fd [open [file join $out build_status.txt] w]
puts $fd "synth_status=$synth_status"
puts $fd "impl_status=$impl_status"
puts $fd "setup_wns_ns=$setup_wns"
puts $fd "hold_whs_ns=$hold_whs"

if {$setup_wns < 0.0 || $hold_whs < 0.0} {
    puts $fd "timing_status=FAIL"
    close $fd
    error "Stage-6 timing failed: setup WNS=$setup_wns ns, hold WHS=$hold_whs ns; bit/LTX/XSA not promoted"
}
puts $fd "timing_status=PASS"
close $fd

close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "impl_1 bitstream step failed: $impl_status"
}
open_run impl_1

set impl_dir [file normalize [get_property DIRECTORY [get_runs impl_1]]]
set bit_path [file join $impl_dir laser_tx_board_top.bit]
set ltx_path [file join $impl_dir laser_tx_board_top.ltx]
write_debug_probes -force $ltx_path
set xsa_path [file join $out laser_tx_board_top_runtime_rate_switch.xsa]
write_hw_platform -fixed -include_bit -force -file $xsa_path

set fd [open [file join $out build_status.txt] a]
puts $fd "synth_status=$synth_status"
puts $fd "impl_status=$impl_status"
puts $fd "bit=$bit_path"
puts $fd "ltx=$ltx_path"
puts $fd "xsa=$xsa_path"
close $fd
puts "STAGE6_RUNTIME_RATE_SWITCH_BUILD=PASS"
puts "BIT=$bit_path"
puts "LTX=$ltx_path"
puts "XSA=$xsa_path"
close_project

set script_dir [file dirname [file normalize [info script]]]
set root [file dirname $script_dir]
set out [file join $root reports ad9528_gt_rate_planner stage3_build]
file mkdir $out

open_project [file join $root laser_tx.xpr]
set wizard_xci [get_files -quiet */gtwizard_0.xci]
if {![llength $wizard_xci]} { error "gtwizard_0.xci not found" }
# The XCI remains the parameter provenance package, but its generated wrapper
# cannot expose the dynamic GTNORTHREFCLK/CPLLREFCLKSEL control ports. Compile
# the tracked wrapper sources instead; do not edit or commit laser_tx.gen.
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
open_bd_design [file join $root laser_tx.srcs sources_1 bd system system.bd]
validate_bd_design
set fd [open [file join $out validate_bd_design.txt] w]
puts $fd "validate_bd_design=PASS"
close $fd

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
set fd [open [file join $out synth_status.txt] w]
puts $fd $synth_status
close $fd
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 failed: $synth_status"
}
open_run synth_1
report_utilization -file [file join $out post_synth_utilization.rpt]
report_timing_summary -file [file join $out post_synth_timing_summary.rpt]
close_project

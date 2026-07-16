# Capture project/run metadata used to build the timing-clean RTL manifest.
# This script is read-only with respect to design sources.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports ad9528_gt_rate_planner \
    timing_iteration7_split_output_network]
file mkdir $out

open_project [file join $root laser_tx.xpr]
set run [get_runs impl_1]
set fd [open [file join $out project_run_metadata.txt] w]
puts $fd "vivado_version=[version -short]"
puts $fd "device=[get_property PART [current_project]]"
puts $fd "top=[get_property TOP [get_filesets sources_1]]"
puts $fd "strategy=[get_property STRATEGY $run]"
puts $fd "opt_design=[get_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE $run]"
puts $fd "place_design=[get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $run]"
puts $fd "phys_opt_design=[get_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE $run]"
puts $fd "route_design=[get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE $run]"
puts $fd "runtime_clock_hook=[file normalize \
    [get_property STEPS.OPT_DESIGN.TCL.PRE $run]]"
close $fd

set fd [open [file join $out active_implementation_xdc.txt] w]
foreach xdc [lsort -unique [get_files -quiet -all -filter \
        {FILE_TYPE == XDC && USED_IN_IMPLEMENTATION == 1 && IS_ENABLED == 1}]] {
    puts $fd [file normalize $xdc]
}
close $fd
close_project
puts "TIMING_CLEAN_BASELINE_METADATA_CAPTURE_COMPLETE"

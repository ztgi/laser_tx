# Rebuild a fixed-refclk baseline from an explicitly selected source worktree.
# Usage:
#   vivado -mode batch -source scripts/build_rollback_fixed_refclk_baseline.tcl \
#     -tclargs <baseline_source_root> <report_output_dir>

if {$argc != 2} {
    error "Expected arguments: <baseline_source_root> <report_output_dir>"
}

set baseline_root [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
set project_path [file join $baseline_root laser_tx.xpr]

if {![file isfile $project_path]} {
    error "Baseline project does not exist: $project_path"
}
if {[file exists $report_dir]} {
    error "Refusing to reuse report output directory: $report_dir"
}
file mkdir $report_dir

open_project $project_path
puts "BASELINE_PROJECT_DIRECTORY=[get_property DIRECTORY [current_project]]"
puts "BASELINE_TOP=[get_property TOP [get_filesets sources_1]]"

# system.bd is the only BD generation entry.  Its nested IP are deliberately
# not passed to generate_target/create_ip_run as independent objects.
set top_bd [get_files -quiet */system.bd]
if {[llength $top_bd] != 1} {
    error "Expected one top-level system.bd, got: $top_bd"
}
open_bd_design $top_bd
validate_bd_design
close_bd_design [current_bd_design]
generate_target all $top_bd
export_ip_user_files -of_objects $top_bd -no_script -sync -force -quiet

# The GT Wizard XCI is a standalone project IP, not a nested system.bd child.
set gt_wizard [get_files -quiet */gtwizard_0.xci]
if {[llength $gt_wizard] != 1} {
    error "Expected one standalone gtwizard_0.xci, got: $gt_wizard"
}
generate_target all $gt_wizard
export_ip_user_files -of_objects $gt_wizard -no_script -sync -force -quiet

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Baseline synthesis failed: $synth_status"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*write_bitstream Complete*" $impl_status]} {
    error "Baseline implementation failed: $impl_status"
}

open_run impl_1
set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_path [file join $impl_dir laser_tx_board_top.bit]
set ltx_path [file join $impl_dir laser_tx_board_top.ltx]
write_debug_probes -force $ltx_path
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_debug_core -full_path -file [file join $report_dir debug_cores.rpt]
report_utilization -file [file join $report_dir utilization.rpt]

set xsa_path [file join $report_dir laser_tx_board_top_fixed_125m_baseline.xsa]
write_hw_platform -fixed -include_bit -force -file $xsa_path

puts "BASELINE_BUILD=PASS"
puts "SYNTH_STATUS=$synth_status"
puts "IMPL_STATUS=$impl_status"
puts "BIT=$bit_path"
puts "LTX=$ltx_path"
puts "XSA=$xsa_path"
close_project
exit

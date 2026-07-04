# Reproducible final-hardware build for the fixed GT Profile 0.
# Run from the project root:
#   vivado -mode batch -source scripts/build_gt_profile0.tcl
# This script deliberately fails before XSA export if any build stage fails.

set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set project_file [file join $project_dir laser_tx.xpr]
set xsa_file [file join $project_dir laser_tx_board_top_gt_profile0.xsa]
set report_dir [file join $project_dir reports gt_profile0]
set impl_pre_tcl [file join $script_dir gt_profile0_impl_pre.tcl]

proc build_fail {message} {
    puts stderr "ERROR: $message"
    return -code error $message
}

proc require_complete_run {run_name} {
    set status [get_property STATUS [get_runs $run_name]]
    puts "INFO: $run_name status: $status"
    if {$status ne "synth_design Complete!" && $status ne "write_bitstream Complete!"} {
        build_fail "$run_name did not complete successfully: $status"
    }
}

if {![file exists $project_file]} { build_fail "Project not found: $project_file" }
if {![file exists $impl_pre_tcl]} { build_fail "Implementation pre-hook not found: $impl_pre_tcl" }
file mkdir $report_dir

# The local XCI must be generated first; this operation is idempotent.
source [file join $script_dir add_gt_wizard_profile0.tcl]

if {[llength [get_projects -quiet]] == 0} { open_project $project_file }
source [file join $script_dir bd_connect_laser_tx_core.tcl]

set system_bd [get_files -quiet */system.bd]
if {[llength $system_bd] != 1} { build_fail "Expected exactly one system.bd" }
reset_target all $system_bd
generate_target all $system_bd
make_wrapper -files $system_bd -top
update_compile_order -fileset sources_1

if {[llength [get_runs -quiet gtwizard_0_synth_1]] != 1} {
    build_fail "gtwizard_0_synth_1 run was not found after GT IP generation."
}
reset_run gtwizard_0_synth_1
launch_runs gtwizard_0_synth_1 -jobs 2
wait_on_run gtwizard_0_synth_1
require_complete_run gtwizard_0_synth_1

reset_run synth_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
require_complete_run synth_1

reset_run impl_1
set_property STEPS.OPT_DESIGN.TCL.PRE $impl_pre_tcl [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
require_complete_run impl_1

open_run impl_1
report_clocks -file [file join $report_dir clocks.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_cdc -file [file join $report_dir cdc.rpt]
report_bus_skew -warn_on_violation -file [file join $report_dir bus_skew.rpt]
write_hw_platform -fixed -include_bit -force -file $xsa_file
puts "INFO: GT Profile 0 bitstream and XSA completed: $xsa_file"
close_project

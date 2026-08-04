set repo_root [file normalize [file join [file dirname [info script]] ..]]
set dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_postroute_physopt.dcp]
if {![file exists $dcp]} { set dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_routed.dcp] }
set out [file join $repo_root reports gtwizard_adapter_validation]
file mkdir $out
open_checkpoint $dcp
report_timing_summary -max_paths 20 -report_unconstrained -file [file join $out timing_summary_full.rpt]
report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_drc -file [file join $out drc.rpt]
report_route_status -file [file join $out route_status.rpt]
close_design

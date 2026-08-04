set repo_root [file normalize [file join [file dirname [info script]] ..]]
set routed_dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_routed.dcp]
set out_dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_postroute_physopt.dcp]
if {![file exists $routed_dcp]} { error "Missing routed checkpoint: $routed_dcp" }
open_checkpoint $routed_dcp
phys_opt_design
write_checkpoint -force $out_dcp
report_timing_summary -max_paths 20 -report_unconstrained -file [file join $repo_root reports gtwizard_adapter_validation postroute_physopt_timing_summary.rpt]
report_drc -file [file join $repo_root reports gtwizard_adapter_validation postroute_physopt_drc.rpt]
report_route_status -file [file join $repo_root reports gtwizard_adapter_validation postroute_physopt_route_status.rpt]
close_design

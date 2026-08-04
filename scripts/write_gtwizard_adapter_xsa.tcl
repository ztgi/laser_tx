set repo_root [file normalize [file join [file dirname [info script]] ..]]
set dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_postroute_physopt.dcp]
if {![file exists $dcp]} { set dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_routed.dcp] }
set out [file join $repo_root reports gtwizard_adapter_validation artifacts]
file mkdir $out
open_checkpoint $dcp
write_hw_platform -fixed -include_bit -force -file [file join $out laser_tx_board_top_gtwizard_adapter.xsa]
close_design

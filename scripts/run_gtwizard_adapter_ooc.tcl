set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set run_name system_laser_tx_core_0_0_synth_1
set run [get_runs $run_name]
if {[llength $run] != 1} { error "Missing OOC run $run_name" }
reset_run $run
launch_runs $run -jobs 4
wait_on_run $run
set status [get_property STATUS $run]
puts "GTWIZARD_ADAPTER_OOC_STATUS=$status"
if {![string match *Complete* $status]} { error "OOC synthesis did not complete" }
close_project

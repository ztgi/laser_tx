set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set run [get_runs synth_1]
reset_run $run
launch_runs $run -jobs 4
wait_on_run $run
set status [get_property STATUS $run]
puts "GTWIZARD_ADAPTER_TOP_SYNTH_STATUS=$status"
if {![string match *Complete* $status]} { error "Top synthesis did not complete" }
close_project

set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set run [get_runs impl_1]
reset_run $run
launch_runs $run -to_step route_design -jobs 4
wait_on_run $run
set status [get_property STATUS $run]
puts "GTWIZARD_ADAPTER_ROUTE_STATUS=$status"
if {![string match *Complete* $status]} { error "Route did not complete" }
close_project

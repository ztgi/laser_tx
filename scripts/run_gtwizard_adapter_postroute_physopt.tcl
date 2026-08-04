set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set run [get_runs impl_1]
launch_runs $run -to_step phys_opt_design -jobs 4
wait_on_run $run
set status [get_property STATUS $run]
puts "GTWIZARD_ADAPTER_POSTROUTE_PHYSOPT_STATUS=$status"
close_project

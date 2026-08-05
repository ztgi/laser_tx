set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
foreach r [get_runs *] {
    puts "RUN=[get_property NAME $r] STATUS=[get_property STATUS $r] PROGRESS=[get_property PROGRESS $r]"
}
close_project

set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set srcset [get_filesets sources_1]
foreach f [get_files -of_objects $srcset -quiet *gtwizard_0*] {
    puts "FILE=[file normalize $f]"
    foreach p {IS_ENABLED USER_DISABLED AUTO_DISABLED USED_IN PROCESSING_ORDER FILE_TYPE PARENT_COMPOSITE_FILE} {
        if {[catch {set v [get_property $p $f]}]} {set v "<unavailable>"}
        puts "  $p=$v"
    }
}
close_project

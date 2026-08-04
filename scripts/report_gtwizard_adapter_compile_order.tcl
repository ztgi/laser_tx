set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set srcset [get_filesets sources_1]
update_compile_order -fileset $srcset
set active_gt {}
set imported_active {}
foreach f [get_files -of_objects $srcset -quiet *gtwizard_0*] {
    if {[get_property IS_ENABLED $f]} {
        lappend active_gt [file normalize $f]
        if {[string match *imports*sources_1* $f]} { lappend imported_active [file normalize $f] }
    }
}
puts "ACTIVE_GT_FILES=[llength $active_gt]"
foreach f $active_gt { puts "ACTIVE_GT=$f" }
puts "IMPORTED_ACTIVE=[llength $imported_active]"
if {[llength $imported_active] != 0} { error "Imported GT HDL remains active" }
set adapter [get_files -of_objects $srcset -quiet *gtwizard_0_adapter.v]
if {[llength $adapter] != 1} { error "Adapter is not in sources_1" }
puts "ADAPTER_COMPILE_ORDER_PASS"
close_project

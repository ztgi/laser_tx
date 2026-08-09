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

set synthesis_order [get_files -compile_order sources -used_in synthesis -of_objects $srcset]
set ordered_gt [lsearch -all -inline -glob $synthesis_order *gtwizard_0*]
puts "SYNTHESIS_COMPILE_ORDER_GT=[llength $ordered_gt]"
foreach f $ordered_gt { puts "ORDERED_GT=[file normalize $f]" }
set generated_lower [lsearch -all -inline -glob $ordered_gt *gtwizard_0_gt.v]
puts "GENERATED_LOWER_IN_NATIVE_ORDER=[llength $generated_lower]"
puts "SYNTH_PRE_HOOK=[get_property STEPS.SYNTH_DESIGN.TCL.PRE [get_runs synth_1]]"
set adapter [get_files -of_objects $srcset -quiet *gtwizard_0_adapter.v]
if {[llength $adapter] != 1} { error "Adapter is not in sources_1" }
puts "ADAPTER_COMPILE_ORDER_PASS"
close_project

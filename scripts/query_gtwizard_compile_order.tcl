set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
open_project $project_file
set srcset [get_filesets sources_1]
puts "SOURCE_MGMT=[get_property source_mgmt_mode [current_project]]"
update_compile_order -fileset $srcset
set xci [get_files -of_objects $srcset -quiet *gtwizard_0.xci]
puts "--- xci properties ---"
if {[llength $xci]} {
    foreach p [list_property $xci] {
        if {[string match *DISABL* $p] || [string match *SYNTH* $p] || [string match *GENERAT* $p] || [string match *USED* $p] || [string match *COMPOS* $p]} {
            puts "XCI_PROP=$p=[get_property $p $xci]"
        }
    }
}
puts "--- compile order all ---"
foreach f [get_files -compile_order sources -used_in synthesis -of_objects $srcset] {
    if {[string match *gtwizard_0* $f]} {
        puts "ORDER=[file normalize $f]"
    }
}
puts "--- all generated gt parent files ---"
foreach f [get_files -of_objects $srcset -quiet *laser_tx.gen*sources_1*ip*gtwizard_0*] {
    set parent ""
    catch {set parent [get_property PARENT_COMPOSITE_FILE $f]}
    set used ""
    catch {set used [get_property USED_IN $f]}
    puts "GEN=[file normalize $f] PARENT=[file normalize $parent] USED_IN=$used"
}
close_project

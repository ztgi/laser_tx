# Read-only audit of DCP file objects implicated by Project 1-840.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set out [file join $root reports ad9528_gt_rate_planner artifact_build]
file mkdir $out

open_project [file join $root laser_tx.xpr]
set fp [open [file join $out project_dcp_file_objects.txt] w]
puts $fp "project=[current_project]"
puts $fp "source_mgmt_mode=[get_property SOURCE_MGMT_MODE [current_project]]"
puts $fp "top=[get_property TOP [get_filesets sources_1]]"

set bd_files [get_files -quiet -all *.bd]
foreach bd $bd_files {
    puts $fp "BD=$bd"
    foreach prop {FILESET_NAME USED_IN USED_IN_SYNTHESIS USED_IN_IMPLEMENTATION IS_GENERATED IS_AUTO_DISABLED PARENT_COMPOSITE_FILE} {
        if {![catch {set value [get_property $prop $bd]}]} {
            puts $fp "  $prop=$value"
        }
    }
}

set xci_files [lsort -unique [get_files -quiet -all *.xci]]
puts $fp "XCI_COUNT=[llength $xci_files]"
foreach xci $xci_files {
    if {[string first "/bd/system/ip/" [string map {\\ /} $xci]] < 0} {
        continue
    }
    puts $fp "XCI=$xci"
    foreach prop {FILESET_NAME USED_IN USED_IN_SYNTHESIS USED_IN_IMPLEMENTATION IS_GENERATED IS_AUTO_DISABLED IS_ENABLED GENERATE_SYNTH_CHECKPOINT SYNTH_CHECKPOINT_MODE} {
        if {![catch {set value [get_property $prop $xci]}]} {
            puts $fp "  $prop=$value"
        }
    }
}

set dcps [lsort -unique [get_files -quiet -all *.dcp]]
puts $fp "DCP_COUNT=[llength $dcps]"
foreach dcp $dcps {
    puts $fp "DCP=$dcp"
    foreach prop {FILESET_NAME USED_IN USED_IN_SYNTHESIS USED_IN_IMPLEMENTATION USED_IN_SIMULATION IS_GENERATED IS_AUTO_DISABLED IS_ENABLED FILE_TYPE PARENT_COMPOSITE_FILE GENERATE_SYNTH_CHECKPOINT} {
        if {![catch {set value [get_property $prop $dcp]}]} {
            puts $fp "  $prop=$value"
        }
    }
}
close $fp

set fp [open [file join $out project_runs.txt] w]
foreach run [lsort [get_runs -quiet]] {
    puts $fp "RUN=$run STATUS=[get_property STATUS $run] SRCSET=[get_property SRCSET $run] PARENT=[get_property PARENT $run]"
}
close $fp
close_project
puts "PROJECT_1_840_SOURCE_AUDIT_COMPLETE"

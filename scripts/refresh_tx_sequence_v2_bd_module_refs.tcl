set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ".."]]
set project_path [file join $repo_dir "laser_tx.xpr"]
set bd_path [file join $repo_dir "laser_tx.srcs" "sources_1" "bd" "system" "system.bd"]
set report_dir [file join $repo_dir "reports" "tx_sequence_v2_refresh"]
file mkdir $report_dir

proc require_file {path label} {
    if {![file exists $path]} {
        error "$label does not exist: $path"
    }
}

require_file $project_path "Vivado project"
require_file $bd_path "Block design"

open_project $project_path

set eom_sources [list \
    [file join $repo_dir "laser_tx.srcs" "sources_1" "new" "laser_tx_core" "tx_eom_geometry_precompute.v"] \
    [file join $repo_dir "laser_tx.srcs" "sources_1" "new" "laser_tx_core" "tx_eom_window_generator.v"]]

foreach source_path $eom_sources {
    require_file $source_path "TX sequence V2 RTL source"
    if {[llength [get_files -quiet -of_objects [get_filesets sources_1] $source_path]] == 0} {
        add_files -fileset sources_1 -norecurse $source_path
        puts "TX_SEQUENCE_V2_REFRESH: added source $source_path"
    } else {
        puts "TX_SEQUENCE_V2_REFRESH: source already present $source_path"
    }
}

open_bd_design $bd_path

set refresh_ips [get_ips -quiet system_laser_tx_core_0_0]
if {[llength $refresh_ips] != 1} {
    error "Expected exactly one laser_tx_core module-reference IP; found: $refresh_ips"
}
puts "TX_SEQUENCE_V2_REFRESH: refreshing module-reference IP $refresh_ips"
update_module_reference -verbose $refresh_ips
validate_bd_design
save_bd_design

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set compile_order_path [file join $report_dir "sources_1_compile_order.txt"]
set compile_fp [open $compile_order_path "w"]
set compile_order_normalized {}
foreach source_file [get_files -compile_order sources -used_in synthesis -of_objects [get_filesets sources_1]] {
    set normalized_source [file normalize $source_file]
    lappend compile_order_normalized $normalized_source
    puts $compile_fp $normalized_source
}
close $compile_fp

foreach source_path $eom_sources {
    if {[lsearch -exact $compile_order_normalized [file normalize $source_path]] < 0} {
        error "Required EOM source is missing from sources_1 compile order: $source_path"
    }
}

set wrapper_files [make_wrapper -files [get_files $bd_path] -top -import -force]
puts "TX_SEQUENCE_V2_REFRESH: wrapper_files=$wrapper_files"

close_project
puts "TX_SEQUENCE_V2_REFRESH_PASS"

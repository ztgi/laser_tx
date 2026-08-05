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

set tx_sequence_sources [list \
    [file join $repo_dir "laser_tx.srcs" "sources_1" "new" "laser_tx_core" "tx_eom_geometry_precompute.v"] \
    [file join $repo_dir "laser_tx.srcs" "sources_1" "new" "laser_tx_core" "tx_eom_window_generator.v"] \
    [file join $repo_dir "laser_tx.srcs" "sources_1" "new" "laser_tx_core" "tx_scope_debug_outputs.v"]]

foreach source_path $tx_sequence_sources {
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

# Keep the descriptor window at 4 KiB (1024 x 32) after BD propagation.
set descriptor_ip [get_ips -quiet system_blk_mem_dyn_desc_0]
if {[llength $descriptor_ip] != 1} {
    error "Expected exactly one descriptor BRAM IP; found: $descriptor_ip"
}
set_property CONFIG.Write_Depth_A {1024} $descriptor_ip
if {[get_property CONFIG.Write_Depth_A $descriptor_ip] ne "1024"} {
    error "Descriptor BRAM depth did not resolve to 1024 after module refresh"
}

set core_cells [get_bd_cells -quiet -hier -filter {VLNV =~ "*:laser_tx_core:*"}]
if {[llength $core_cells] != 1} {
    error "Expected exactly one laser_tx_core BD cell; found: $core_cells"
}
set core_cell [lindex $core_cells 0]
foreach port_name {gt_sequence_sync_out txusrclk2_monitor_out} {
    set core_pin [get_bd_pins -quiet $core_cell/$port_name]
    if {[llength $core_pin] != 1} {
        error "Expected module-reference output pin $port_name; found: $core_pin"
    }
    set external_port [get_bd_ports -quiet $port_name]
    if {[llength $external_port] == 0} {
        set external_port [create_bd_port -dir O $port_name]
        puts "TX_SEQUENCE_V2_REFRESH: created output port $port_name"
    }
    if {[llength [get_bd_nets -quiet -of_objects $core_pin]] == 0} {
        connect_bd_net $core_pin $external_port
        puts "TX_SEQUENCE_V2_REFRESH: connected $core_pin to $external_port"
    }
}

validate_bd_design
save_bd_design
generate_target all [get_files $bd_path]

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

foreach source_path $tx_sequence_sources {
    if {[lsearch -exact $compile_order_normalized [file normalize $source_path]] < 0} {
        error "Required EOM source is missing from sources_1 compile order: $source_path"
    }
}

set wrapper_files [make_wrapper -files [get_files $bd_path] -top -import -force]
puts "TX_SEQUENCE_V2_REFRESH: wrapper_files=$wrapper_files"

close_project
puts "TX_SEQUENCE_V2_REFRESH_PASS"

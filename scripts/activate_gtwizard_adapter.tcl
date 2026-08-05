set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
set repo_root [file dirname $project_file]
open_project $project_file

set srcset [get_filesets sources_1]
# Keep the standard automatic source manager for BD/module-reference IP.  The
# top-synthesis pre-hook explicitly loads the XCI-owned lower GT children when
# the maintained adapter binds them; no generated HDL is independently added.
set_property source_mgmt_mode All [current_project]
set xci [get_files -of_objects $srcset -quiet [file join $repo_root laser_tx.srcs sources_1 ip gtwizard_0 gtwizard_0.xci]]
if {[llength $xci] != 1} {
    error "Local gtwizard_0.xci was not found in sources_1"
}
set_property IS_ENABLED true $xci
generate_target all $xci

# Remove only the historical imported GT HDL and generated wrapper layers that
# are replaced by the maintained adapter.  The files remain on disk for audit.
set imported_gt [get_files -of_objects $srcset -quiet *imports*sources_1*ip*gtwizard_0*.v]
if {[llength $imported_gt] > 0} {
    remove_files -fileset $srcset $imported_gt
}

# The XCI remains the source of all generated products.  No generated HDL is
# registered as an independent source; the composite XCI owns its child files.
# The maintained adapter binds the lower GT and generated startup helpers
# through that parent/child relationship.
set generated_wrappers {}
foreach pat {\
    *laser_tx.gen*sources_1*ip*gtwizard_0*gtwizard_0.v \
    *laser_tx.gen*sources_1*ip*gtwizard_0*gtwizard_0_init.v \
    *laser_tx.gen*sources_1*ip*gtwizard_0*gtwizard_0_multi_gt.v} {
    foreach f [get_files -of_objects $srcset -quiet $pat] { lappend generated_wrappers $f }
}
if {[llength $generated_wrappers] > 0} {
    set_property IS_ENABLED true $generated_wrappers
}

set gen_dir [file join $repo_root laser_tx.gen sources_1 ip gtwizard_0]
# Refresh/legacy activation can leave a second, standalone registration for a
# generated Verilog file alongside the XCI-owned composite child.  Remove only
# that project-file registration; never delete the generated file on disk.
foreach existing [get_files -of_objects $srcset -quiet *laser_tx.gen*sources_1*ip*gtwizard_0*.v] {
    if {[catch {set parent [get_property PARENT_COMPOSITE_FILE $existing]}]} { set parent "" }
    if {$parent eq ""} {
        remove_files -fileset $srcset $existing
    }
}
set required_generated [list \
    [file join $gen_dir gtwizard_0_gt.v] \
    [file join $gen_dir gtwizard_0_cpll_railing.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_rx_startup_fsm.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_sync_block.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_tx_startup_fsm.v]]
foreach f $required_generated {
    if {![file exists $f]} { error "Missing local XCI generated source: $f" }
    set managed 0
    foreach existing [get_files -of_objects $srcset -quiet $f] {
        if {[catch {set parent [get_property PARENT_COMPOSITE_FILE $existing]}]} { set parent "" }
        if {[file normalize $parent] eq [file normalize $xci]} { set managed 1 }
    }
    if {!$managed} {
        error "Generated GT source is not managed by local gtwizard_0.xci: $f"
    }
}

set adapter [file join $repo_root laser_tx.srcs sources_1 new gtwizard_0_adapter.v]
if {![file exists $adapter]} { error "Missing maintained adapter: $adapter" }
if {[llength [get_files -of_objects $srcset -quiet $adapter]] == 0} {
    add_files -fileset $srcset -norecurse $adapter
}

update_compile_order -fileset $srcset
set_property top laser_tx_board_top $srcset
set_property top_auto_set 0 $srcset
puts "GTWIZARD_ADAPTER_PROJECT_ACTIVATED"
puts "LOCAL_XCI=[file normalize $xci]"
puts "ADAPTER=[file normalize $adapter]"
puts "COMPILE_ORDER_GT_FILES="
foreach f [get_files -of_objects $srcset -quiet *gtwizard_0*] { puts "  [file normalize $f]" }
close_project

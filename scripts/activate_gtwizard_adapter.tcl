set project_file [file normalize [file join [file dirname [file normalize [info script]]] .. laser_tx.xpr]]
set repo_root [file dirname $project_file]
open_project $project_file

set srcset [get_filesets sources_1]
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

# The XCI remains the source of generated products, but its generated top/init/
# multi_gt wrappers are not compiled: the adapter binds the lower GT and the
# generated startup helpers directly.
set generated_wrappers {}
foreach pat {\
    *laser_tx.gen*sources_1*ip*gtwizard_0*gtwizard_0.v \
    *laser_tx.gen*sources_1*ip*gtwizard_0*gtwizard_0_init.v \
    *laser_tx.gen*sources_1*ip*gtwizard_0*gtwizard_0_multi_gt.v} {
    foreach f [get_files -of_objects $srcset -quiet $pat] { lappend generated_wrappers $f }
}
if {[llength $generated_wrappers] > 0} {
    # Keep the XCI composite's generated wrapper layers enabled so Vivado does
    # not auto-disable the IP parent.  The maintained adapter instantiates the
    # lower GT directly; these generated wrappers remain uninstantiated audit
    # sources and are pruned from the production netlist.
    set_property IS_ENABLED true $generated_wrappers
}

set gen_dir [file join $repo_root laser_tx.gen sources_1 ip gtwizard_0]
set required_generated [list \
    [file join $gen_dir gtwizard_0_gt.v] \
    [file join $gen_dir gtwizard_0_cpll_railing.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_rx_startup_fsm.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_sync_block.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_tx_startup_fsm.v]]
foreach f $required_generated {
    if {![file exists $f]} { error "Missing local XCI generated source: $f" }
    set standalone 0
    foreach existing [get_files -of_objects $srcset -quiet $f] {
        if {[catch {set parent [get_property PARENT_COMPOSITE_FILE $existing]}]} { set parent "" }
        if {$parent eq ""} { set standalone 1 }
    }
    if {!$standalone} {
        # Keep the XCI as the authoritative generator, while registering its
        # generated HDL as an explicit source so the adapter can bind the
        # lower module even when the unused wizard top is auto-disabled.
        add_files -fileset $srcset -norecurse $f
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

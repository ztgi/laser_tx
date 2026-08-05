# Top-level synthesis pre-hook for the maintained GT adapter.
#
# gtwizard_0.xci remains the sole Vivado project registration and owns these
# generated children.  Because the production adapter binds the lower
# gtwizard_0_GT wrapper instead of the Wizard example top, Vivado's automatic
# source manager can omit orphan composite children from the in-memory run
# script.  Load the already-generated XCI children here; they are regenerated
# from the checked-in XCI before this hook runs and are never registered as
# independent project sources.
set hook_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $hook_dir ..]]
set gen_dir [file join $root laser_tx.gen sources_1 ip gtwizard_0]
set gt_sources [list \
    [file join $gen_dir gtwizard_0_gt.v] \
    [file join $gen_dir gtwizard_0_cpll_railing.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_rx_startup_fsm.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_sync_block.v] \
    [file join $gen_dir gtwizard_0 example_design gtwizard_0_tx_startup_fsm.v]]
foreach source $gt_sources {
    if {![file exists $source]} {
        error "XCI-managed GT generated source is missing before top synthesis: $source"
    }
    read_verilog -library xil_defaultlib $source
}
puts "GTWIZARD_0_SYNTH_PRE_LOADED=[llength $gt_sources]"

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_postroute_physopt.dcp]
if {![file exists $dcp]} { set dcp [file join $repo_root laser_tx.runs impl_1 laser_tx_board_top_routed.dcp] }
set out [file join $repo_root reports gtwizard_adapter_validation]
file mkdir $out
open_checkpoint $dcp

set snapshot [open [file join $out production_baseline_snapshot.txt] w]
proc snapshot_emit {fp key value} {
    puts $fp "$key=$value"
    puts "$key=$value"
}

set gt_channels [get_cells -quiet -hier -filter {REF_NAME == GTXE2_CHANNEL}]
set gt_commons [get_cells -quiet -hier -filter {REF_NAME == GTXE2_COMMON}]
set black_boxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
set runtime_clocks [get_clocks -quiet [list GT_TXUSRCLK_RUNTIME* GT_TXUSRCLK2_RUNTIME* GT_EOM_CLK_RUNTIME*]]
set cpll_sel_pin [get_pins -quiet -hier *gtxe2_i/CPLLREFCLKSEL]
set north_refclk_pin [get_pins -quiet -hier *gtxe2_i/GTNORTHREFCLK0]

snapshot_emit $snapshot "routed_dcp" [file normalize $dcp]
snapshot_emit $snapshot "gtxe2_channel_count" [llength $gt_channels]
snapshot_emit $snapshot "gtxe2_common_count" [llength $gt_commons]
snapshot_emit $snapshot "black_box_count" [llength $black_boxes]
snapshot_emit $snapshot "runtime_clock_count" [llength $runtime_clocks]
snapshot_emit $snapshot "cpllrefclksel_pin" $cpll_sel_pin
snapshot_emit $snapshot "cpllrefclksel_nets" [get_nets -quiet -segments -of_objects $cpll_sel_pin]
snapshot_emit $snapshot "gtnorthrefclk0_pin" $north_refclk_pin
snapshot_emit $snapshot "gtnorthrefclk0_nets" [get_nets -quiet -segments -of_objects $north_refclk_pin]

if {[llength $gt_channels] != 1} { error "Expected one GTXE2_CHANNEL, found [llength $gt_channels]" }
if {[llength $gt_commons] != 1} { error "Expected one GTXE2_COMMON, found [llength $gt_commons]" }
if {[llength $black_boxes] != 0} { error "Routed design contains black boxes: $black_boxes" }
if {[llength $runtime_clocks] != 15} { error "Expected 15 runtime clocks, found [llength $runtime_clocks]" }
if {[llength $cpll_sel_pin] != 3} { error "Expected three runtime CPLLREFCLKSEL primitive pins, found [llength $cpll_sel_pin]" }
if {[llength $north_refclk_pin] != 1} { error "GTNORTHREFCLK0 primitive pin is missing" }
if {![llength [get_nets -quiet -segments -of_objects $north_refclk_pin]]} {
    error "GTNORTHREFCLK0 primitive pin is not connected"
}

close $snapshot
report_timing_summary -max_paths 20 -report_unconstrained -file [file join $out timing_summary_full.rpt]
report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_methodology -file [file join $out methodology.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_drc -file [file join $out drc.rpt]
report_route_status -file [file join $out route_status.rpt]
close_design

# Direct Tcl build for the minimal 500M <-> 1000M dynamic-rate image.
#
# This bypasses Vivado project run-script file filtering and uses the current
# project fileset directly.  It is intended for this dynamic-rate bring-up only.

set report_dir [file normalize ./reports/dynamic_rate_500m_1000m/artifacts]
file mkdir $report_dir

open_project ./laser_tx.xpr
set_property top laser_tx_board_top [current_fileset]
update_compile_order -fileset sources_1

synth_design -top laser_tx_board_top -part xc7z100ffg900-2

set gt_cell [get_cells -quiet u_laser_gt_tx_profile0/u_gtwizard_0]
if {[llength $gt_cell] == 0} {
    error "GT Wizard cell u_laser_gt_tx_profile0/u_gtwizard_0 not found after synthesis"
}
if {[get_property IS_BLACKBOX $gt_cell]} {
    error "GT Wizard remained a blackbox. Scheme A requires project/IP generated-HDL linkage without manual checkpoint cell binding."
}

set dbg_clk_net [get_nets -hier -quiet gt_ctrl_clk]
if {[llength $dbg_clk_net] == 0} {
    set dbg_clk_net [get_nets -hier -quiet *gt_ctrl_clk*]
}
if {[llength $dbg_clk_net] == 0} {
    error "Cannot find gt_ctrl_clk net for dbg_hub/clk"
}
set dbg_clk_net [lindex $dbg_clk_net 0]
if {[llength [get_debug_cores -quiet dbg_hub]] != 0} {
    catch {disconnect_debug_port dbg_hub/clk}
    connect_debug_port dbg_hub/clk $dbg_clk_net
    set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
    set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
    set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
    puts "INFO: dbg_hub/clk forced to $dbg_clk_net"
}
write_checkpoint -force [file join $report_dir post_synth_dynamic_500m_1000m.dcp]
report_utilization -file [file join $report_dir utilization_post_synth_dynamic_500m_1000m.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $report_dir routed_dynamic_500m_1000m.dcp]

report_timing_summary -file [file join $report_dir timing_summary_dynamic_500m_1000m.rpt]
report_clocks -file [file join $report_dir clocks_dynamic_500m_1000m.rpt]
report_utilization -file [file join $report_dir utilization_dynamic_500m_1000m.rpt]
report_debug_core -file [file join $report_dir debug_cores_dynamic_500m_1000m.rpt]

set dst_bit [file join $report_dir laser_tx_board_top_dynamic_500m_1000m.bit]
set dst_ltx [file join $report_dir laser_tx_board_top_dynamic_500m_1000m.ltx]

write_bitstream -force $dst_bit
write_debug_probes -force $dst_ltx

puts "DYNAMIC_BUILD_BIT=$dst_bit"
puts "DYNAMIC_BUILD_LTX=$dst_ltx"
puts "DYNAMIC_BUILD_TIMING=[file join $report_dir timing_summary_dynamic_500m_1000m.rpt]"

close_project

# Build the minimal 500M <-> 1000M dynamic-rate hardware image.
#
# This script assumes scripts/bd_expose_rate_control_signals.tcl has already
# updated the BD wrapper ports.  It does not export XSA by default because the
# AXI address map and software-visible peripheral instances are unchanged.

set report_dir [file normalize ./reports/dynamic_rate_500m_1000m]
file mkdir $report_dir

open_project ./laser_tx.xpr
set_property top laser_tx_board_top [current_fileset]

set rate_switch_file [file normalize ./laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v]
if {[llength [get_files -quiet $rate_switch_file]] == 0} {
    add_files -norecurse $rate_switch_file
}

# The GT Wizard XCI is kept as a project IP, but this project has historically
# used generated HDL for top-level integration.  Make the generated wrapper
# hierarchy explicit so synth_design can resolve gtwizard_0 after clean resets.
set gt_generated_files [list \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_multi_gt.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_init.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_cpll_railing.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_tx_startup_fsm.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_rx_startup_fsm.v] \
    [file normalize ./laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0/example_design/gtwizard_0_sync_block.v]]
foreach gt_file $gt_generated_files {
    if {[file exists $gt_file] && [llength [get_files -quiet $gt_file]] == 0} {
        add_files -norecurse $gt_file
    }
}

update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 did not finish"
}
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "synth_1 failed: [get_property STATUS [get_runs synth_1]]"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 did not finish"
}
if {![string match "*write_bitstream Complete!*" [get_property STATUS [get_runs impl_1]]]} {
    error "impl_1 failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_timing_summary -file [file join $report_dir timing_summary_dynamic_500m_1000m.rpt]
report_clocks -file [file join $report_dir clocks_dynamic_500m_1000m.rpt]
report_utilization -file [file join $report_dir utilization_dynamic_500m_1000m.rpt]
report_debug_core -file [file join $report_dir debug_cores_dynamic_500m_1000m.rpt]

set src_bit [file normalize ./laser_tx.runs/impl_1/laser_tx_board_top.bit]
set src_ltx [file normalize ./laser_tx.runs/impl_1/laser_tx_board_top.ltx]
set dst_bit [file join $report_dir laser_tx_board_top_dynamic_500m_1000m.bit]
set dst_ltx [file join $report_dir laser_tx_board_top_dynamic_500m_1000m.ltx]

if {[file exists $src_bit]} {
    file copy -force $src_bit $dst_bit
}
if {[file exists $src_ltx]} {
    file copy -force $src_ltx $dst_ltx
} else {
    write_debug_probes -force $dst_ltx
}

puts "DYNAMIC_BUILD_BIT=$dst_bit"
puts "DYNAMIC_BUILD_LTX=$dst_ltx"
puts "DYNAMIC_BUILD_TIMING=[file join $report_dir timing_summary_dynamic_500m_1000m.rpt]"

close_project

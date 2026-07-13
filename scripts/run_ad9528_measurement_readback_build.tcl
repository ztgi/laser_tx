# Clean build, reports and XSA export for AD9528 OUT0 software readback.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set report_dir [file join $project_dir reports ad9528_out0_software_readback]
file mkdir $report_dir

source [file join $script_dir clean_rebuild_bit_ltx.tcl]

report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]
report_clock_networks -file [file join $report_dir clock_networks.rpt]
report_io -file [file join $report_dir io.rpt]
report_debug_core -full_path -file [file join $report_dir debug_cores.rpt]

set measure_gpio [get_cells -hier -quiet *axi_gpio_ad9528_measure*]
if {![llength $measure_gpio]} {
    error "Implemented axi_gpio_ad9528_measure was not found."
}
set xsa_file [file join $report_dir laser_tx_board_top_ad9528_measure.xsa]
write_hw_platform -fixed -include_bit -force -file $xsa_file
puts "INFO: AD9528 software-readback XSA: $xsa_file"
# Clean main-project build and evidence reports for the measurement-only path.
set script_dir [file dirname [file normalize [info script]]]
set project_dir [file dirname $script_dir]
set report_dir [file join $project_dir reports ad9528_out0_ila_measurement]
file mkdir $report_dir

source [file join $script_dir clean_rebuild_bit_ltx.tcl]

report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_clock_networks -file [file join $report_dir clock_networks.rpt]
report_io -file [file join $report_dir io.rpt]
report_debug_core -full_path -file [file join $report_dir debug_cores.rpt]

set fd [open [file join $report_dir measurement_path_check.txt] w]
puts $fd "IBUFDS_GTE2=[get_cells -hier -filter {REF_NAME == IBUFDS_GTE2 && NAME =~ *u_ad9528_out0_ibufds_gte2*}]"
puts $fd "ODIV2_BUFG=[get_cells -hier -filter {REF_NAME == BUFG && NAME =~ *u_ad9528_out0_odiv2_bufg*}]"
puts $fd "MEASURE_ILA=[get_debug_cores -quiet ila_ad9528_out0_measure]"
puts $fd "AD9528_PORTS=[get_ports -quiet ad9528_ref0_clk_*]"
puts $fd "BANK111_NORTHREFCLK_NETS=[get_nets -hier -quiet *GTNORTHREFCLK0*]"
close $fd

puts "INFO: AD9528 OUT0 measurement build reports: $report_dir"

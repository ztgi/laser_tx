# Isolated feasibility probe for a future non-destructive OUT0 frequency meter.
# This never opens/saves laser_tx.xpr and never generates a bitstream.
# It validates only AA8/AA7 -> IBUFDS_GTE2.ODIV2 -> BUFG -> retained counter.

set part xc7z100ffg900-2
create_project -in_memory -part $part
set report_dir [file normalize "reports/ad9528_runtime/isolated_out0_measurement_path"]
file mkdir $report_dir

set probe_top [file join $report_dir ad9528_out0_odiv2_probe.v]
set fh [open $probe_top w]
puts $fh {
module ad9528_out0_odiv2_probe (
    input wire ad9528_out0_p,
    input wire ad9528_out0_n
);
    wire out0_odiv2;
    wire out0_fabric_clk;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) reg [31:0] out0_edge_counter = 32'd0;
    (* KEEP = "TRUE", DONT_TOUCH = "TRUE" *) wire [31:0] out0_counter_observe = out0_edge_counter;

    // ODIV2 is the documented divided fabric-side output of IBUFDS_GTE2.
    // No GT channel/Common is instantiated and no normal fabric logic drives
    // a MGT reference-clock pin.
    (* DONT_TOUCH = "TRUE" *) IBUFDS_GTE2 u_out0_ibuf (
        .I(ad9528_out0_p), .IB(ad9528_out0_n), .CEB(1'b0),
        .O(), .ODIV2(out0_odiv2)
    );
    (* DONT_TOUCH = "TRUE" *) BUFG u_out0_odiv2_bufg (
        .I(out0_odiv2), .O(out0_fabric_clk)
    );
    always @(posedge out0_fabric_clk)
        out0_edge_counter <= out0_edge_counter + 1'b1;
endmodule
}
close $fh

set probe_xdc [file join $report_dir ad9528_out0_odiv2_probe.xdc]
set fh [open $probe_xdc w]
puts $fh {
set_property PACKAGE_PIN AA8 [get_ports ad9528_out0_p]
set_property PACKAGE_PIN AA7 [get_ports ad9528_out0_n]
# 125 MHz is a route-only placeholder, not a measured OUT0 claim.
create_clock -name AD9528_OUT0_ODIV2_ROUTE_PROBE -period 8.000 [get_ports ad9528_out0_p]
}
close $fh

read_verilog $probe_top
read_xdc -quiet -unmanaged $probe_xdc
synth_design -top ad9528_out0_odiv2_probe -part $part
puts "IBUFDS_GTE2_CELLS=[get_cells -hier -filter {REF_NAME == IBUFDS_GTE2}]"
puts "BUFG_CELLS=[get_cells -hier -filter {REF_NAME == BUFG}]"
puts "COUNTER_CELLS=[get_cells -hier *out0_edge_counter*]"
opt_design
place_design
route_design
report_drc -file [file join $report_dir drc.rpt]
report_clock_networks -file [file join $report_dir clock_networks.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
puts "ISOLATED_OUT0_ODIV2_PATH_DONE"
close_project

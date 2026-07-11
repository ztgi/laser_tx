# Read-only placement probe for the isolated Bank110 -> Bank111 GT refclk task.
# It never opens, saves, or modifies laser_tx.xpr.

set part xc7z100ffg900-2
create_project -in_memory -part $part

# get_package_pins/get_sites require an open design.  The probe generates a
# one-COMMON QPLL topology under reports/, never any main-project source file.
# It deliberately instantiates no Bank110 GTXE2_CHANNEL: AA8/AA7 only feed an
# IBUFDS_GTE2, then the dedicated northbound reference-clock network.
set report_dir [file normalize "reports/ad9528_gt_refclk_candidates/isolated_route_probe"]
file mkdir $report_dir
set probe_top [file join $report_dir bank110_to_bank111_qpll_probe.v]
set fh [open $probe_top w]
puts $fh {
`timescale 1ns / 1ps
module bank110_to_bank111_qpll_probe (
    input  wire ad9528_out0_p,
    input  wire ad9528_out0_n
);
    wire bank110_refclk;
    wire bank110_refclk_odiv2_unused;
    wire qplloutclk_unused;
    wire qplloutrefclk_unused;
    wire [15:0] drpdo_unused;
    wire drprdy_unused;

    // This buffer is placed by the AA8/AA7 dedicated MGTREFCLK0 pins in
    // Bank110.  No data-channel primitive exists in Bank110.
    (* DONT_TOUCH = "TRUE" *) IBUFDS_GTE2 u_bank110_refclk_ibuf (
        .I(ad9528_out0_p),
        .IB(ad9528_out0_n),
        .CEB(1'b0),
        .O(bank110_refclk),
        .ODIV2(bank110_refclk_odiv2_unused)
    );

    // Bank110 is physically below Bank111 on this device.  UG476 defines
    // GTNORTHREFCLK0 as the north-bound clock arriving from the Quad below;
    // select value 3'b011 is the GTNORTHREFCLK0 input.
    (* DONT_TOUCH = "TRUE" *) GTXE2_COMMON #(
        .SIM_RESET_SPEEDUP        ("FALSE"),
        .SIM_QPLLREFCLK_SEL       (3'b011),
        .SIM_VERSION              ("4.0"),
        .BIAS_CFG                 (64'h0000040000001000),
        .COMMON_CFG               (32'h00000000),
        .QPLL_CFG                 (27'h0680181),
        .QPLL_CLKOUT_CFG          (4'b0000),
        .QPLL_COARSE_FREQ_OVRD    (6'b010000),
        .QPLL_COARSE_FREQ_OVRD_EN (1'b0),
        .QPLL_CP                  (10'b0000011111),
        .QPLL_CP_MONITOR_EN       (1'b0),
        .QPLL_DMONITOR_SEL        (1'b0),
        .QPLL_FBDIV               (10'b0100100000),
        .QPLL_FBDIV_MONITOR_EN    (1'b0),
        .QPLL_FBDIV_RATIO         (1'b1),
        .QPLL_INIT_CFG            (24'h000006),
        .QPLL_LOCK_CFG            (16'h21E8),
        .QPLL_LPF                 (4'b1111),
        .QPLL_REFCLK_DIV          (1)
    ) u_bank111_common (
        .DRPADDR                  (8'd0),
        .DRPCLK                   (bank110_refclk),
        .DRPDI                    (16'd0),
        .DRPDO                    (drpdo_unused),
        .DRPEN                    (1'b0),
        .DRPRDY                   (drprdy_unused),
        .DRPWE                    (1'b0),
        .GTGREFCLK                (1'b0),
        .GTNORTHREFCLK0           (bank110_refclk),
        .GTNORTHREFCLK1           (1'b0),
        .GTREFCLK0                (1'b0),
        .GTREFCLK1                (1'b0),
        .GTSOUTHREFCLK0           (1'b0),
        .GTSOUTHREFCLK1           (1'b0),
        .QPLLDMONITOR             (),
        .QPLLOUTCLK               (qplloutclk_unused),
        .QPLLOUTREFCLK            (qplloutrefclk_unused),
        .REFCLKOUTMONITOR         (),
        .QPLLFBCLKLOST            (),
        .QPLLLOCK                 (),
        .QPLLLOCKDETCLK           (1'b0),
        .QPLLLOCKEN               (1'b1),
        .QPLLOUTRESET             (1'b0),
        .QPLLPD                   (1'b0),
        .QPLLREFCLKLOST           (),
        .QPLLREFCLKSEL            (3'b011),
        .QPLLRESET                (1'b0),
        .QPLLRSVD1                (16'd0),
        .QPLLRSVD2                (5'b11111),
        .BGBYPASSB                (1'b1),
        .BGMONITORENB             (1'b1),
        .BGPDB                    (1'b1),
        .BGRCALOVRD               (5'b11111),
        .PMARSVD                  (8'd0),
        .RCALENB                  (1'b1)
    );

    // A Bank111 channel consumes the QPLL outputs.  It is held in reset and
    // has no package data pins in this routing-only test; Bank110 still has no
    // GTXE2_CHANNEL instance.  Keeping the consumer in the intended Bank111
    // Quad removes the partial-COMMON warning and validates the full QPLL
    // reference-clock path without creating a functional data channel.
    (* DONT_TOUCH = "TRUE" *) GTXE2_CHANNEL u_bank111_channel (
        .CPLLREFCLKSEL             (3'b011),
        .GTGREFCLK                  (1'b0),
        .GTNORTHREFCLK0             (bank110_refclk),
        .GTNORTHREFCLK1             (1'b0),
        .GTREFCLK0                  (1'b0),
        .GTREFCLK1                  (1'b0),
        .GTSOUTHREFCLK0             (1'b0),
        .GTSOUTHREFCLK1             (1'b0),
        .QPLLCLK                    (qplloutclk_unused),
        .QPLLREFCLK                 (qplloutrefclk_unused),
        .TXSYSCLKSEL                (2'b11),
        .TXOUTCLKSEL                (3'b010),
        .GTTXRESET                  (1'b1),
        .TXUSERRDY                  (1'b0),
        .TXUSRCLK                   (1'b0),
        .TXUSRCLK2                  (1'b0),
        .TXDATA                     (64'd0)
    );
endmodule
}
close $fh

set probe_xdc [file join $report_dir bank110_to_bank111_qpll_probe.xdc]
set fh [open $probe_xdc w]
puts $fh {# Isolated test only: AD9528 OUT0 is wired to Bank110 MGTREFCLK0.
set_property PACKAGE_PIN AA8 [get_ports ad9528_out0_p]
set_property PACKAGE_PIN AA7 [get_ports ad9528_out0_n]
create_clock -name AD9528_OUT0_ROUTE_TEST -period 8.000 [get_ports ad9528_out0_p]

# Current SFP+ Bank111 Quad.
set_property LOC GTXE2_COMMON_X0Y2 [get_cells u_bank111_common]
set_property LOC GTXE2_CHANNEL_X0Y8 [get_cells u_bank111_channel]
}
close $fh

read_verilog $probe_top
read_xdc -quiet -unmanaged $probe_xdc
synth_design -top bank110_to_bank111_qpll_probe -part $part

puts "PART=$part"
foreach package_pin {AA8 AA7 AD10 AD9 U8 U7 W8 W7 AB2 AB1} {
    set pkg [get_package_pins $package_pin]
    set sites [get_sites -of_objects $pkg]
    puts [format "PACKAGE_PIN=%-4s SITES=%s" $package_pin $sites]
    foreach site $sites {
        puts [format "  SITE=%s TYPE=%s TILES=%s CLOCK_REGIONS=%s" \
            $site \
            [get_property SITE_TYPE $site] \
            [get_tiles -of_objects $site] \
            [get_clock_regions -of_objects $site]]
    }
}

puts "GTX_CHANNEL_SITES"
foreach site [lsort [get_sites -filter {SITE_TYPE == GTXE2_CHANNEL}]] {
    puts [format "  %s TILES=%s CLOCK_REGIONS=%s" \
        $site [get_tiles -of_objects $site] [get_clock_regions -of_objects $site]]
}

puts "GTX_COMMON_SITES"
foreach site [lsort [get_sites -filter {SITE_TYPE == GTXE2_COMMON}]] {
    puts [format "  %s TILES=%s CLOCK_REGIONS=%s" \
        $site [get_tiles -of_objects $site] [get_clock_regions -of_objects $site]]
}

puts "ISOLATED_ROUTE_IMPLEMENTATION_BEGIN"
opt_design
place_design
route_design
report_drc -file [file join $report_dir drc.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization.rpt]
report_clock_networks -file [file join $report_dir clock_networks.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
puts "ISOLATED_ROUTE_IMPLEMENTATION_DONE"

close_project

`timescale 1ns/1ps

// GT Profile 1 static 1000 Mb/s TX user-clock generator.
//
// This file is intentionally separate from laser_gt_usrclk_profile0.v so the
// verified 500 Mb/s Profile 0 clocking remains directly recoverable.
//
// Parameters come from the Vivado 7-series Transceiver Wizard example design
// generated for the isolated 1000M comparison profile:
//
//   TXOUTCLK 31.25 MHz -> MMCM
//     CLKOUT1 /20 -> TXUSRCLK  31.25  MHz
//     CLKOUT0 /40 -> TXUSRCLK2 15.625 MHz
//
// Do not use this module for runtime rate switching.  It is a compile-time,
// single-rate 1000M static profile clocking block only.
module laser_gt_usrclk_profile1_1000m (
    input  wire txoutclk_in,
    input  wire mmcm_reset_in,
    output wire txusrclk_out,
    output wire txusrclk2_out,
    output wire mmcm_locked_out
);
    wire txoutclk_buf;
    wire clkfbout;
    wire clkout0_txusrclk2;
    wire clkout1_txusrclk;
    wire clkout0b_unused;
    wire clkout1b_unused;
    wire clkout2_unused;
    wire clkout2b_unused;
    wire clkout3_unused;
    wire clkout3b_unused;
    wire clkout4_unused;
    wire clkout5_unused;
    wire clkout6_unused;
    wire clkfboutb_unused;
    wire clkfbstopped_unused;
    wire clkinstopped_unused;
    wire [15:0] do_unused;
    wire drdy_unused;
    wire psdone_unused;

    BUFG u_txoutclk_bufg (
        .I(txoutclk_in),
        .O(txoutclk_buf)
    );

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (1),
        .CLKFBOUT_MULT_F      (20.0),
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKOUT0_DIVIDE_F     (40.0),
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKOUT1_DIVIDE       (20),
        .CLKOUT1_PHASE        (0.000),
        .CLKOUT1_DUTY_CYCLE   (0.500),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .CLKOUT2_DIVIDE       (1),
        .CLKOUT2_PHASE        (0.000),
        .CLKOUT2_DUTY_CYCLE   (0.500),
        .CLKOUT2_USE_FINE_PS  ("FALSE"),
        .CLKOUT3_DIVIDE       (1),
        .CLKOUT3_PHASE        (0.000),
        .CLKOUT3_DUTY_CYCLE   (0.500),
        .CLKOUT3_USE_FINE_PS  ("FALSE"),
        .REF_JITTER1          (0.010)
    ) u_txusrclk_mmcm (
        .CLKFBOUT            (clkfbout),
        .CLKFBOUTB           (clkfboutb_unused),
        .CLKOUT0             (clkout0_txusrclk2),
        .CLKOUT0B            (clkout0b_unused),
        .CLKOUT1             (clkout1_txusrclk),
        .CLKOUT1B            (clkout1b_unused),
        .CLKOUT2             (clkout2_unused),
        .CLKOUT2B            (clkout2b_unused),
        .CLKOUT3             (clkout3_unused),
        .CLKOUT3B            (clkout3b_unused),
        .CLKOUT4             (clkout4_unused),
        .CLKOUT5             (clkout5_unused),
        .CLKOUT6             (clkout6_unused),
        .CLKFBIN             (clkfbout),
        .CLKIN1              (txoutclk_buf),
        .CLKIN2              (1'b0),
        .CLKINSEL            (1'b1),
        .DADDR               (7'h00),
        .DCLK                (1'b0),
        .DEN                 (1'b0),
        .DI                  (16'h0000),
        .DO                  (do_unused),
        .DRDY                (drdy_unused),
        .DWE                 (1'b0),
        .PSCLK               (1'b0),
        .PSEN                (1'b0),
        .PSINCDEC            (1'b0),
        .PSDONE              (psdone_unused),
        .LOCKED              (mmcm_locked_out),
        .CLKINSTOPPED        (clkinstopped_unused),
        .CLKFBSTOPPED        (clkfbstopped_unused),
        .PWRDWN              (1'b0),
        .RST                 (mmcm_reset_in)
    );

    BUFG u_txusrclk2_bufg (
        .I(clkout0_txusrclk2),
        .O(txusrclk2_out)
    );

    BUFG u_txusrclk_bufg (
        .I(clkout1_txusrclk),
        .O(txusrclk_out)
    );
endmodule

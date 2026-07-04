`timescale 1 ps / 1 ps

// Board-level wrapper for static 2000 Mb/s GT TX Profile 2 validation.
//
// This top keeps the same board pins and the same PS/BD control path as
// laser_tx_board_top, but instantiates laser_gt_tx_profile2_2000m instead of
// the verified 500M Profile 0 wrapper.  It is not used for runtime rate
// switching.
module laser_tx_board_top_profile2_2000m (
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,
    inout  wire        SPI_1_0_io0_io,
    inout  wire        SPI_1_0_io1_io,
    inout  wire        SPI_1_0_sck_io,
    inout  wire        SPI_1_0_ss_io,
    output wire        SPI_1_0_ss1_o,
    output wire        acq_gate_out_0,
    output wire        acq_trig_out_0,
    output wire        eom_out_0,
    output wire        soa_gate_out_0,

    input  wire        gt_refclk125_p,
    input  wire        gt_refclk125_n,
    output wire        gtx_txp_out,
    output wire        gtx_txn_out
);

    wire spi_ss2_unused;
    wire gt_ctrl_clk;
    wire gt_ctrl_rst;
    wire gt_txusrclk2;
    wire gt_tx_rst;
    wire gt_ready;
    wire [31:0] gt_status;
    wire [31:0] gpio_ctrl_to_gt_unused;
    wire [31:0] gpio_status_to_gt_unused;
    wire [63:0] laser_txdata;
    wire [63:0] laser_valid_mask;

    system_wrapper u_system_wrapper (
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_ck_n          (DDR_ck_n),
        .DDR_ck_p          (DDR_ck_p),
        .DDR_cke           (DDR_cke),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
        .SPI_1_0_io0_io    (SPI_1_0_io0_io),
        .SPI_1_0_io1_io    (SPI_1_0_io1_io),
        .SPI_1_0_sck_io    (SPI_1_0_sck_io),
        .SPI_1_0_ss_io     (SPI_1_0_ss_io),
        .SPI_1_0_ss1_o     (SPI_1_0_ss1_o),
        .SPI_1_0_ss2_o     (spi_ss2_unused),
        .acq_gate_out_0    (acq_gate_out_0),
        .acq_trig_out_0    (acq_trig_out_0),
        .eom_out_0         (eom_out_0),
        .soa_gate_out_0    (soa_gate_out_0),
        .gt_ctrl_clk       (gt_ctrl_clk),
        .gt_ctrl_rst       (gt_ctrl_rst),
        .gt_ready          (gt_ready),
        .gt_status_in      (gt_status),
        .gpio_ctrl_to_gt   (gpio_ctrl_to_gt_unused),
        .gpio_status_to_gt (gpio_status_to_gt_unused),
        .tx_rst            (gt_tx_rst),
        .txdata            (laser_txdata),
        .txusrclk2         (gt_txusrclk2),
        .valid_mask        (laser_valid_mask)
    );

    laser_gt_tx_profile2_2000m u_laser_gt_tx_profile2_2000m (
        .ctrl_clk       (gt_ctrl_clk),
        .ctrl_rst       (gt_ctrl_rst),
        .gt_refclk125_p (gt_refclk125_p),
        .gt_refclk125_n (gt_refclk125_n),
        .txdata_in      (laser_txdata),
        .valid_mask_in  (laser_valid_mask),
        .txusrclk2_out  (gt_txusrclk2),
        .tx_rst_out     (gt_tx_rst),
        .gt_ready_out   (gt_ready),
        .gt_status_out  (gt_status),
        .gtx_txp_out    (gtx_txp_out),
        .gtx_txn_out    (gtx_txn_out)
    );

endmodule


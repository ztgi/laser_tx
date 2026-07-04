`timescale 1 ps / 1 ps

// Board-level wrapper for the two-chip shared SPI bus.
//
// The Zynq-7000 PS7 SPI EMIO interface contains three slave-select outputs,
// but this board routes only SS0 (ADRV9009) and SS1 (AD9528). SS2 is consumed
// internally and deliberately has no package-level port.
module laser_tx_board_top (
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

    // Single optical TX lane.  These are GTX dedicated pins, not GPIO.
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
    wire [31:0] gpio_ctrl_to_gt;
    wire [31:0] gpio_status_to_gt;
    wire [63:0] laser_txdata;
    wire [63:0] laser_valid_mask;
    wire [7:0]  dbg_rate_state;
    wire [15:0] dbg_target_rate_mbps;
    wire [15:0] dbg_current_rate_mbps;
    wire        dbg_rate_error;
    wire [7:0]  dbg_rate_error_code;
    wire        dbg_gt_drp_write_attempted;
    wire        dbg_mmcm_drp_write_attempted;
    wire        dbg_gt_drp_busy;
    wire        dbg_gt_drp_done;
    wire        dbg_gt_drp_error;
    wire        dbg_mmcm_drp_busy;
    wire        dbg_mmcm_drp_done;
    wire        dbg_mmcm_drp_error;
    wire        dbg_txusrclk2_alive_axi;
    wire [31:0] dbg_txusrclk2_freq_counter_axi;
    wire        dbg_tx_quiesce_req;
    wire        dbg_tx_idle_seen;
    wire        dbg_apply_enable_blocked;
    wire        dbg_tx_mmcm_reset_wizard;
    wire        dbg_tx_mmcm_reset_rate;
    wire        dbg_tx_mmcm_reset;
    wire        dbg_tx_mmcm_locked_raw;
    wire        dbg_tx_mmcm_locked_sync;
    wire        dbg_rate_gt_tx_reset;
    wire        dbg_gt0_gttxreset_effective;
    wire        dbg_rate_txuserrdy_block;
    wire        dbg_gt0_txuserrdy_effective;
    wire        dbg_txresetdone_sync;
    wire        dbg_gt_ready;
    wire [6:0]  dbg_mmcm_drp_addr;
    wire [15:0] dbg_mmcm_drp_di;
    wire [15:0] dbg_mmcm_drp_do;
    wire        dbg_mmcm_drp_en;
    wire        dbg_mmcm_drp_we;
    wire        dbg_mmcm_drp_rdy;
    wire [8:0]  dbg_gt_drp_addr;
    wire [15:0] dbg_gt_drp_di;
    wire [15:0] dbg_gt_drp_do;
    wire        dbg_gt_drp_en;
    wire        dbg_gt_drp_we;
    wire        dbg_gt_drp_rdy;
    wire [15:0] dbg_gt_drp_readback_value;
    wire        dbg_txoutclk_alive_axi;
    wire [31:0] dbg_timeout_count;

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
        .dbg_apply_enable_blocked       (dbg_apply_enable_blocked),
        .dbg_current_rate_mbps          (dbg_current_rate_mbps),
        .dbg_gt_drp_busy                (dbg_gt_drp_busy),
        .dbg_gt_drp_done                (dbg_gt_drp_done),
        .dbg_gt_drp_error               (dbg_gt_drp_error),
        .dbg_gt_drp_write_attempted     (dbg_gt_drp_write_attempted),
        .dbg_mmcm_drp_busy              (dbg_mmcm_drp_busy),
        .dbg_mmcm_drp_done              (dbg_mmcm_drp_done),
        .dbg_mmcm_drp_error             (dbg_mmcm_drp_error),
        .dbg_mmcm_drp_write_attempted   (dbg_mmcm_drp_write_attempted),
        .dbg_rate_error                 (dbg_rate_error),
        .dbg_rate_error_code            (dbg_rate_error_code),
        .dbg_rate_state                 (dbg_rate_state),
        .dbg_target_rate_mbps           (dbg_target_rate_mbps),
        .dbg_tx_idle_seen               (dbg_tx_idle_seen),
        .dbg_tx_quiesce_req             (dbg_tx_quiesce_req),
        .dbg_tx_mmcm_reset_wizard       (dbg_tx_mmcm_reset_wizard),
        .dbg_tx_mmcm_reset_rate         (dbg_tx_mmcm_reset_rate),
        .dbg_tx_mmcm_reset              (dbg_tx_mmcm_reset),
        .dbg_tx_mmcm_locked_raw         (dbg_tx_mmcm_locked_raw),
        .dbg_tx_mmcm_locked_sync        (dbg_tx_mmcm_locked_sync),
        .dbg_rate_gt_tx_reset           (dbg_rate_gt_tx_reset),
        .dbg_gt0_gttxreset_effective    (dbg_gt0_gttxreset_effective),
        .dbg_rate_txuserrdy_block       (dbg_rate_txuserrdy_block),
        .dbg_gt0_txuserrdy_effective    (dbg_gt0_txuserrdy_effective),
        .dbg_txresetdone_sync           (dbg_txresetdone_sync),
        .dbg_gt_ready                   (dbg_gt_ready),
        .dbg_mmcm_drp_addr              (dbg_mmcm_drp_addr),
        .dbg_mmcm_drp_di                (dbg_mmcm_drp_di),
        .dbg_mmcm_drp_do                (dbg_mmcm_drp_do),
        .dbg_mmcm_drp_en                (dbg_mmcm_drp_en),
        .dbg_mmcm_drp_we                (dbg_mmcm_drp_we),
        .dbg_mmcm_drp_rdy               (dbg_mmcm_drp_rdy),
        .dbg_gt_drp_addr                (dbg_gt_drp_addr),
        .dbg_gt_drp_di                  (dbg_gt_drp_di),
        .dbg_gt_drp_do                  (dbg_gt_drp_do),
        .dbg_gt_drp_en                  (dbg_gt_drp_en),
        .dbg_gt_drp_we                  (dbg_gt_drp_we),
        .dbg_gt_drp_rdy                 (dbg_gt_drp_rdy),
        .dbg_gt_drp_readback_value      (dbg_gt_drp_readback_value),
        .dbg_txoutclk_alive_axi         (dbg_txoutclk_alive_axi),
        .dbg_timeout_count              (dbg_timeout_count),
        .dbg_txusrclk2_alive_axi        (dbg_txusrclk2_alive_axi),
        .dbg_txusrclk2_freq_counter_axi (dbg_txusrclk2_freq_counter_axi),
        .gt_ctrl_clk       (gt_ctrl_clk),
        .gt_ctrl_rst       (gt_ctrl_rst),
        .gt_ready          (gt_ready),
        .gt_status_in      (gt_status),
        .gpio_ctrl_to_gt   (gpio_ctrl_to_gt),
        .gpio_status_to_gt (gpio_status_to_gt),
        .tx_rst            (gt_tx_rst),
        .txdata            (laser_txdata),
        .txusrclk2         (gt_txusrclk2),
        .valid_mask        (laser_valid_mask)
    );

    laser_gt_tx_profile0 u_laser_gt_tx_profile0 (
        .ctrl_clk      (gt_ctrl_clk),
        .ctrl_rst      (gt_ctrl_rst),
        .gt_refclk125_p(gt_refclk125_p),
        .gt_refclk125_n(gt_refclk125_n),
        .gpio_ctrl_axi (gpio_ctrl_to_gt),
        .gpio_status_axi(gpio_status_to_gt),
        .txdata_in     (laser_txdata),
        .valid_mask_in (laser_valid_mask),
        .txusrclk2_out (gt_txusrclk2),
        .tx_rst_out    (gt_tx_rst),
        .gt_ready_out  (gt_ready),
        .gt_status_out (gt_status),
        .dbg_rate_state                 (dbg_rate_state),
        .dbg_target_rate_mbps           (dbg_target_rate_mbps),
        .dbg_current_rate_mbps          (dbg_current_rate_mbps),
        .dbg_rate_error                 (dbg_rate_error),
        .dbg_rate_error_code            (dbg_rate_error_code),
        .dbg_gt_drp_write_attempted     (dbg_gt_drp_write_attempted),
        .dbg_mmcm_drp_write_attempted   (dbg_mmcm_drp_write_attempted),
        .dbg_gt_drp_busy                (dbg_gt_drp_busy),
        .dbg_gt_drp_done                (dbg_gt_drp_done),
        .dbg_gt_drp_error               (dbg_gt_drp_error),
        .dbg_mmcm_drp_busy              (dbg_mmcm_drp_busy),
        .dbg_mmcm_drp_done              (dbg_mmcm_drp_done),
        .dbg_mmcm_drp_error             (dbg_mmcm_drp_error),
        .dbg_txusrclk2_alive_axi        (dbg_txusrclk2_alive_axi),
        .dbg_txusrclk2_freq_counter_axi (dbg_txusrclk2_freq_counter_axi),
        .dbg_tx_quiesce_req             (dbg_tx_quiesce_req),
        .dbg_tx_idle_seen               (dbg_tx_idle_seen),
        .dbg_apply_enable_blocked       (dbg_apply_enable_blocked),
        .dbg_tx_mmcm_reset_wizard       (dbg_tx_mmcm_reset_wizard),
        .dbg_tx_mmcm_reset_rate         (dbg_tx_mmcm_reset_rate),
        .dbg_tx_mmcm_reset              (dbg_tx_mmcm_reset),
        .dbg_tx_mmcm_locked_raw         (dbg_tx_mmcm_locked_raw),
        .dbg_tx_mmcm_locked_sync        (dbg_tx_mmcm_locked_sync),
        .dbg_rate_gt_tx_reset           (dbg_rate_gt_tx_reset),
        .dbg_gt0_gttxreset_effective    (dbg_gt0_gttxreset_effective),
        .dbg_rate_txuserrdy_block       (dbg_rate_txuserrdy_block),
        .dbg_gt0_txuserrdy_effective    (dbg_gt0_txuserrdy_effective),
        .dbg_txresetdone_sync           (dbg_txresetdone_sync),
        .dbg_gt_ready                   (dbg_gt_ready),
        .dbg_mmcm_drp_addr              (dbg_mmcm_drp_addr),
        .dbg_mmcm_drp_di                (dbg_mmcm_drp_di),
        .dbg_mmcm_drp_do                (dbg_mmcm_drp_do),
        .dbg_mmcm_drp_en                (dbg_mmcm_drp_en),
        .dbg_mmcm_drp_we                (dbg_mmcm_drp_we),
        .dbg_mmcm_drp_rdy               (dbg_mmcm_drp_rdy),
        .dbg_gt_drp_addr                (dbg_gt_drp_addr),
        .dbg_gt_drp_di                  (dbg_gt_drp_di),
        .dbg_gt_drp_do                  (dbg_gt_drp_do),
        .dbg_gt_drp_en                  (dbg_gt_drp_en),
        .dbg_gt_drp_we                  (dbg_gt_drp_we),
        .dbg_gt_drp_rdy                 (dbg_gt_drp_rdy),
        .dbg_gt_drp_readback_value      (dbg_gt_drp_readback_value),
        .dbg_txoutclk_alive_axi         (dbg_txoutclk_alive_axi),
        .dbg_timeout_count              (dbg_timeout_count),
        .gtx_txp_out   (gtx_txp_out),
        .gtx_txn_out   (gtx_txn_out)
    );

endmodule


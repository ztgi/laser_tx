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

    // AD9528 OUT0 measurement-only MGT reference-clock input in Bank 110.
    // The direct O output is deliberately not connected to the Bank 111 GT.
    input  wire        ad9528_ref0_clk_p,
    input  wire        ad9528_ref0_clk_n,

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
    wire [3:0] dynamic_mailbox_control;
    wire [31:0] dynamic_mailbox_status;
    wire dynamic_descriptor_bram_en;
    wire [7:0] dynamic_descriptor_bram_word_addr;
    wire [31:0] dynamic_descriptor_bram_rdata;
    wire [3:0] dynamic_descriptor_bram_we;
    wire [31:0] dynamic_descriptor_bram_wdata;
    wire dynamic_descriptor_valid;
    wire [2047:0] dynamic_descriptor_active_words;
    wire dynamic_refclk_ready_event;
    wire dynamic_abort_event;
    wire dynamic_rollback_ready_event;
    wire dynamic_descriptor_commit_event;
    wire dynamic_executor_prepared;
    wire dynamic_executor_done;
    wire dynamic_executor_error;
    wire dynamic_executor_rollback_done;
    wire dynamic_executor_verify_pass;
    wire [7:0] dynamic_executor_failed_stage;
    wire [7:0] dynamic_executor_state;
    // AXI/FCLK ILA-only summary. This bus is observational and never feeds
    // back into the mailbox, executor, or legacy rate-switch path.
    wire [31:0] dynamic_rate_debug_bus = {
        3'b000,
        gt_ready,
        2'b00,
        dynamic_rollback_ready_event,
        dynamic_abort_event,
        dynamic_refclk_ready_event,
        dynamic_descriptor_commit_event,
        dynamic_descriptor_valid,
        dynamic_executor_verify_pass,
        dynamic_executor_rollback_done,
        dynamic_executor_error,
        dynamic_executor_done,
        dynamic_executor_prepared,
        dynamic_executor_failed_stage,
        dynamic_executor_state
    };

    localparam integer AD9528_MEASURE_GT_CTRL_CLK_HZ = 50000000;
    localparam integer AD9528_MEASURE_WINDOW_US = 1000;
    localparam integer AD9528_MEASURE_CYCLES = 50000;
    localparam integer AD9528_ODIV2_DIVIDE_FACTOR = 2;
    localparam [3:0] AD9528_MEASURE_FORMAT_VERSION = 4'd1;
    localparam [31:0] AD9528_ODIV2_COUNT_MIN = 32'd60000;
    localparam [31:0] AD9528_ODIV2_COUNT_MAX = 32'd62900;

    wire ad9528_out0_gt_refclk;
    wire ad9528_out0_odiv2_raw;
    wire ad9528_out0_odiv2_clk;
    reg [31:0] ad9528_odiv2_counter = 32'd0;
    reg [31:0] ad9528_odiv2_counter_gray = 32'd0;
    wire [31:0] ad9528_odiv2_counter_next =
        ad9528_odiv2_counter + 1'b1;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ad9528_odiv2_gray_meta_axi;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ad9528_odiv2_gray_sync_axi;
    reg [31:0] ad9528_odiv2_counter_bin_axi;
    reg [31:0] ad9528_odiv2_counter_prev_axi;
    reg [15:0] ad9528_measure_window_count_axi;
    reg ad9528_measure_window_primed_axi;
    (* ASYNC_REG = "TRUE" *) reg ad9528_odiv2_toggle_meta_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg ad9528_odiv2_toggle_axi;
    (* mark_debug = "true" *) reg ad9528_odiv2_alive_axi;
    (* mark_debug = "true" *) reg [31:0] ad9528_odiv2_count_axi;
    (* mark_debug = "true" *) reg ad9528_odiv2_in_range_axi;
    (* mark_debug = "true" *) reg ad9528_measure_valid_axi;
    reg [15:0] ad9528_measure_sequence_axi;
    wire [31:0] ad9528_measure_status_to_ps = {
        ad9528_measure_sequence_axi,
        8'd0,
        AD9528_MEASURE_FORMAT_VERSION,
        1'b0,
        ad9528_odiv2_alive_axi,
        ad9528_odiv2_in_range_axi,
        ad9528_measure_valid_axi
    };
    wire [31:0] ad9528_odiv2_delta_axi =
        ad9528_odiv2_counter_bin_axi - ad9528_odiv2_counter_prev_axi;

    function [31:0] ad9528_gray_to_bin;
        input [31:0] gray;
        integer i;
        begin
            ad9528_gray_to_bin[31] = gray[31];
            for (i = 30; i >= 0; i = i - 1)
                ad9528_gray_to_bin[i] = ad9528_gray_to_bin[i+1] ^ gray[i];
        end
    endfunction

    (* DONT_TOUCH = "TRUE" *) IBUFDS_GTE2 u_ad9528_out0_ibufds_gte2 (
        .I     (ad9528_ref0_clk_p),
        .IB    (ad9528_ref0_clk_n),
        .CEB   (1'b0),
        .O     (ad9528_out0_gt_refclk),
        .ODIV2 (ad9528_out0_odiv2_raw)
    );

    (* DONT_TOUCH = "TRUE" *) BUFG u_ad9528_out0_odiv2_bufg (
        .I (ad9528_out0_odiv2_raw),
        .O (ad9528_out0_odiv2_clk)
    );

    // Free-running source-domain counter. Only Gray code crosses into the
    // stable 50 MHz gt_ctrl_clk/PS-FCLK domain.
    always @(posedge ad9528_out0_odiv2_clk) begin
        ad9528_odiv2_counter <= ad9528_odiv2_counter_next;
        ad9528_odiv2_counter_gray <=
            ad9528_odiv2_counter_next ^ (ad9528_odiv2_counter_next >> 1);
    end

    always @(posedge gt_ctrl_clk) begin
        if (gt_ctrl_rst) begin
            ad9528_odiv2_gray_meta_axi      <= 32'd0;
            ad9528_odiv2_gray_sync_axi      <= 32'd0;
            ad9528_odiv2_counter_bin_axi    <= 32'd0;
            ad9528_odiv2_counter_prev_axi   <= 32'd0;
            ad9528_measure_window_count_axi <= 16'd0;
            ad9528_measure_window_primed_axi <= 1'b0;
            ad9528_odiv2_toggle_meta_axi    <= 1'b0;
            ad9528_odiv2_toggle_axi         <= 1'b0;
            ad9528_odiv2_alive_axi          <= 1'b0;
            ad9528_odiv2_count_axi          <= 32'd0;
            ad9528_odiv2_in_range_axi       <= 1'b0;
            ad9528_measure_valid_axi        <= 1'b0;
            ad9528_measure_sequence_axi     <= 16'd0;
        end else begin
            ad9528_odiv2_gray_meta_axi   <= ad9528_odiv2_counter_gray;
            ad9528_odiv2_gray_sync_axi   <= ad9528_odiv2_gray_meta_axi;
            ad9528_odiv2_counter_bin_axi <=
                ad9528_gray_to_bin(ad9528_odiv2_gray_sync_axi);
            ad9528_odiv2_toggle_meta_axi <= ad9528_odiv2_counter[10];
            ad9528_odiv2_toggle_axi      <= ad9528_odiv2_toggle_meta_axi;

            if (ad9528_measure_window_count_axi == AD9528_MEASURE_CYCLES - 1) begin
                ad9528_measure_window_count_axi <= 16'd0;
                ad9528_odiv2_counter_prev_axi <= ad9528_odiv2_counter_bin_axi;
                ad9528_odiv2_count_axi <= ad9528_odiv2_delta_axi;
                ad9528_odiv2_alive_axi <= (ad9528_odiv2_delta_axi != 32'd0);
                ad9528_measure_valid_axi <= ad9528_measure_window_primed_axi;
                ad9528_measure_sequence_axi <=
                    ad9528_measure_sequence_axi + 1'b1;
                if (ad9528_measure_window_primed_axi) begin
                    ad9528_odiv2_in_range_axi <=
                        (ad9528_odiv2_delta_axi >= AD9528_ODIV2_COUNT_MIN) &&
                        (ad9528_odiv2_delta_axi <= AD9528_ODIV2_COUNT_MAX);
                end else begin
                    ad9528_odiv2_in_range_axi <= 1'b0;
                end
                ad9528_measure_window_primed_axi <= 1'b1;
            end else begin
                ad9528_measure_window_count_axi <=
                    ad9528_measure_window_count_axi + 1'b1;
            end
        end
    end

    // Independent runtime-rate mailbox. Port B reads a transaction shadow
    // written by PS through the AXI BRAM controller. The reader latches all
    // 64 descriptor words before acknowledging PREPARE.
    laser_dynamic_rate_mailbox u_dynamic_rate_mailbox (
        .clk                       (gt_ctrl_clk),
        .rst                       (gt_ctrl_rst),
        .control_toggles           (dynamic_mailbox_control),
        .status_gpio               (dynamic_mailbox_status),
        .bram_en                   (dynamic_descriptor_bram_en),
        .bram_word_addr            (dynamic_descriptor_bram_word_addr),
        .bram_we                   (dynamic_descriptor_bram_we),
        .bram_wdata                (dynamic_descriptor_bram_wdata),
        .bram_rdata                (dynamic_descriptor_bram_rdata),
        .active_descriptor_valid   (dynamic_descriptor_valid),
        .active_words_flat         (dynamic_descriptor_active_words),
        .descriptor_commit_event   (dynamic_descriptor_commit_event),
        .executor_prepared_ack     (dynamic_executor_prepared),
        .executor_switch_done      (dynamic_executor_done),
        .executor_switch_error     (dynamic_executor_error),
        .executor_rollback_done    (dynamic_executor_rollback_done),
        .executor_verify_pass      (dynamic_executor_verify_pass),
        .executor_failed_stage     (dynamic_executor_failed_stage),
        .refclk_ready_event        (dynamic_refclk_ready_event),
        .abort_event               (dynamic_abort_event),
        .rollback_ready_event      (dynamic_rollback_ready_event)
    );

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
        .ad9528_measure_count_in  (ad9528_odiv2_count_axi),
        .ad9528_measure_status_in (ad9528_measure_status_to_ps),
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
        .dynamic_descriptor_bram_portb_addr ({22'd0, dynamic_descriptor_bram_word_addr, 2'b00}),
        .dynamic_descriptor_bram_portb_clk  (gt_ctrl_clk),
        .dynamic_descriptor_bram_portb_din  (dynamic_descriptor_bram_wdata),
        .dynamic_descriptor_bram_portb_dout (dynamic_descriptor_bram_rdata),
        .dynamic_descriptor_bram_portb_en   (dynamic_descriptor_bram_en),
        .dynamic_descriptor_bram_portb_rst  (gt_ctrl_rst),
        .dynamic_descriptor_bram_portb_we   (dynamic_descriptor_bram_we),
        .dynamic_mailbox_control_out        (dynamic_mailbox_control),
        .dynamic_mailbox_status_in          (dynamic_mailbox_status),
        .dynamic_rate_debug_bus             (dynamic_rate_debug_bus),
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
        .ad9528_gtnorthrefclk0(ad9528_out0_gt_refclk),
        .gpio_ctrl_axi (gpio_ctrl_to_gt),
        .gpio_status_axi(gpio_status_to_gt),
        .dynamic_start(dynamic_descriptor_commit_event),
        .dynamic_descriptor_valid(dynamic_descriptor_valid),
        .dynamic_words(dynamic_descriptor_active_words),
        .dynamic_refclk_ready(dynamic_refclk_ready_event),
        .dynamic_abort(dynamic_abort_event),
        .dynamic_rollback_ready(dynamic_rollback_ready_event),
        .dynamic_prepared(dynamic_executor_prepared),
        .dynamic_done(dynamic_executor_done),
        .dynamic_error(dynamic_executor_error),
        .dynamic_rollback_done(dynamic_executor_rollback_done),
        .dynamic_verify_pass(dynamic_executor_verify_pass),
        .dynamic_failed_stage(dynamic_executor_failed_stage),
        .dynamic_state(dynamic_executor_state),
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


`timescale 1ns/1ps

// Fixed compile-time GT TX Profile 1 for static 1000 Mb/s validation.
//
// This module is deliberately parallel to laser_gt_tx_profile0, but uses the
// 1000M user-clock MMCM parameters and reports profile ID 1.  It contains no
// runtime rate switching path, no GTX DRP writer and no MMCM DRP writer.
module laser_gt_tx_profile1_1000m (
    input  wire        ctrl_clk,
    input  wire        ctrl_rst,
    input  wire        gt_refclk125_p,
    input  wire        gt_refclk125_n,
    input  wire [63:0] txdata_in,
    input  wire [63:0] valid_mask_in,
    output wire        txusrclk2_out,
    output wire        tx_rst_out,
    output wire        gt_ready_out,
    output wire [31:0] gt_status_out,
    output wire        gtx_txp_out,
    output wire        gtx_txn_out
);
    localparam [2:0] GT_PROFILE_ID = 3'd1;
    localparam integer READY_STABLE_CYCLES = 64;
    localparam integer READY_COUNT_WIDTH = $clog2(READY_STABLE_CYCLES + 1);
    localparam integer TXUSRCLK2_DEBUG_DIVIDE = 16;
    localparam integer TXUSRCLK2_DEBUG_COUNT_WIDTH = $clog2(TXUSRCLK2_DEBUG_DIVIDE);
    localparam integer TXUSRCLK2_FREQ_WIDTH = 32;

    function [TXUSRCLK2_FREQ_WIDTH-1:0] gray_to_bin;
        input [TXUSRCLK2_FREQ_WIDTH-1:0] gray;
        integer i;
        begin
            gray_to_bin[TXUSRCLK2_FREQ_WIDTH-1] = gray[TXUSRCLK2_FREQ_WIDTH-1];
            for (i = TXUSRCLK2_FREQ_WIDTH-2; i >= 0; i = i - 1) begin
                gray_to_bin[i] = gray_to_bin[i+1] ^ gray[i];
            end
        end
    endfunction

    wire gtrefclk125;
    wire gtrefclk125_div2_unused;
    wire txoutclk;
    wire txusrclk;
    wire txusrclk2;
    wire tx_mmcm_reset;
    wire tx_mmcm_locked;
    wire txresetdone;
    wire cplllock;
    wire txresetdone_native;
    wire tx_fsm_reset_done;
    wire [63:0] rxdata_unused;
    wire [7:0] dmonitor_unused;
    wire [6:0] rxmonitor_unused;
    wire cpllfbclklost_unused;
    wire rxresetdone_unused;
    wire eyescandataerror_unused;
    wire rxoutclk_unused;
    wire rxoutclkfabric_unused;
    wire txoutclkfabric_unused;
    wire txratedone_unused;
    wire [15:0] drpdo_unused;
    wire drprdy_unused;

    (* ASYNC_REG = "TRUE" *) reg cplllock_meta;
    (* ASYNC_REG = "TRUE" *) reg cplllock_sync;
    (* ASYNC_REG = "TRUE" *) reg tx_mmcm_locked_meta;
    (* ASYNC_REG = "TRUE" *) reg tx_mmcm_locked_sync;
    (* ASYNC_REG = "TRUE" *) reg txresetdone_meta;
    (* ASYNC_REG = "TRUE" *) reg txresetdone_sync;
    reg [READY_COUNT_WIDTH-1:0] ready_count;
    reg gt_ready_ctrl;

    (* ASYNC_REG = "TRUE" *) reg gt_ready_meta_tx;
    (* ASYNC_REG = "TRUE" *) reg gt_ready_tx;
    reg [23:0] tx_word_count;

    (* mark_debug = "true" *) reg [TXUSRCLK2_DEBUG_COUNT_WIDTH-1:0] txusrclk2_debug_count;
    (* mark_debug = "true" *) reg txusrclk2_divided_debug;
    (* mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_tx;
    wire [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_gray_tx =
        txusrclk2_counter_tx ^ (txusrclk2_counter_tx >> 1);

    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_gray_meta_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_gray_sync_axi;
    (* mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_freq_counter_axi;
    reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_freq_counter_prev_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg txusrclk2_toggle_meta_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg txusrclk2_toggle_axi;
    (* mark_debug = "true" *) reg txusrclk2_alive_axi;
    reg [7:0] txusrclk2_alive_timeout_axi;

    IBUFDS_GTE2 u_refclk125_ibuf (
        .I(gt_refclk125_p),
        .IB(gt_refclk125_n),
        .CEB(1'b0),
        .O(gtrefclk125),
        .ODIV2(gtrefclk125_div2_unused)
    );

    laser_gt_usrclk_profile1_1000m u_tx_usrclk_profile1_1000m (
        .txoutclk_in     (txoutclk),
        .mmcm_reset_in   (tx_mmcm_reset),
        .txusrclk_out    (txusrclk),
        .txusrclk2_out   (txusrclk2),
        .mmcm_locked_out (tx_mmcm_locked)
    );

    assign txusrclk2_out = txusrclk2;

    always @(posedge ctrl_clk) begin
        if (ctrl_rst) begin
            cplllock_meta        <= 1'b0;
            cplllock_sync        <= 1'b0;
            tx_mmcm_locked_meta  <= 1'b0;
            tx_mmcm_locked_sync  <= 1'b0;
            txresetdone_meta     <= 1'b0;
            txresetdone_sync     <= 1'b0;
            ready_count          <= {READY_COUNT_WIDTH{1'b0}};
            gt_ready_ctrl        <= 1'b0;
            txusrclk2_counter_gray_meta_axi <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_counter_gray_sync_axi <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_freq_counter_axi      <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_freq_counter_prev_axi <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_toggle_meta_axi       <= 1'b0;
            txusrclk2_toggle_axi            <= 1'b0;
            txusrclk2_alive_axi             <= 1'b0;
            txusrclk2_alive_timeout_axi     <= 8'hff;
        end else begin
            cplllock_meta        <= cplllock;
            cplllock_sync        <= cplllock_meta;
            tx_mmcm_locked_meta  <= tx_mmcm_locked;
            tx_mmcm_locked_sync  <= tx_mmcm_locked_meta;
            txresetdone_meta     <= txresetdone;
            txresetdone_sync     <= txresetdone_meta;
            txusrclk2_counter_gray_meta_axi <= txusrclk2_counter_gray_tx;
            txusrclk2_counter_gray_sync_axi <= txusrclk2_counter_gray_meta_axi;
            txusrclk2_freq_counter_axi      <= gray_to_bin(txusrclk2_counter_gray_sync_axi);
            txusrclk2_toggle_meta_axi       <= txusrclk2_counter_tx[8];
            txusrclk2_toggle_axi            <= txusrclk2_toggle_meta_axi;
            if (txusrclk2_freq_counter_axi != txusrclk2_freq_counter_prev_axi) begin
                txusrclk2_alive_axi <= 1'b1;
                txusrclk2_alive_timeout_axi <= 8'd0;
                txusrclk2_freq_counter_prev_axi <= txusrclk2_freq_counter_axi;
            end else if (txusrclk2_alive_timeout_axi == 8'hff) begin
                txusrclk2_alive_axi <= 1'b0;
            end else begin
                txusrclk2_alive_timeout_axi <= txusrclk2_alive_timeout_axi + 1'b1;
            end
            if (!cplllock_sync || !tx_mmcm_locked_sync || !txresetdone_sync) begin
                ready_count   <= {READY_COUNT_WIDTH{1'b0}};
                gt_ready_ctrl <= 1'b0;
            end else if (ready_count < READY_STABLE_CYCLES) begin
                ready_count   <= ready_count + 1'b1;
                gt_ready_ctrl <= 1'b0;
            end else begin
                gt_ready_ctrl <= 1'b1;
            end
        end
    end

    always @(posedge txusrclk2) begin
        if (ctrl_rst) begin
            gt_ready_meta_tx          <= 1'b0;
            gt_ready_tx               <= 1'b0;
            tx_word_count             <= 24'd0;
            txusrclk2_debug_count     <= {TXUSRCLK2_DEBUG_COUNT_WIDTH{1'b0}};
            txusrclk2_divided_debug   <= 1'b0;
            txusrclk2_counter_tx       <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
        end else begin
            gt_ready_meta_tx <= gt_ready_ctrl;
            gt_ready_tx      <= gt_ready_meta_tx;
            txusrclk2_counter_tx <= txusrclk2_counter_tx + 1'b1;
            if (!gt_ready_tx) begin
                tx_word_count <= 24'd0;
            end else if (|valid_mask_in) begin
                tx_word_count <= tx_word_count + 1'b1;
            end

            if (txusrclk2_debug_count == TXUSRCLK2_DEBUG_DIVIDE - 1) begin
                txusrclk2_debug_count   <= {TXUSRCLK2_DEBUG_COUNT_WIDTH{1'b0}};
                txusrclk2_divided_debug <= ~txusrclk2_divided_debug;
            end else begin
                txusrclk2_debug_count <= txusrclk2_debug_count + 1'b1;
            end
        end
    end

    assign tx_rst_out   = ~gt_ready_tx;
    assign gt_ready_out = gt_ready_tx;

    gtwizard_0 u_gtwizard_0 (
        .sysclk_in                    (ctrl_clk),
        .soft_reset_tx_in             (ctrl_rst),
        .soft_reset_rx_in             (1'b1),
        .dont_reset_on_data_error_in  (1'b1),
        .gt0_tx_fsm_reset_done_out    (tx_fsm_reset_done),
        .gt0_rx_fsm_reset_done_out    (),
        .gt0_data_valid_in            (1'b1),
        .gt0_tx_mmcm_lock_in          (tx_mmcm_locked),
        .gt0_tx_mmcm_reset_out        (tx_mmcm_reset),
        .gt0_rx_mmcm_lock_in          (1'b1),
        .gt0_rx_mmcm_reset_out        (),
        .gt0_cpllfbclklost_out        (cpllfbclklost_unused),
        .gt0_cplllock_out             (cplllock),
        .gt0_cplllockdetclk_in        (ctrl_clk),
        .gt0_cpllpd_in                (1'b0),
        .gt0_cpllreset_in             (ctrl_rst),
        .gt0_gtrefclk0_in             (gtrefclk125),
        .gt0_gtrefclk1_in             (1'b0),
        .gt0_drpaddr_in               (9'd0),
        .gt0_drpclk_in                (ctrl_clk),
        .gt0_drpdi_in                 (16'd0),
        .gt0_drpdo_out                (drpdo_unused),
        .gt0_drpen_in                 (1'b0),
        .gt0_drprdy_out               (drprdy_unused),
        .gt0_drpwe_in                 (1'b0),
        .gt0_txsysclksel_in           (2'b00),
        .gt0_dmonitorout_out          (dmonitor_unused),
        .gt0_eyescanreset_in          (1'b0),
        .gt0_rxuserrdy_in             (1'b0),
        .gt0_eyescandataerror_out     (eyescandataerror_unused),
        .gt0_eyescantrigger_in        (1'b0),
        .gt0_rxusrclk_in              (txusrclk),
        .gt0_rxusrclk2_in             (txusrclk2),
        .gt0_rxdata_out               (rxdata_unused),
        .gt0_gtxrxp_in                (1'b0),
        .gt0_gtxrxn_in                (1'b0),
        .gt0_rxdfelpmreset_in         (1'b1),
        .gt0_rxmonitorout_out         (rxmonitor_unused),
        .gt0_rxmonitorsel_in          (2'b00),
        .gt0_rxoutclk_out             (rxoutclk_unused),
        .gt0_rxoutclkfabric_out       (rxoutclkfabric_unused),
        .gt0_gtrxreset_in             (1'b1),
        .gt0_rxpmareset_in            (1'b1),
        .gt0_rxresetdone_out          (rxresetdone_unused),
        .gt0_gttxreset_in             (ctrl_rst | ~cplllock_sync),
        .gt0_txuserrdy_in             (~ctrl_rst & cplllock_sync),
        .gt0_txusrclk_in              (txusrclk),
        .gt0_txusrclk2_in             (txusrclk2),
        .gt0_txrate_in                (3'b000),
        .gt0_txdata_in                (gt_ready_tx ? txdata_in : 64'd0),
        .gt0_gtxtxn_out               (gtx_txn_out),
        .gt0_gtxtxp_out               (gtx_txp_out),
        .gt0_txoutclk_out             (txoutclk),
        .gt0_txoutclkfabric_out       (txoutclkfabric_unused),
        .gt0_txoutclkpcs_out          (),
        .gt0_txratedone_out           (txratedone_unused),
        .gt0_txresetdone_out          (txresetdone_native),
        .gt0_qplloutclk_in            (1'b0),
        .gt0_qplloutrefclk_in         (1'b0)
    );

    assign txresetdone = txresetdone_native & tx_fsm_reset_done;

    // Dedicated static-1000M GT debug ILA.  This is sampled by TXUSRCLK2, so
    // the divided debug probe should toggle every 16 TXUSRCLK2 samples.  It is
    // intended for static Profile 1 board bring-up only.
    ila_gt_profile1_1000m u_ila_gt_profile1_1000m (
        .clk    (txusrclk2),
        .probe0 (gt_ready_tx),
        .probe1 (cplllock_sync),
        .probe2 (txresetdone_sync),
        .probe3 (tx_mmcm_locked_sync),
        .probe4 (txusrclk2_divided_debug),
        .probe5 (tx_word_count),
        .probe6 (txdata_in),
        .probe7 (valid_mask_in)
    );

    assign gt_status_out = {
        tx_word_count,
        GT_PROFILE_ID,
        ctrl_rst,
        ~gt_ready_tx,
        gt_ready_tx,
        txresetdone_sync,
        cplllock_sync
    };
endmodule

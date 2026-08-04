`timescale 1ns / 1ps
`default_nettype wire

// Self-maintained GT adapter.  The XCI-generated gtwizard_0_GT, startup FSM
// and CPLL-railing sources remain untouched; this file owns only the binding
// between laser_gt_tx_profile0 and those generated modules.
module gtwizard_0_adapter (
    input sysclk_in, input soft_reset_tx_in, input soft_reset_rx_in,
    input dont_reset_on_data_error_in,
    output gt0_tx_fsm_reset_done_out, output gt0_rx_fsm_reset_done_out,
    input gt0_data_valid_in, input gt0_tx_mmcm_lock_in,
    output gt0_tx_mmcm_reset_out, input gt0_rx_mmcm_lock_in,
    output gt0_rx_mmcm_reset_out,
    output gt0_cpllfbclklost_out, output gt0_cplllock_out,
    input gt0_cplllockdetclk_in, input gt0_cpllpd_in,
    input gt0_cpllreset_in,
    input gt0_gtrefclk0_in, input gt0_gtrefclk1_in,
    input gt0_gtnorthrefclk0_in, input [2:0] gt0_cpllrefclksel_in,
    input [8:0] gt0_drpaddr_in, input gt0_drpclk_in,
    input [15:0] gt0_drpdi_in, output [15:0] gt0_drpdo_out,
    input gt0_drpen_in, output gt0_drprdy_out, input gt0_drpwe_in,
    input [1:0] gt0_txsysclksel_in, output [7:0] gt0_dmonitorout_out,
    input gt0_eyescanreset_in, input gt0_rxuserrdy_in,
    output gt0_eyescandataerror_out, input gt0_eyescantrigger_in,
    input gt0_rxusrclk_in, input gt0_rxusrclk2_in,
    output [63:0] gt0_rxdata_out, input gt0_gtxrxp_in,
    input gt0_gtxrxn_in, input gt0_rxdfelpmreset_in,
    output [6:0] gt0_rxmonitorout_out, input [1:0] gt0_rxmonitorsel_in,
    output gt0_rxoutclk_out, output gt0_rxoutclkfabric_out,
    input gt0_gtrxreset_in, input gt0_rxpmareset_in,
    output gt0_rxresetdone_out, input gt0_gttxreset_in,
    input gt0_txuserrdy_in, input gt0_txusrclk_in,
    input gt0_txusrclk2_in, input [2:0] gt0_txrate_in,
    input [63:0] gt0_txdata_in, output gt0_gtxtxn_out,
    output gt0_gtxtxp_out, output gt0_txoutclk_out,
    output gt0_txoutclkfabric_out, output gt0_txoutclkpcs_out,
    output gt0_txratedone_out, output gt0_txresetdone_out,
    input gt0_qplloutclk_in, input gt0_qplloutrefclk_in
);
    wire gt0_cpllreset_t, gt0_cpllrail_reset_i;
    wire gt0_gttxreset_t, gt0_gtrxreset_t;
    wire gt0_txuserrdy_t, gt0_rxuserrdy_t;
    wire gt0_rxdfeagchold_i, gt0_rxdfelfhold_i;
    wire gt0_rxlpmlfhold_i, gt0_rxlpmhfhold_i;
    wire gt0_cpllrefclklost_i, gt0_cplllock_i;
    wire gt0_txresetdone_i, gt0_rxresetdone_i;
    wire gt0_rxoutclk_i, gt0_txoutclk_i;
    wire gt0_recclk_stable_i;
    wire gt0_cpllpd_t, gt0_cpllpd_i;
    wire gt0_cpllreset_i = gt0_cpllreset_in | gt0_cpllreset_t | gt0_cpllrail_reset_i;
    wire gt0_gttxreset_i = gt0_gttxreset_in | gt0_gttxreset_t;
    wire gt0_gtrxreset_i = gt0_gtrxreset_in | gt0_gtrxreset_t;
    wire gt0_txuserrdy_i = gt0_txuserrdy_in & gt0_txuserrdy_t;
    wire gt0_rxuserrdy_i = gt0_rxuserrdy_in & gt0_rxuserrdy_t;
    wire tied_to_ground_i = 1'b0;
    wire tied_to_vcc_i = 1'b1;
    reg [17:0] gt0_rx_cdrlock_counter = 18'd0;
    reg gt0_rx_cdrlocked_reg = 1'b0;

    assign gt0_cpllpd_i = gt0_cpllpd_in | gt0_cpllpd_t;
    assign gt0_cplllock_out = gt0_cplllock_i;
    assign gt0_txresetdone_out = gt0_txresetdone_i;
    assign gt0_rxresetdone_out = gt0_rxresetdone_i;
    assign gt0_rxoutclk_out = gt0_rxoutclk_i;
    assign gt0_txoutclk_out = gt0_txoutclk_i;
    assign gt0_recclk_stable_i = gt0_rx_cdrlocked_reg;

    gtwizard_0_GT #(
        .GT_SIM_GTRESET_SPEEDUP ("TRUE"),
        .RX_DFE_KL_CFG2_IN     (32'h301148AC),
        .PCS_RSVD_ATTR_IN      (48'h000000000000),
        .SIM_CPLLREFCLK_SEL    (3'b001),
        .PMA_RSV_IN            (32'h00018480)
    ) gt0_gtwizard_0_i (
        .cpllrefclksel_in      (gt0_cpllrefclksel_in),
        .cpllfbclklost_out     (gt0_cpllfbclklost_out),
        .cplllock_out          (gt0_cplllock_i),
        .cplllockdetclk_in     (gt0_cplllockdetclk_in),
        .cpllpd_in             (gt0_cpllpd_i),
        .cpllrefclklost_out    (gt0_cpllrefclklost_i),
        .cpllreset_in          (gt0_cpllreset_i),
        .gtnorthrefclk0_in     (gt0_gtnorthrefclk0_in),
        .gtnorthrefclk1_in     (1'b0),
        .gtrefclk0_in          (gt0_gtrefclk0_in),
        .gtrefclk1_in          (gt0_gtrefclk1_in),
        .gtsouthrefclk0_in     (1'b0), .gtsouthrefclk1_in (1'b0),
        .drpaddr_in            (gt0_drpaddr_in), .drpclk_in (gt0_drpclk_in),
        .drpdi_in              (gt0_drpdi_in), .drpdo_out (gt0_drpdo_out),
        .drpen_in              (gt0_drpen_in), .drprdy_out (gt0_drprdy_out),
        .drpwe_in              (gt0_drpwe_in),
        .qpllclk_in            (gt0_qplloutclk_in),
        .qpllrefclk_in         (gt0_qplloutrefclk_in),
        .txsysclksel_in        (gt0_txsysclksel_in),
        .dmonitorout_out       (gt0_dmonitorout_out),
        .eyescanreset_in       (gt0_eyescanreset_in),
        .rxuserrdy_in          (gt0_rxuserrdy_i),
        .eyescandataerror_out  (gt0_eyescandataerror_out),
        .eyescantrigger_in     (gt0_eyescantrigger_in),
        .rxusrclk_in           (gt0_rxusrclk_in), .rxusrclk2_in (gt0_rxusrclk2_in),
        .rxdata_out            (gt0_rxdata_out),
        .gtxrxp_in             (gt0_gtxrxp_in), .gtxrxn_in (gt0_gtxrxn_in),
        .rxdfeagchold_in       (gt0_rxdfeagchold_i),
        .rxdfelfhold_in        (gt0_rxdfelfhold_i),
        .rxdfelpmreset_in      (gt0_rxdfelpmreset_in),
        .rxmonitorout_out      (gt0_rxmonitorout_out),
        .rxmonitorsel_in       (gt0_rxmonitorsel_in),
        .rxoutclk_out          (gt0_rxoutclk_i),
        .rxoutclkfabric_out    (gt0_rxoutclkfabric_out),
        .gtrxreset_in          (gt0_gtrxreset_i), .rxpmareset_in (gt0_rxpmareset_in),
        .rxresetdone_out       (gt0_rxresetdone_i),
        .gttxreset_in          (gt0_gttxreset_i), .txuserrdy_in (gt0_txuserrdy_i),
        .txusrclk_in           (gt0_txusrclk_in), .txusrclk2_in (gt0_txusrclk2_in),
        .txrate_in             (gt0_txrate_in), .txdata_in (gt0_txdata_in),
        .gtxtxn_out            (gt0_gtxtxn_out), .gtxtxp_out (gt0_gtxtxp_out),
        .txoutclk_out          (gt0_txoutclk_i),
        .txoutclkfabric_out    (gt0_txoutclkfabric_out),
        .txoutclkpcs_out       (gt0_txoutclkpcs_out),
        .txratedone_out        (gt0_txratedone_out),
        .txresetdone_out       (gt0_txresetdone_i)
    );

    gtwizard_0_cpll_railing #(.USE_BUFG(0)) cpll_railing0_i (
        .cpll_reset_out (gt0_cpllrail_reset_i), .cpll_pd_out (gt0_cpllpd_t),
        .refclk_out (), .refclk_in (gt0_gtrefclk0_in)
    );

    gtwizard_0_TX_STARTUP_FSM #(
        .EXAMPLE_SIMULATION(0), .STABLE_CLOCK_PERIOD(16),
        .RETRY_COUNTER_BITWIDTH(8), .TX_QPLL_USED("FALSE"),
        .RX_QPLL_USED("FALSE"), .PHASE_ALIGNMENT_MANUAL("FALSE")
    ) gt0_txresetfsm_i (
        .STABLE_CLOCK(sysclk_in), .TXUSERCLK(gt0_txusrclk_in),
        .SOFT_RESET(soft_reset_tx_in), .QPLLREFCLKLOST(tied_to_ground_i),
        .CPLLREFCLKLOST(gt0_cpllrefclklost_i), .QPLLLOCK(tied_to_vcc_i),
        .CPLLLOCK(gt0_cplllock_i), .TXRESETDONE(gt0_txresetdone_i),
        .MMCM_LOCK(gt0_tx_mmcm_lock_in), .GTTXRESET(gt0_gttxreset_t),
        .MMCM_RESET(gt0_tx_mmcm_reset_out), .QPLL_RESET(),
        .CPLL_RESET(gt0_cpllreset_t), .TX_FSM_RESET_DONE(gt0_tx_fsm_reset_done_out),
        .TXUSERRDY(gt0_txuserrdy_t), .RUN_PHALIGNMENT(), .RESET_PHALIGNMENT(),
        .PHALIGNMENT_DONE(tied_to_vcc_i), .RETRY_COUNTER()
    );

    gtwizard_0_RX_STARTUP_FSM #(
        .EXAMPLE_SIMULATION(0), .EQ_MODE("DFE"), .STABLE_CLOCK_PERIOD(16),
        .RETRY_COUNTER_BITWIDTH(8), .TX_QPLL_USED("FALSE"),
        .RX_QPLL_USED("FALSE"), .PHASE_ALIGNMENT_MANUAL("FALSE")
    ) gt0_rxresetfsm_i (
        .STABLE_CLOCK(sysclk_in), .RXUSERCLK(gt0_rxusrclk_in),
        .SOFT_RESET(soft_reset_rx_in),
        .DONT_RESET_ON_DATA_ERROR(dont_reset_on_data_error_in),
        .QPLLREFCLKLOST(tied_to_ground_i), .CPLLREFCLKLOST(gt0_cpllrefclklost_i),
        .QPLLLOCK(tied_to_vcc_i), .CPLLLOCK(gt0_cplllock_i),
        .RXRESETDONE(gt0_rxresetdone_i), .MMCM_LOCK(gt0_rx_mmcm_lock_in),
        .RECCLK_STABLE(gt0_recclk_stable_i), .RECCLK_MONITOR_RESTART(tied_to_ground_i),
        .DATA_VALID(gt0_data_valid_in), .TXUSERRDY(tied_to_vcc_i),
        .GTRXRESET(gt0_gtrxreset_t), .MMCM_RESET(gt0_rx_mmcm_reset_out),
        .QPLL_RESET(), .CPLL_RESET(), .RX_FSM_RESET_DONE(gt0_rx_fsm_reset_done_out),
        .RXUSERRDY(gt0_rxuserrdy_t), .RUN_PHALIGNMENT(), .RESET_PHALIGNMENT(),
        .PHALIGNMENT_DONE(tied_to_vcc_i), .RXDFEAGCHOLD(gt0_rxdfeagchold_i),
        .RXDFELFHOLD(gt0_rxdfelfhold_i), .RXLPMLFHOLD(gt0_rxlpmlfhold_i),
        .RXLPMHFHOLD(gt0_rxlpmhfhold_i), .RETRY_COUNTER()
    );

    always @(posedge sysclk_in) begin
        if (gt0_gtrxreset_i) begin
            gt0_rx_cdrlocked_reg <= 1'b0;
            gt0_rx_cdrlock_counter <= 18'd0;
        end else if (gt0_rx_cdrlock_counter == 18'd200000) begin
            gt0_rx_cdrlocked_reg <= 1'b1;
        end else begin
            gt0_rx_cdrlock_counter <= gt0_rx_cdrlock_counter + 1'b1;
        end
    end
endmodule

`default_nettype wire

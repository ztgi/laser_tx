`timescale 1ns/1ps

// GT TX profile for the single optical lane.
//
// The lane/refclk combination matches the local project_gtx reference:
// GTX lane X0Y8, local 125 MHz MGTREFCLK0, CPLL and a 64-bit TX user
// interface.  The initial power-up rate remains 0.5 Gb/s.  A deliberately
// narrow runtime switch path is added only for the already statically checked
// 500M <-> 1000M pair by changing TXOUT_DIV and the TX user-clock MMCM through
// DRP.  It does not implement wide-range rate planning, AD9528 control,
// 10G/QPLL support is intentionally not enabled in the rate table yet.  The
// wrapper now instantiates a QPLL-capable GTXE2_COMMON so the real QPLL clock,
// lock and reset path exist for the next-stage 10G architecture work, while
// the active validated CPLL profiles continue to select the CPLL path.
// The gtx_rate_channel instance is generated
// by the 7-series Transceiver Wizard XCI imported by
// scripts/add_gt_wizard_profile0.tcl.
module laser_gt_tx_profile0 (
    input  wire        ctrl_clk,
    input  wire        ctrl_rst,
    input  wire        gt_refclk125_p,
    input  wire        gt_refclk125_n,
    input  wire        ad9528_gtnorthrefclk0,
    input  wire [31:0] gpio_ctrl_axi,
    input  wire [31:0] gpio_status_axi,
    input  wire        dynamic_start,
    input  wire        dynamic_descriptor_valid,
    input  wire [2047:0] dynamic_words,
    input  wire        dynamic_refclk_ready,
    input  wire        dynamic_abort,
    input  wire        dynamic_rollback_ready,
    output wire        dynamic_prepared,
    output wire        dynamic_done,
    output wire        dynamic_error,
    output wire        dynamic_rollback_done,
    output wire        dynamic_verify_pass,
    output wire [7:0]  dynamic_failed_stage,
    output wire [7:0]  dynamic_state,
    input  wire [63:0] txdata_in,
    input  wire [63:0] valid_mask_in,
    output wire        txusrclk2_out,
    output wire        eom_clk_out,
    output wire [2:0]  eom_subdiv_log2_out,
    output wire        eom_clock_safe_out,
    output wire        tx_rst_out,
    output wire        gt_ready_out,
    output wire [31:0] gt_status_out,
    output wire [7:0]  dbg_rate_state,
    output wire [15:0] dbg_target_rate_mbps,
    output wire [15:0] dbg_current_rate_mbps,
    output wire        dbg_rate_error,
    output wire [7:0]  dbg_rate_error_code,
    output wire        dbg_gt_drp_write_attempted,
    output wire        dbg_mmcm_drp_write_attempted,
    output wire        dbg_gt_drp_busy,
    output wire        dbg_gt_drp_done,
    output wire        dbg_gt_drp_error,
    output wire        dbg_mmcm_drp_busy,
    output wire        dbg_mmcm_drp_done,
    output wire        dbg_mmcm_drp_error,
    output wire        dbg_txusrclk2_alive_axi,
    output wire [31:0] dbg_txusrclk2_freq_counter_axi,
    output wire        dbg_tx_quiesce_req,
    output wire        dbg_tx_idle_seen,
    output wire        dbg_apply_enable_blocked,
    output wire        dbg_tx_mmcm_reset_wizard,
    output wire        dbg_tx_mmcm_reset_rate,
    output wire        dbg_tx_mmcm_reset,
    output wire        dbg_tx_mmcm_locked_raw,
    output wire        dbg_tx_mmcm_locked_sync,
    output wire        dbg_rate_gt_tx_reset,
    output wire        dbg_gt0_gttxreset_effective,
    output wire        dbg_rate_txuserrdy_block,
    output wire        dbg_gt0_txuserrdy_effective,
    output wire        dbg_txresetdone_sync,
    output wire        dbg_gt_ready,
    output wire [6:0]  dbg_mmcm_drp_addr,
    output wire [15:0] dbg_mmcm_drp_di,
    output wire [15:0] dbg_mmcm_drp_do,
    output wire        dbg_mmcm_drp_en,
    output wire        dbg_mmcm_drp_we,
    output wire        dbg_mmcm_drp_rdy,
    output wire [8:0]  dbg_gt_drp_addr,
    output wire [15:0] dbg_gt_drp_di,
    output wire [15:0] dbg_gt_drp_do,
    output wire        dbg_gt_drp_en,
    output wire        dbg_gt_drp_we,
    output wire        dbg_gt_drp_rdy,
    output wire [15:0] dbg_gt_drp_readback_value,
    output wire        dbg_txoutclk_alive_axi,
    output wire [31:0] dbg_timeout_count,
    output wire        gtx_txp_out,
    output wire        gtx_txn_out
);
    localparam [2:0] GT_PROFILE_ID = 3'd0;
    localparam integer READY_STABLE_CYCLES = 64;
    localparam integer READY_COUNT_WIDTH = $clog2(READY_STABLE_CYCLES + 1);
    localparam integer TXUSRCLK2_FREQ_WIDTH = 32;
    localparam integer TXUSRCLK2_MEASURE_CYCLES = 50000;
    localparam integer TXOUTCLK_ALIVE_TIMEOUT_WIDTH = 8;
    // Static QPLL architecture-prep configuration for future 10.000G support:
    // 125 MHz REFCLK, QPLL_N/FBDIV=80, TXOUT_DIV=1.  qpll_selected remains
    // held at 0 in this stage, so existing supported profiles still use CPLL.
    localparam integer QPLL_FBDIV_TOP = 80;
    localparam [9:0] QPLL_FBDIV_IN =
        (QPLL_FBDIV_TOP == 16)  ? 10'b0000100000 :
        (QPLL_FBDIV_TOP == 20)  ? 10'b0000110000 :
        (QPLL_FBDIV_TOP == 32)  ? 10'b0001100000 :
        (QPLL_FBDIV_TOP == 40)  ? 10'b0010000000 :
        (QPLL_FBDIV_TOP == 64)  ? 10'b0011100000 :
        (QPLL_FBDIV_TOP == 66)  ? 10'b0101000000 :
        (QPLL_FBDIV_TOP == 80)  ? 10'b0100100000 :
        (QPLL_FBDIV_TOP == 100) ? 10'b0101110000 : 10'b0000000000;
    localparam QPLL_FBDIV_RATIO = (QPLL_FBDIV_TOP == 66) ? 1'b0 : 1'b1;

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
    wire tied_to_ground = 1'b0;
    wire tied_to_vcc = 1'b1;
    wire txoutclk;
    wire txoutclk_dbg;
    wire txusrclk;
    wire txusrclk2;
    wire eom_clk;
    wire [2:0] eom_subdiv_log2;
    wire tx_mmcm_reset_wizard;
    wire tx_mmcm_reset_rate;
    wire tx_mmcm_reset;
    wire tx_mmcm_locked;
    wire txresetdone;
    wire cplllock;
    (* mark_debug = "true", keep = "true" *) wire qplllock;
    (* mark_debug = "true", keep = "true" *) wire qpllrefclklost;
    (* mark_debug = "true", keep = "true" *) wire qplloutclk;
    (* mark_debug = "true", keep = "true" *) wire qplloutrefclk;
    (* mark_debug = "true", keep = "true" *) wire qpllreset_ctrl;
    (* mark_debug = "true", keep = "true" *) wire qpllpd_ctrl;
    (* mark_debug = "true", keep = "true" *) wire [1:0] gt0_txsysclksel_effective;
    (* mark_debug = "true", keep = "true" *) wire qpll_selected;
    (* mark_debug = "true", keep = "true" *) wire refclk_north_selected;
    wire [2:0] gt0_refclksel_effective = refclk_north_selected ? 3'b011 : 3'b001;
    wire [15:0] qpll_drpdo_unused;
    wire qpll_drprdy_unused;
    wire qpllfbclklost_unused;
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
    wire [15:0] gt_drpdo;
    wire gt_drprdy;
    wire [8:0] gt_drpaddr;
    wire [15:0] gt_drpdi;
    wire gt_drpen;
    wire gt_drpwe;
    wire [6:0] mmcm_drpaddr;
    wire [15:0] mmcm_drpdi;
    wire [15:0] mmcm_drpdo;
    wire mmcm_drpen;
    wire mmcm_drpwe;
    wire mmcm_drprdy;
    wire rate_gt_tx_reset;
    wire rate_txuserrdy_block;
    (* mark_debug = "true" *) wire rate_cpll_reset;
    (* mark_debug = "true" *) wire rate_qpll_reset;
    wire apply_enable_blocked;

    (* mark_debug = "true" *) wire [7:0] rate_state;
    (* mark_debug = "true" *) wire [15:0] target_rate_mbps;
    (* mark_debug = "true" *) wire [15:0] current_rate_mbps;
    (* mark_debug = "true" *) wire [3:0] current_rate_id;
    (* mark_debug = "true" *) wire rate_busy;
    (* mark_debug = "true" *) wire rate_done;
    (* mark_debug = "true" *) wire rate_error;
    (* mark_debug = "true" *) wire already_current_rate;
    (* mark_debug = "true" *) wire [7:0] rate_error_code;
    (* mark_debug = "true" *) wire gt_drp_busy;
    (* mark_debug = "true" *) wire gt_drp_done;
    (* mark_debug = "true" *) wire gt_drp_error;
    (* mark_debug = "true" *) wire gt_drp_write_attempted;
    (* mark_debug = "true" *) wire [15:0] gt_drp_readback_value;
    (* mark_debug = "true" *) wire mmcm_drp_busy;
    (* mark_debug = "true" *) wire mmcm_drp_done;
    (* mark_debug = "true" *) wire mmcm_drp_error;
    (* mark_debug = "true" *) wire mmcm_drp_write_attempted;
    (* mark_debug = "true" *) wire tx_quiesce_req;
    (* mark_debug = "true" *) wire tx_idle_seen;
    (* mark_debug = "true" *) wire [1:0] target_pll_type_dbg;
    (* mark_debug = "true" *) wire [1:0] active_pll_type_dbg;
    (* mark_debug = "true" *) wire [1:0] programmed_pll_type_dbg;
    wire [31:0] dbg_rate_timeout_count;

    (* ASYNC_REG = "TRUE" *) reg cplllock_meta;
    (* ASYNC_REG = "TRUE" *) reg cplllock_sync;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg qplllock_meta;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg qplllock_sync;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg qpllrefclklost_meta;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg qpllrefclklost_sync;
    (* ASYNC_REG = "TRUE" *) reg tx_mmcm_locked_meta;
    (* ASYNC_REG = "TRUE" *) reg tx_mmcm_locked_sync;
    (* ASYNC_REG = "TRUE" *) reg txresetdone_meta;
    (* ASYNC_REG = "TRUE" *) reg txresetdone_sync;
    reg [READY_COUNT_WIDTH-1:0] ready_count;
    reg gt_ready_ctrl;

    (* ASYNC_REG = "TRUE" *) reg gt_ready_meta_tx;
    (* ASYNC_REG = "TRUE" *) reg gt_ready_tx;
    reg [23:0] tx_word_count;
    reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_tx;
    wire [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_gray_tx =
        txusrclk2_counter_tx ^ (txusrclk2_counter_tx >> 1);

    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_gray_meta_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_gray_sync_axi;
    reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_bin_axi;
    reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_counter_bin_prev_axi;
    reg [15:0] txusrclk2_measure_count_axi;
    (* mark_debug = "true" *) reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_freq_counter_axi;
    reg [TXUSRCLK2_FREQ_WIDTH-1:0] txusrclk2_freq_counter_prev_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg txusrclk2_toggle_meta_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg txusrclk2_toggle_axi;
    (* mark_debug = "true" *) reg txusrclk2_alive_axi;
    reg [7:0] txusrclk2_alive_timeout_axi;

    reg txoutclk_toggle_txout;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg txoutclk_toggle_meta_axi;
    (* ASYNC_REG = "TRUE", mark_debug = "true" *) reg txoutclk_toggle_axi;
    reg txoutclk_toggle_prev_axi;
    (* mark_debug = "true" *) reg txoutclk_alive_axi;
    reg [TXOUTCLK_ALIVE_TIMEOUT_WIDTH-1:0] txoutclk_alive_timeout_axi;

    IBUFDS_GTE2 u_refclk125_ibuf (
        .I(gt_refclk125_p),
        .IB(gt_refclk125_n),
        .CEB(1'b0),
        .O(gtrefclk125),
        .ODIV2(gtrefclk125_div2_unused)
    );

    // QPLL architecture preparation.
    //
    // The rate controller owns the qpll_selected/qpllreset control points so
    // the PLL-source state semantics are no longer hard-wired constants.
    // Existing CPLL profiles still return PLL_TYPE_CPLL; RATE_ID_10000M is the
    // only profile that selects the QPLL path.
    assign qpllreset_ctrl = ctrl_rst | rate_qpll_reset;
    assign qpllpd_ctrl = 1'b0;
    assign gt0_txsysclksel_effective = qpll_selected ? 2'b11 : 2'b00;

    GTXE2_COMMON #(
        .SIM_RESET_SPEEDUP        ("FALSE"),
        .SIM_QPLLREFCLK_SEL       (3'b001),
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
        .QPLL_FBDIV               (QPLL_FBDIV_IN),
        .QPLL_FBDIV_MONITOR_EN    (1'b0),
        .QPLL_FBDIV_RATIO         (QPLL_FBDIV_RATIO),
        .QPLL_INIT_CFG            (24'h000006),
        .QPLL_LOCK_CFG            (16'h21E8),
        .QPLL_LPF                 (4'b1111),
        .QPLL_REFCLK_DIV          (1)
    ) u_gtxe2_common_qpll (
        .DRPADDR                  (8'd0),
        .DRPCLK                   (ctrl_clk),
        .DRPDI                    (16'd0),
        .DRPDO                    (qpll_drpdo_unused),
        .DRPEN                    (1'b0),
        .DRPRDY                   (qpll_drprdy_unused),
        .DRPWE                    (1'b0),
        .GTGREFCLK                (tied_to_ground),
        .GTNORTHREFCLK0           (ad9528_gtnorthrefclk0),
        .GTNORTHREFCLK1           (tied_to_ground),
        .GTREFCLK0                (gtrefclk125),
        .GTREFCLK1                (tied_to_ground),
        .GTSOUTHREFCLK0           (tied_to_ground),
        .GTSOUTHREFCLK1           (tied_to_ground),
        .QPLLDMONITOR             (),
        .QPLLOUTCLK               (qplloutclk),
        .QPLLOUTREFCLK            (qplloutrefclk),
        .REFCLKOUTMONITOR         (),
        .QPLLFBCLKLOST            (qpllfbclklost_unused),
        .QPLLLOCK                 (qplllock),
        .QPLLLOCKDETCLK           (ctrl_clk),
        .QPLLLOCKEN               (tied_to_vcc),
        .QPLLOUTRESET             (tied_to_ground),
        .QPLLPD                   (qpllpd_ctrl),
        .QPLLREFCLKLOST           (qpllrefclklost),
        .QPLLREFCLKSEL            (gt0_refclksel_effective),
        .QPLLRESET                (qpllreset_ctrl),
        .QPLLRSVD1                (16'b0000000000000000),
        .QPLLRSVD2                (5'b11111),
        .BGBYPASSB                (tied_to_vcc),
        .BGMONITORENB             (tied_to_vcc),
        .BGPDB                    (tied_to_vcc),
        .BGRCALOVRD               (5'b11111),
        .PMARSVD                  (8'b00000000),
        .RCALENB                  (tied_to_vcc)
    );


    // Debug-only TXOUTCLK alive monitor.  GTX TXOUTCLK is not allowed to drive
    // fabric FFs directly, so this monitor uses a dedicated BUFG before the
    // toggle generator.  The functional TXUSRCLK/TXUSRCLK2 path remains in
    // laser_gt_usrclk_profile0 and is not changed by this debug clock.
    BUFG u_txoutclk_debug_bufg (
        .I(txoutclk),
        .O(txoutclk_dbg)
    );
    laser_gt_usrclk_profile0 u_tx_usrclk_profile0 (
        .txoutclk_in     (txoutclk),
        .mmcm_reset_in   (tx_mmcm_reset),
        .mmcm_daddr_in   (mmcm_drpaddr),
        .mmcm_dclk_in    (ctrl_clk),
        .mmcm_den_in     (mmcm_drpen),
        .mmcm_di_in      (mmcm_drpdi),
        .mmcm_do_out     (mmcm_drpdo),
        .mmcm_drdy_out   (mmcm_drprdy),
        .mmcm_dwe_in     (mmcm_drpwe),
        .txusrclk_out    (txusrclk),
        .txusrclk2_out   (txusrclk2),
        .eom_clk_out      (eom_clk),
        .mmcm_locked_out (tx_mmcm_locked)
    );

    assign txusrclk2_out = txusrclk2;
    assign eom_clk_out = eom_clk;
    assign eom_subdiv_log2_out = eom_subdiv_log2;
    assign eom_clock_safe_out = tx_mmcm_locked;
    assign tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate;
    wire gt_ready_effective_ctrl = gt_ready_ctrl & ~rate_busy & ~rate_error;
    wire selected_pll_lock_sync = qpll_selected ?
                                  (qplllock_sync & ~qpllrefclklost_sync) :
                                  cplllock_sync;
    wire gt0_gttxreset_effective = ctrl_rst | rate_gt_tx_reset | ~selected_pll_lock_sync;
    wire gt0_txuserrdy_effective = ~ctrl_rst & ~rate_txuserrdy_block &
                                    selected_pll_lock_sync & tx_mmcm_locked_sync;

    // Debug-only AXI/FCLK-domain mirrors for the BD AXI ILA. These outputs do
    // not feed back into the rate controller or GT datapath.
    assign dbg_rate_state                  = rate_state;
    assign dbg_target_rate_mbps            = target_rate_mbps;
    assign dbg_current_rate_mbps           = current_rate_mbps;
    assign dbg_rate_error                  = rate_error;
    assign dbg_rate_error_code             = rate_error_code;
    assign dbg_gt_drp_write_attempted      = gt_drp_write_attempted;
    assign dbg_mmcm_drp_write_attempted    = mmcm_drp_write_attempted;
    assign dbg_gt_drp_busy                 = gt_drp_busy;
    assign dbg_gt_drp_done                 = gt_drp_done;
    assign dbg_gt_drp_error                = gt_drp_error;
    assign dbg_mmcm_drp_busy               = mmcm_drp_busy;
    assign dbg_mmcm_drp_done               = mmcm_drp_done;
    assign dbg_mmcm_drp_error              = mmcm_drp_error;
    assign dbg_txusrclk2_alive_axi         = txusrclk2_alive_axi;
    assign dbg_txusrclk2_freq_counter_axi  = txusrclk2_freq_counter_axi;
    assign dbg_tx_quiesce_req              = tx_quiesce_req;
    assign dbg_tx_idle_seen                = tx_idle_seen;
    assign dbg_apply_enable_blocked        = apply_enable_blocked;
    assign dbg_tx_mmcm_reset_wizard        = tx_mmcm_reset_wizard;
    assign dbg_tx_mmcm_reset_rate          = tx_mmcm_reset_rate;
    assign dbg_tx_mmcm_reset               = tx_mmcm_reset;
    assign dbg_tx_mmcm_locked_raw          = tx_mmcm_locked;
    assign dbg_tx_mmcm_locked_sync         = tx_mmcm_locked_sync;
    assign dbg_rate_gt_tx_reset            = rate_gt_tx_reset;
    assign dbg_gt0_gttxreset_effective     = gt0_gttxreset_effective;
    assign dbg_rate_txuserrdy_block        = rate_txuserrdy_block;
    assign dbg_gt0_txuserrdy_effective     = gt0_txuserrdy_effective;
    assign dbg_txresetdone_sync            = txresetdone_sync;
    assign dbg_gt_ready                    = gt_ready_ctrl;
    assign dbg_mmcm_drp_addr               = mmcm_drpaddr;
    assign dbg_mmcm_drp_di                 = mmcm_drpdi;
    assign dbg_mmcm_drp_do                 = mmcm_drpdo;
    assign dbg_mmcm_drp_en                 = mmcm_drpen;
    assign dbg_mmcm_drp_we                 = mmcm_drpwe;
    assign dbg_mmcm_drp_rdy                = mmcm_drprdy;
    assign dbg_gt_drp_addr                 = gt_drpaddr;
    assign dbg_gt_drp_di                   = gt_drpdi;
    assign dbg_gt_drp_do                   = gt_drpdo;
    assign dbg_gt_drp_en                   = gt_drpen;
    assign dbg_gt_drp_we                   = gt_drpwe;
    assign dbg_gt_drp_rdy                  = gt_drprdy;
    assign dbg_gt_drp_readback_value       = gt_drp_readback_value;
    assign dbg_txoutclk_alive_axi          = txoutclk_alive_axi;
    // Probe49 of the AXI/FCLK ILA remains 32-bit wide and is reused as a
    // debug-only PLL/QPLL status bus to avoid changing the BD ILA probe count.
    // [15:0]  = low bits of the common rate-switch timeout counter
    // [16]    = qpll_selected, the real PLL-source select driving TXSYSCLKSEL
    // [17]    = synchronized QPLLLOCK
    // [18]    = synchronized QPLLREFCLKLOST
    // [20:19] = effective TXSYSCLKSEL delivered to the GT channel
    // [22:21] = active_pll_type, updated only after VERIFY_RATE succeeds
    // [24:23] = programmed_pll_type, latest actual PLL source selection
    // [26:25] = target_pll_type, current request target PLL type
    // [27]    = qpllreset_ctrl
    // [28]    = synchronized CPLLLOCK
    // [31:29] = reserved
    assign dbg_timeout_count = {
        3'b000,
        cplllock_sync,
        qpllreset_ctrl,
        target_pll_type_dbg,
        programmed_pll_type_dbg,
        active_pll_type_dbg,
        gt0_txsysclksel_effective,
        qpllrefclklost_sync,
        qplllock_sync,
        qpll_selected,
        dbg_rate_timeout_count[15:0]
    };

    laser_gt_rate_control_mux u_rate_switch_500m_1000m (
        .clk                         (ctrl_clk),
        .rst                         (ctrl_rst),
        .gpio_ctrl                   (gpio_ctrl_axi),
        .gpio_status                 (gpio_status_axi),
        .dynamic_start               (dynamic_start),
        .dynamic_descriptor_valid    (dynamic_descriptor_valid),
        .dynamic_words               (dynamic_words),
        .dynamic_refclk_ready        (dynamic_refclk_ready),
        .dynamic_abort               (dynamic_abort),
        .dynamic_rollback_ready      (dynamic_rollback_ready),
        .dynamic_prepared            (dynamic_prepared),
        .dynamic_done                (dynamic_done),
        .dynamic_error               (dynamic_error),
        .dynamic_rollback_done       (dynamic_rollback_done),
        .dynamic_verify_pass         (dynamic_verify_pass),
        .dynamic_failed_stage        (dynamic_failed_stage),
        .dynamic_state               (dynamic_state),
        .cplllock_sync               (cplllock_sync),
        .qplllock_sync               (qplllock_sync),
        .qpllrefclklost_sync         (qpllrefclklost_sync),
        .txresetdone_sync            (txresetdone_sync),
        .tx_mmcm_locked_sync         (tx_mmcm_locked_sync),
        .gt_ready_ctrl               (gt_ready_ctrl),
        .txusrclk2_alive_axi         (txusrclk2_alive_axi),
        .txusrclk2_freq_counter_axi  (txusrclk2_freq_counter_axi),
        .rate_gt_tx_reset            (rate_gt_tx_reset),
        .rate_txuserrdy_block        (rate_txuserrdy_block),
        .rate_mmcm_reset             (tx_mmcm_reset_rate),
        .rate_cpll_reset             (rate_cpll_reset),
        .rate_qpll_reset             (rate_qpll_reset),
        .qpll_selected               (qpll_selected),
        .refclk_north_selected       (refclk_north_selected),
        .apply_enable_blocked        (apply_enable_blocked),
        .gt_drp_addr                 (gt_drpaddr),
        .gt_drp_di                   (gt_drpdi),
        .gt_drp_do                   (gt_drpdo),
        .gt_drp_en                   (gt_drpen),
        .gt_drp_we                   (gt_drpwe),
        .gt_drp_rdy                  (gt_drprdy),
        .mmcm_drp_addr               (mmcm_drpaddr),
        .mmcm_drp_di                 (mmcm_drpdi),
        .mmcm_drp_do                 (mmcm_drpdo),
        .mmcm_drp_en                 (mmcm_drpen),
        .mmcm_drp_we                 (mmcm_drpwe),
        .mmcm_drp_rdy                (mmcm_drprdy),
        .rate_state                  (rate_state),
        .target_rate_mbps            (target_rate_mbps),
        .current_rate_mbps           (current_rate_mbps),
        .current_rate_id             (current_rate_id),
        .target_pll_type_dbg         (target_pll_type_dbg),
        .active_pll_type_dbg         (active_pll_type_dbg),
        .programmed_pll_type_dbg     (programmed_pll_type_dbg),
        .rate_busy                   (rate_busy),
        .rate_done                   (rate_done),
        .rate_error                  (rate_error),
        .already_current_rate        (already_current_rate),
        .rate_error_code             (rate_error_code),
        .gt_drp_busy                 (gt_drp_busy),
        .gt_drp_done                 (gt_drp_done),
        .gt_drp_error                (gt_drp_error),
        .gt_drp_write_attempted      (gt_drp_write_attempted),
        .gt_drp_readback_value       (gt_drp_readback_value),
        .mmcm_drp_busy               (mmcm_drp_busy),
        .mmcm_drp_done               (mmcm_drp_done),
        .mmcm_drp_error              (mmcm_drp_error),
        .mmcm_drp_write_attempted    (mmcm_drp_write_attempted),
        .tx_quiesce_req              (tx_quiesce_req),
        .tx_idle_seen                (tx_idle_seen),
        .dbg_timeout_count           (dbg_rate_timeout_count),
        .eom_subdiv_log2             (eom_subdiv_log2)
    );

    always @(posedge ctrl_clk) begin
        if (ctrl_rst) begin
            cplllock_meta   <= 1'b0;
            cplllock_sync   <= 1'b0;
            qplllock_meta   <= 1'b0;
            qplllock_sync   <= 1'b0;
            qpllrefclklost_meta <= 1'b0;
            qpllrefclklost_sync <= 1'b0;
            tx_mmcm_locked_meta <= 1'b0;
            tx_mmcm_locked_sync <= 1'b0;
            txresetdone_meta <= 1'b0;
            txresetdone_sync <= 1'b0;
            ready_count      <= {READY_COUNT_WIDTH{1'b0}};
            gt_ready_ctrl    <= 1'b0;
            txusrclk2_counter_gray_meta_axi <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_counter_gray_sync_axi <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_counter_bin_axi       <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_counter_bin_prev_axi  <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_measure_count_axi     <= 16'd0;
            txusrclk2_freq_counter_axi      <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_freq_counter_prev_axi <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
            txusrclk2_toggle_meta_axi       <= 1'b0;
            txusrclk2_toggle_axi            <= 1'b0;
            txusrclk2_alive_axi             <= 1'b0;
            txusrclk2_alive_timeout_axi     <= 8'hff;
            txoutclk_toggle_meta_axi        <= 1'b0;
            txoutclk_toggle_axi             <= 1'b0;
            txoutclk_toggle_prev_axi        <= 1'b0;
            txoutclk_alive_axi              <= 1'b0;
            txoutclk_alive_timeout_axi      <= {TXOUTCLK_ALIVE_TIMEOUT_WIDTH{1'b1}};
        end else begin
            cplllock_meta    <= cplllock;
            cplllock_sync    <= cplllock_meta;
            qplllock_meta    <= qplllock;
            qplllock_sync    <= qplllock_meta;
            qpllrefclklost_meta <= qpllrefclklost;
            qpllrefclklost_sync <= qpllrefclklost_meta;
            tx_mmcm_locked_meta <= tx_mmcm_locked;
            tx_mmcm_locked_sync <= tx_mmcm_locked_meta;
            txresetdone_meta <= txresetdone;
            txresetdone_sync <= txresetdone_meta;
            txusrclk2_counter_gray_meta_axi <= txusrclk2_counter_gray_tx;
            txusrclk2_counter_gray_sync_axi <= txusrclk2_counter_gray_meta_axi;
            txusrclk2_counter_bin_axi       <= gray_to_bin(txusrclk2_counter_gray_sync_axi);
            txusrclk2_toggle_meta_axi       <= txusrclk2_counter_tx[8];
            txusrclk2_toggle_axi            <= txusrclk2_toggle_meta_axi;
            txoutclk_toggle_meta_axi        <= txoutclk_toggle_txout;
            txoutclk_toggle_axi             <= txoutclk_toggle_meta_axi;
            if (txoutclk_toggle_axi != txoutclk_toggle_prev_axi) begin
                txoutclk_alive_axi <= 1'b1;
                txoutclk_alive_timeout_axi <= {TXOUTCLK_ALIVE_TIMEOUT_WIDTH{1'b0}};
                txoutclk_toggle_prev_axi <= txoutclk_toggle_axi;
            end else if (txoutclk_alive_timeout_axi == {TXOUTCLK_ALIVE_TIMEOUT_WIDTH{1'b1}}) begin
                txoutclk_alive_axi <= 1'b0;
            end else begin
                txoutclk_alive_timeout_axi <= txoutclk_alive_timeout_axi + 1'b1;
            end
            if (txusrclk2_counter_bin_axi != txusrclk2_freq_counter_prev_axi) begin
                txusrclk2_alive_axi <= 1'b1;
                txusrclk2_alive_timeout_axi <= 8'd0;
                txusrclk2_freq_counter_prev_axi <= txusrclk2_counter_bin_axi;
            end else if (txusrclk2_alive_timeout_axi == 8'hff) begin
                txusrclk2_alive_axi <= 1'b0;
            end else begin
                txusrclk2_alive_timeout_axi <= txusrclk2_alive_timeout_axi + 1'b1;
            end
            if (txusrclk2_measure_count_axi == TXUSRCLK2_MEASURE_CYCLES - 1) begin
                txusrclk2_measure_count_axi <= 16'd0;
                txusrclk2_freq_counter_axi <=
                    txusrclk2_counter_bin_axi - txusrclk2_counter_bin_prev_axi;
                txusrclk2_counter_bin_prev_axi <= txusrclk2_counter_bin_axi;
            end else begin
                txusrclk2_measure_count_axi <= txusrclk2_measure_count_axi + 1'b1;
            end
            if (!selected_pll_lock_sync || !tx_mmcm_locked_sync || !txresetdone_sync) begin
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

    always @(posedge txoutclk_dbg or posedge ctrl_rst) begin
        if (ctrl_rst) begin
            txoutclk_toggle_txout <= 1'b0;
        end else begin
            txoutclk_toggle_txout <= ~txoutclk_toggle_txout;
        end
    end

    always @(posedge txusrclk2) begin
        if (ctrl_rst) begin
            gt_ready_meta_tx <= 1'b0;
            gt_ready_tx      <= 1'b0;
            tx_word_count    <= 24'd0;
            txusrclk2_counter_tx <= {TXUSRCLK2_FREQ_WIDTH{1'b0}};
        end else begin
            gt_ready_meta_tx <= gt_ready_effective_ctrl;
            gt_ready_tx      <= gt_ready_meta_tx;
            txusrclk2_counter_tx <= txusrclk2_counter_tx + 1'b1;
            if (!gt_ready_tx) begin
                tx_word_count <= 24'd0;
            end else if (|valid_mask_in) begin
                tx_word_count <= tx_word_count + 1'b1;
            end
        end
    end

    // The core stays reset until the GT user clock, CPLL and TX reset-done
    // indications have been stable for READY_STABLE_CYCLES ctrl_clk cycles.
    assign tx_rst_out   = ~gt_ready_tx;
    assign gt_ready_out = gt_ready_tx;

    gtwizard_0_adapter u_gtwizard_0 (
        .sysclk_in                    (ctrl_clk),
        .soft_reset_tx_in             (ctrl_rst | rate_gt_tx_reset),
        .soft_reset_rx_in             (1'b1),
        .dont_reset_on_data_error_in  (1'b1),
        .gt0_tx_fsm_reset_done_out    (tx_fsm_reset_done),
        .gt0_rx_fsm_reset_done_out    (),
        .gt0_data_valid_in            (1'b1),
        .gt0_tx_mmcm_lock_in          (tx_mmcm_locked),
        .gt0_tx_mmcm_reset_out        (tx_mmcm_reset_wizard),
        .gt0_rx_mmcm_lock_in          (1'b1),
        .gt0_rx_mmcm_reset_out        (),
        .gt0_cpllfbclklost_out        (cpllfbclklost_unused),
        .gt0_cplllock_out             (cplllock),
        .gt0_cplllockdetclk_in        (ctrl_clk),
        .gt0_cpllpd_in                (1'b0),
        .gt0_cpllreset_in             (ctrl_rst | rate_cpll_reset),
        .gt0_gtrefclk0_in             (gtrefclk125),
        .gt0_gtrefclk1_in             (1'b0),
        .gt0_gtnorthrefclk0_in        (ad9528_gtnorthrefclk0),
        .gt0_cpllrefclksel_in         (gt0_refclksel_effective),
        .gt0_drpaddr_in               (gt_drpaddr),
        .gt0_drpclk_in                (ctrl_clk),
        .gt0_drpdi_in                 (gt_drpdi),
        .gt0_drpdo_out                (gt_drpdo),
        .gt0_drpen_in                 (gt_drpen),
        .gt0_drprdy_out               (gt_drprdy),
        .gt0_drpwe_in                 (gt_drpwe),
        .gt0_txsysclksel_in           (gt0_txsysclksel_effective),
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
        .gt0_gttxreset_in             (gt0_gttxreset_effective),
        .gt0_txuserrdy_in             (gt0_txuserrdy_effective),
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
        .gt0_qplloutclk_in            (qplloutclk),
        .gt0_qplloutrefclk_in         (qplloutrefclk)
    );

    assign txresetdone = txresetdone_native & tx_fsm_reset_done;

    // Software-visible GT/rate status. Existing laser gpio_status is
    // intentionally left unchanged.
    assign gt_status_out = {
        rate_error_code,
        rate_state,
        mmcm_drp_write_attempted,
        gt_drp_write_attempted,
        mmcm_drp_done,
        gt_drp_done,
        rate_error,
        rate_busy,
        rate_done,
        already_current_rate,
        current_rate_id,
        ctrl_rst,
        gt_ready_tx,
        txresetdone_sync,
        selected_pll_lock_sync
    };
endmodule




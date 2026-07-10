`timescale 1ns/1ps

// Minimal TX-only dynamic rate switch controller for the already validated
// 500M Profile0 <-> 1000M Profile1 <-> 2000M Profile2 set, plus the
// first 125 MHz-refclk CPLL-parameter-changing 1250M/2500M/3125M/5000M/6250M profiles.
//
// This module intentionally supports only fixed, explicitly reviewed profiles.
// It does not touch RXOUT_DIV, QPLL, AD9528 or any wide-range/refclk switching
// fields.  The GTXE2 and MMCME2 DRP tables are taken from
// docs/debug_reports/06_drp_parameter_confirmation_for_500m_1000m.md.
//
// Level-3 profile-table refactor note:
// The current implementation supports only the validated 500M/1000M/2000M
// set and the first CPLL-parameter-changing 1250M/2500M/3125M/5000M/6250M candidates on the existing
// 125 MHz refclk.  The profile accessors below collect rate-specific
// parameters in one place so the FSM acts as a common Rate Switch Executor.
// Reserved profile fields such as refclk_id and flags remain constant; they
// document that AD9528/refclk dynamic switching is not implemented in this
// stage.
module laser_gt_rate_switch_500m_1000m #(
    parameter integer RESET_HOLD_CYCLES      = 1024,
    parameter integer TX_QUIESCE_TIMEOUT     = 1000000,
    parameter integer DRP_TIMEOUT_CYCLES     = 4096,
    parameter integer LOCK_TIMEOUT_CYCLES    = 5000000,
    parameter integer VERIFY_SETTLE_CYCLES   = 100000,
    parameter integer FREQ_500M_MIN_COUNT    = 7700,
    parameter integer FREQ_500M_MAX_COUNT    = 7950,
    parameter integer FREQ_1000M_MIN_COUNT   = 15400,
    parameter integer FREQ_1000M_MAX_COUNT   = 15900,
    parameter integer FREQ_1250M_MIN_COUNT   = 19200,
    parameter integer FREQ_1250M_MAX_COUNT   = 19850,
    parameter integer FREQ_2000M_MIN_COUNT   = 30800,
    parameter integer FREQ_2000M_MAX_COUNT   = 31800,
    parameter integer FREQ_2500M_MIN_COUNT   = 38400,
    parameter integer FREQ_2500M_MAX_COUNT   = 39750,
    parameter integer FREQ_3125M_MIN_COUNT   = 48000,
    parameter integer FREQ_3125M_MAX_COUNT   = 49700,
    parameter integer FREQ_5000M_MIN_COUNT   = 76800,
    parameter integer FREQ_5000M_MAX_COUNT   = 79500,
    parameter integer FREQ_6250M_MIN_COUNT   = 96000,
    parameter integer FREQ_6250M_MAX_COUNT   = 99500
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] gpio_ctrl,
    input  wire [31:0] gpio_status,

    input  wire        cplllock_sync,
    input  wire        txresetdone_sync,
    input  wire        tx_mmcm_locked_sync,
    input  wire        gt_ready_ctrl,
    input  wire        txusrclk2_alive_axi,
    input  wire [31:0] txusrclk2_freq_counter_axi,

    output reg         rate_gt_tx_reset,
    output reg         rate_txuserrdy_block,
    output reg         rate_mmcm_reset,
    output reg         rate_cpll_reset,
    output reg         apply_enable_blocked,

    output reg  [8:0]  gt_drp_addr,
    output reg  [15:0] gt_drp_di,
    input  wire [15:0] gt_drp_do,
    output reg         gt_drp_en,
    output reg         gt_drp_we,
    input  wire        gt_drp_rdy,

    output reg  [6:0]  mmcm_drp_addr,
    output reg  [15:0] mmcm_drp_di,
    input  wire [15:0] mmcm_drp_do,
    output reg         mmcm_drp_en,
    output reg         mmcm_drp_we,
    input  wire        mmcm_drp_rdy,

    (* mark_debug = "true" *) output reg  [7:0]  rate_state,
    (* mark_debug = "true" *) output reg  [15:0] target_rate_mbps,
    (* mark_debug = "true" *) output reg  [15:0] current_rate_mbps,
    (* mark_debug = "true" *) output reg  [3:0]  current_rate_id,
    (* mark_debug = "true" *) output reg         rate_busy,
    (* mark_debug = "true" *) output reg         rate_done,
    (* mark_debug = "true" *) output reg         rate_error,
    (* mark_debug = "true" *) output reg         already_current_rate,
    (* mark_debug = "true" *) output reg  [7:0]  rate_error_code,

    (* mark_debug = "true" *) output reg         gt_drp_busy,
    (* mark_debug = "true" *) output reg         gt_drp_done,
    (* mark_debug = "true" *) output reg         gt_drp_error,
    (* mark_debug = "true" *) output reg         gt_drp_write_attempted,
    (* mark_debug = "true" *) output reg  [15:0] gt_drp_readback_value,

    (* mark_debug = "true" *) output reg         mmcm_drp_busy,
    (* mark_debug = "true" *) output reg         mmcm_drp_done,
    (* mark_debug = "true" *) output reg         mmcm_drp_error,
    (* mark_debug = "true" *) output reg         mmcm_drp_write_attempted,

    (* mark_debug = "true" *) output reg         tx_quiesce_req,
    (* mark_debug = "true" *) output reg         tx_idle_seen,

    // Debug-only mirror of the common timeout/wait counter. This does not
    // feed back into the state machine; it is only exported to the AXI/FCLK
    // ILA so RATE_WAIT_LOCK progress can be correlated with lock/reset state.
    (* mark_debug = "true" *) output wire [31:0] dbg_timeout_count
);

    localparam [7:0] RATE_IDLE             = 8'h00;
    localparam [7:0] RATE_REQUEST          = 8'h01;
    localparam [7:0] RATE_VALIDATE         = 8'h02;
    localparam [7:0] RATE_QUIESCE_TX       = 8'h03;
    localparam [7:0] RATE_ASSERT_RESET     = 8'h04;
    localparam [7:0] RATE_PROGRAM_GT_DRP   = 8'h05;
    localparam [7:0] RATE_PROGRAM_MMCM_DRP = 8'h06;
    localparam [7:0] RATE_RELEASE_RESET    = 8'h07;
    localparam [7:0] RATE_WAIT_LOCK        = 8'h08;
    localparam [7:0] RATE_VERIFY_RATE      = 8'h09;
    localparam [7:0] RATE_DONE             = 8'h0a;
    localparam [7:0] RATE_WAIT_MMCM_RESET_RELEASE = 8'h0b;
    localparam [7:0] RATE_ERROR            = 8'h80;

    localparam [7:0] RATE_ERR_NONE                         = 8'h00;
    localparam [7:0] RATE_ERR_UNSUPPORTED_RATE             = 8'h01;
    localparam [7:0] RATE_ERR_TX_QUIESCE_TIMEOUT           = 8'h02;
    localparam [7:0] RATE_ERR_GT_DRP_TIMEOUT               = 8'h03;
    localparam [7:0] RATE_ERR_GT_DRP_READBACK_MISMATCH     = 8'h04;
    localparam [7:0] RATE_ERR_MMCM_DRP_TIMEOUT             = 8'h05;
    localparam [7:0] RATE_ERR_MMCM_LOCK_TIMEOUT            = 8'h06;
    localparam [7:0] RATE_ERR_TX_RESETDONE_TIMEOUT         = 8'h07;
    localparam [7:0] RATE_ERR_GT_READY_TIMEOUT             = 8'h08;
    localparam [7:0] RATE_ERR_TXUSRCLK2_NOT_ALIVE          = 8'h09;
    localparam [7:0] RATE_ERR_TXUSRCLK2_FREQ_OUT_OF_WINDOW = 8'h0a;
    localparam [7:0] RATE_ERR_CPLL_LOCK_TIMEOUT            = 8'h0b;

    localparam [3:0] RATE_ID_NONE  = 4'd0;
    localparam [3:0] RATE_ID_500M  = 4'd1;
    localparam [3:0] RATE_ID_1000M = 4'd2;
    localparam [3:0] RATE_ID_2000M = 4'd3;
    localparam [3:0] RATE_ID_1250M = 4'd4;
    localparam [3:0] RATE_ID_2500M = 4'd5;
    localparam [3:0] RATE_ID_5000M = 4'd6;
    localparam [3:0] RATE_ID_3125M = 4'd7;
    localparam [3:0] RATE_ID_6250M = 4'd8;

    localparam [1:0] REFCLK_125M = 2'd0;
    localparam [1:0] PLL_TYPE_CPLL = 2'd0;
    localparam [3:0] GT_DRP_SEQ_TXOUT_DIV = 4'd1;
    localparam [3:0] GT_DRP_SEQ_CPLL_TXOUT_DIV = 4'd2;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE0_500M = 4'd1;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE1_1000M = 4'd2;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE2_2000M = 4'd3;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE3_1250M = 4'd4;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE4_2500M = 4'd5;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE5_5000M = 4'd6;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE6_3125M = 4'd7;
    localparam [3:0] MMCM_DRP_SEQ_PROFILE7_6250M = 4'd8;
    localparam [7:0] PROFILE_FLAG_NONE = 8'h00;
    localparam [7:0] PROFILE_FLAG_AD9528_DYNAMIC_REQUIRED = 8'h01;

    localparam [8:0] GTX_DRP_ADDR_OUT_DIV = 9'h088;
    localparam [8:0] GTX_DRP_ADDR_CPLL_DIV = 9'h05e;
    localparam [15:0] GTX_DRP_CPLL_DIV_MASK = 16'h1fff;

    localparam [3:0] GT_STEP_READ_CPLL        = 4'd0;
    localparam [3:0] GT_STEP_READ_CPLL_WAIT   = 4'd1;
    localparam [3:0] GT_STEP_WRITE_CPLL       = 4'd2;
    localparam [3:0] GT_STEP_WRITE_CPLL_WAIT  = 4'd3;
    localparam [3:0] GT_STEP_READBACK_CPLL    = 4'd4;
    localparam [3:0] GT_STEP_READBACK_CPLL_WAIT = 4'd5;
    localparam [3:0] GT_STEP_READ_OUTDIV      = 4'd6;
    localparam [3:0] GT_STEP_READ_OUTDIV_WAIT = 4'd7;
    localparam [3:0] GT_STEP_WRITE_OUTDIV     = 4'd8;
    localparam [3:0] GT_STEP_WRITE_OUTDIV_WAIT = 4'd9;
    localparam [3:0] GT_STEP_READBACK         = 4'd10;
    localparam [3:0] GT_STEP_READBACK_WAIT    = 4'd11;
    localparam [3:0] GT_STEP_DONE             = 4'd12;

    localparam integer MMCM_TABLE_LEN = 15;

    reg rate_req_toggle_d;
    reg [3:0] target_rate_id;
    reg [2:0] target_txout_div_enc;
    reg [4:0] target_cpll_refclk_div_enc;
    reg       target_cpll_fbdiv_45_enc;
    reg [6:0] target_cpll_fbdiv_enc;
    (* mark_debug = "true", keep = "true" *) reg [15:0] target_cpll_drp_value;
    (* mark_debug = "true", keep = "true" *) reg [15:0] active_cpll_drp_value;
    reg [15:0] programmed_cpll_drp_value;
    reg        programmed_cpll_drp_valid;
    reg [23:0] expected_min_count;
    reg [23:0] expected_max_count;
    reg [1:0] target_refclk_id;
    reg [31:0] target_refclk_freq_hz;
    reg [1:0] target_pll_type;
    reg [3:0] target_gt_drp_seq_id;
    reg [3:0] target_mmcm_drp_seq_id;
    reg [31:0] target_expected_txusrclk2_hz;
    reg [31:0] target_lock_timeout;
    reg [31:0] target_reset_timeout;
    reg [7:0] target_profile_flags;
    reg [31:0] timeout_count;
    reg [31:0] reset_hold_count;
    reg [31:0] verify_count;
    reg [3:0] gt_step;
    reg [4:0] mmcm_index;
    reg [15:0] gt_outdiv_readback;
    reg [15:0] gt_cpll_readback;
    reg request_pending;

    (* mark_debug = "true", keep = "true" *) wire cpll_drp_required =
        (!programmed_cpll_drp_valid) ||
        (target_cpll_drp_value != programmed_cpll_drp_value);

    wire can_accept_rate_request =
        (rate_state == RATE_IDLE) ||
        (rate_state == RATE_DONE) ||
        (rate_state == RATE_ERROR);
    wire request_event = gpio_ctrl[17] ^ rate_req_toggle_d;
    wire [3:0] requested_rate_id = gpio_ctrl[16:13];
    wire laser_busy = gpio_status[3];
    wire laser_done = gpio_status[4];
    wire laser_idle = (!laser_busy) || laser_done;
    wire target_supported = profile_supported(target_rate_id);
    wire target_is_current = target_supported &&
                             (target_rate_id == current_rate_id);
    wire freq_in_window =
        (txusrclk2_freq_counter_axi >= {8'd0, expected_min_count}) &&
        (txusrclk2_freq_counter_axi <= {8'd0, expected_max_count});

    assign dbg_timeout_count = timeout_count;

    function profile_supported;
        input [3:0] rate_id;
        begin
            profile_supported = (rate_id == RATE_ID_500M) ||
                                (rate_id == RATE_ID_1000M) ||
                                (rate_id == RATE_ID_2000M) ||
                                (rate_id == RATE_ID_1250M) ||
                                (rate_id == RATE_ID_2500M) ||
                                (rate_id == RATE_ID_5000M) ||
                                (rate_id == RATE_ID_3125M) ||
                                (rate_id == RATE_ID_6250M);
        end
    endfunction

    function [15:0] profile_rate_mbps;
        input [3:0] rate_id;
        begin
            case (rate_id)
            RATE_ID_500M:  profile_rate_mbps = 16'd500;
            RATE_ID_1000M: profile_rate_mbps = 16'd1000;
            RATE_ID_2000M: profile_rate_mbps = 16'd2000;
            RATE_ID_1250M: profile_rate_mbps = 16'd1250;
            RATE_ID_2500M: profile_rate_mbps = 16'd2500;
            RATE_ID_5000M: profile_rate_mbps = 16'd5000;
            RATE_ID_3125M: profile_rate_mbps = 16'd3125;
            RATE_ID_6250M: profile_rate_mbps = 16'd6250;
            default:       profile_rate_mbps = 16'd0;
            endcase
        end
    endfunction

    function [1:0] profile_refclk_id;
        input [3:0] rate_id;
        begin
            profile_refclk_id = REFCLK_125M;
        end
    endfunction

    function [31:0] profile_refclk_freq_hz;
        input [3:0] rate_id;
        begin
            profile_refclk_freq_hz = 32'd125000000;
        end
    endfunction

    function [1:0] profile_pll_type;
        input [3:0] rate_id;
        begin
            profile_pll_type = PLL_TYPE_CPLL;
        end
    endfunction

    function [3:0] profile_gt_drp_seq_id;
        input [3:0] rate_id;
        begin
            profile_gt_drp_seq_id = GT_DRP_SEQ_TXOUT_DIV;
        end
    endfunction

    function [3:0] profile_mmcm_drp_seq_id;
        input [3:0] rate_id;
        begin
            case (rate_id)
            RATE_ID_500M:  profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE0_500M;
            RATE_ID_1000M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE1_1000M;
            RATE_ID_2000M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE2_2000M;
            RATE_ID_1250M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE3_1250M;
            RATE_ID_2500M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE4_2500M;
            RATE_ID_5000M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE5_5000M;
            RATE_ID_3125M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE6_3125M;
            RATE_ID_6250M: profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE7_6250M;
            default:       profile_mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE0_500M;
            endcase
        end
    endfunction

    function [2:0] profile_txout_div_enc;
        input [3:0] rate_id;
        begin
            case (rate_id)
            RATE_ID_500M:  profile_txout_div_enc = 3'b011;
            RATE_ID_1000M: profile_txout_div_enc = 3'b010;
            RATE_ID_2000M: profile_txout_div_enc = 3'b001;
            RATE_ID_1250M: profile_txout_div_enc = 3'b010;
            RATE_ID_2500M: profile_txout_div_enc = 3'b001;
            RATE_ID_5000M: profile_txout_div_enc = 3'b000;
            RATE_ID_3125M: profile_txout_div_enc = 3'b001;
            RATE_ID_6250M: profile_txout_div_enc = 3'b000;
            default:       profile_txout_div_enc = 3'b011;
            endcase
        end
    endfunction

    function [4:0] profile_cpll_refclk_div_enc;
        input [3:0] rate_id;
        begin
            // XVphy_DrpEncodeQpllMCpllMN2(M=1) -> 5'h10.
            profile_cpll_refclk_div_enc = 5'h10;
        end
    endfunction

    function profile_cpll_fbdiv_45_enc;
        input [3:0] rate_id;
        begin
            // XVphy_DrpEncodeCpllN1(N1=4) -> 1'b0.
            // XVphy_DrpEncodeCpllN1(N1=5) -> 1'b1.
            if (rate_id == RATE_ID_3125M || rate_id == RATE_ID_6250M) begin
                profile_cpll_fbdiv_45_enc = 1'b1;
            end else begin
                profile_cpll_fbdiv_45_enc = 1'b0;
            end
        end
    endfunction

    function [6:0] profile_cpll_fbdiv_enc;
        input [3:0] rate_id;
        begin
            case (rate_id)
            // XVphy_DrpEncodeQpllMCpllMN2(N2=5) -> 7'h03.
            RATE_ID_1250M: profile_cpll_fbdiv_enc = 7'h03;
            RATE_ID_2500M: profile_cpll_fbdiv_enc = 7'h03;
            RATE_ID_5000M: profile_cpll_fbdiv_enc = 7'h03;
            RATE_ID_3125M: profile_cpll_fbdiv_enc = 7'h03;
            RATE_ID_6250M: profile_cpll_fbdiv_enc = 7'h03;
            // Current 500M/1000M/2000M profiles use N2=4 -> 7'h02.
            default:       profile_cpll_fbdiv_enc = 7'h02;
            endcase
        end
    endfunction

    function [15:0] cpll_div_drp_value;
        input [4:0] refclk_div_enc;
        input       fbdiv_45_enc;
        input [6:0] fbdiv_enc;
        begin
            cpll_div_drp_value = ({11'd0, refclk_div_enc} << 8) |
                                 ({15'd0, fbdiv_45_enc} << 7) |
                                 {9'd0, fbdiv_enc};
        end
    endfunction

    function [31:0] profile_expected_txusrclk2_hz;
        input [3:0] rate_id;
        begin
            case (rate_id)
            RATE_ID_500M:  profile_expected_txusrclk2_hz = 32'd7812500;
            RATE_ID_1000M: profile_expected_txusrclk2_hz = 32'd15625000;
            RATE_ID_2000M: profile_expected_txusrclk2_hz = 32'd31250000;
            RATE_ID_1250M: profile_expected_txusrclk2_hz = 32'd19531250;
            RATE_ID_2500M: profile_expected_txusrclk2_hz = 32'd39062500;
            RATE_ID_5000M: profile_expected_txusrclk2_hz = 32'd78125000;
            RATE_ID_3125M: profile_expected_txusrclk2_hz = 32'd48828125;
            RATE_ID_6250M: profile_expected_txusrclk2_hz = 32'd97656250;
            default:       profile_expected_txusrclk2_hz = 32'd7812500;
            endcase
        end
    endfunction

    function [23:0] profile_freq_min_count;
        input [3:0] rate_id;
        begin
            case (rate_id)
            RATE_ID_500M:  profile_freq_min_count = FREQ_500M_MIN_COUNT[23:0];
            RATE_ID_1000M: profile_freq_min_count = FREQ_1000M_MIN_COUNT[23:0];
            RATE_ID_2000M: profile_freq_min_count = FREQ_2000M_MIN_COUNT[23:0];
            RATE_ID_1250M: profile_freq_min_count = FREQ_1250M_MIN_COUNT[23:0];
            RATE_ID_2500M: profile_freq_min_count = FREQ_2500M_MIN_COUNT[23:0];
            RATE_ID_5000M: profile_freq_min_count = FREQ_5000M_MIN_COUNT[23:0];
            RATE_ID_3125M: profile_freq_min_count = FREQ_3125M_MIN_COUNT[23:0];
            RATE_ID_6250M: profile_freq_min_count = FREQ_6250M_MIN_COUNT[23:0];
            default:       profile_freq_min_count = FREQ_500M_MIN_COUNT[23:0];
            endcase
        end
    endfunction

    function [23:0] profile_freq_max_count;
        input [3:0] rate_id;
        begin
            case (rate_id)
            RATE_ID_500M:  profile_freq_max_count = FREQ_500M_MAX_COUNT[23:0];
            RATE_ID_1000M: profile_freq_max_count = FREQ_1000M_MAX_COUNT[23:0];
            RATE_ID_2000M: profile_freq_max_count = FREQ_2000M_MAX_COUNT[23:0];
            RATE_ID_1250M: profile_freq_max_count = FREQ_1250M_MAX_COUNT[23:0];
            RATE_ID_2500M: profile_freq_max_count = FREQ_2500M_MAX_COUNT[23:0];
            RATE_ID_5000M: profile_freq_max_count = FREQ_5000M_MAX_COUNT[23:0];
            RATE_ID_3125M: profile_freq_max_count = FREQ_3125M_MAX_COUNT[23:0];
            RATE_ID_6250M: profile_freq_max_count = FREQ_6250M_MAX_COUNT[23:0];
            default:       profile_freq_max_count = FREQ_500M_MAX_COUNT[23:0];
            endcase
        end
    endfunction

    function [31:0] profile_lock_timeout;
        input [3:0] rate_id;
        begin
            profile_lock_timeout = LOCK_TIMEOUT_CYCLES;
        end
    endfunction

    function [31:0] profile_reset_timeout;
        input [3:0] rate_id;
        begin
            profile_reset_timeout = RESET_HOLD_CYCLES;
        end
    endfunction

    function [7:0] profile_flags;
        input [3:0] rate_id;
        begin
            profile_flags = PROFILE_FLAG_NONE;
        end
    endfunction

    function [6:0] mmcm_addr_for_index;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_addr_for_index = 7'h28;
            5'd1:  mmcm_addr_for_index = 7'h14;
            5'd2:  mmcm_addr_for_index = 7'h15;
            5'd3:  mmcm_addr_for_index = 7'h16;
            5'd4:  mmcm_addr_for_index = 7'h08;
            5'd5:  mmcm_addr_for_index = 7'h09;
            5'd6:  mmcm_addr_for_index = 7'h0a;
            5'd7:  mmcm_addr_for_index = 7'h0b;
            5'd8:  mmcm_addr_for_index = 7'h0c;
            5'd9:  mmcm_addr_for_index = 7'h0d;
            5'd10: mmcm_addr_for_index = 7'h18;
            5'd11: mmcm_addr_for_index = 7'h19;
            5'd12: mmcm_addr_for_index = 7'h1a;
            5'd13: mmcm_addr_for_index = 7'h4e;
            default: mmcm_addr_for_index = 7'h4f;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_500m;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_data_500m = 16'hffff;
            5'd1:  mmcm_data_500m = 16'h14d4;
            5'd2:  mmcm_data_500m = 16'h0080;
            5'd3:  mmcm_data_500m = 16'h1041;
            5'd4:  mmcm_data_500m = 16'h19e7;
            5'd5:  mmcm_data_500m = 16'h0000;
            5'd6:  mmcm_data_500m = 16'h14d4;
            5'd7:  mmcm_data_500m = 16'h0080;
            5'd8:  mmcm_data_500m = 16'h1041;
            5'd9:  mmcm_data_500m = 16'h00c0;
            5'd10: mmcm_data_500m = 16'h00fa;
            5'd11: mmcm_data_500m = 16'h7c01;
            5'd12: mmcm_data_500m = 16'h7de9;
            5'd13: mmcm_data_500m = 16'h0800;
            default: mmcm_data_500m = 16'h9000;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_1000m;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_data_1000m = 16'hffff;
            5'd1:  mmcm_data_1000m = 16'h128a;
            5'd2:  mmcm_data_1000m = 16'h0000;
            5'd3:  mmcm_data_1000m = 16'h1041;
            5'd4:  mmcm_data_1000m = 16'h1514;
            5'd5:  mmcm_data_1000m = 16'h0000;
            5'd6:  mmcm_data_1000m = 16'h128a;
            5'd7:  mmcm_data_1000m = 16'h0000;
            5'd8:  mmcm_data_1000m = 16'h1041;
            5'd9:  mmcm_data_1000m = 16'h00c0;
            5'd10: mmcm_data_1000m = 16'h00f4;
            5'd11: mmcm_data_1000m = 16'h7c01;
            5'd12: mmcm_data_1000m = 16'h7de9;
            5'd13: mmcm_data_1000m = 16'h0800;
            default: mmcm_data_1000m = 16'h1800;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_2000m;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_data_2000m = 16'hffff;
            5'd1:  mmcm_data_2000m = 16'h1145;
            5'd2:  mmcm_data_2000m = 16'h0000;
            5'd3:  mmcm_data_2000m = 16'h1041;
            5'd4:  mmcm_data_2000m = 16'h128a;
            5'd5:  mmcm_data_2000m = 16'h0000;
            5'd6:  mmcm_data_2000m = 16'h1145;
            5'd7:  mmcm_data_2000m = 16'h0000;
            5'd8:  mmcm_data_2000m = 16'h1041;
            5'd9:  mmcm_data_2000m = 16'h00c0;
            5'd10: mmcm_data_2000m = 16'h01e8;
            5'd11: mmcm_data_2000m = 16'h7001;
            5'd12: mmcm_data_2000m = 16'h71e9;
            5'd13: mmcm_data_2000m = 16'h0800;
            default: mmcm_data_2000m = 16'h1100;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_1250m;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_data_1250m = 16'hffff;
            5'd1:  mmcm_data_1250m = 16'h1208;
            5'd2:  mmcm_data_1250m = 16'h0000;
            5'd3:  mmcm_data_1250m = 16'h1041;
            5'd4:  mmcm_data_1250m = 16'h1410;
            5'd5:  mmcm_data_1250m = 16'h0000;
            5'd6:  mmcm_data_1250m = 16'h1208;
            5'd7:  mmcm_data_1250m = 16'h0000;
            5'd8:  mmcm_data_1250m = 16'h1041;
            5'd9:  mmcm_data_1250m = 16'h00c0;
            5'd10: mmcm_data_1250m = 16'h0171;
            5'd11: mmcm_data_1250m = 16'h7c01;
            5'd12: mmcm_data_1250m = 16'h7de9;
            5'd13: mmcm_data_1250m = 16'h0800;
            default: mmcm_data_1250m = 16'h0100;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_2500m;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_data_2500m = 16'hffff;
            5'd1:  mmcm_data_2500m = 16'h1104;
            5'd2:  mmcm_data_2500m = 16'h0000;
            5'd3:  mmcm_data_2500m = 16'h1041;
            5'd4:  mmcm_data_2500m = 16'h1208;
            5'd5:  mmcm_data_2500m = 16'h0000;
            5'd6:  mmcm_data_2500m = 16'h1104;
            5'd7:  mmcm_data_2500m = 16'h0000;
            5'd8:  mmcm_data_2500m = 16'h1041;
            5'd9:  mmcm_data_2500m = 16'h00c0;
            5'd10: mmcm_data_2500m = 16'h01e8;
            5'd11: mmcm_data_2500m = 16'h5801;
            5'd12: mmcm_data_2500m = 16'h59e9;
            5'd13: mmcm_data_2500m = 16'h0800;
            default: mmcm_data_2500m = 16'h0900;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_5000m;
        input [4:0] index;
        begin
            case (index)
            5'd0:  mmcm_data_5000m = 16'hffff;
            5'd1:  mmcm_data_5000m = 16'h1082;
            5'd2:  mmcm_data_5000m = 16'h0000;
            5'd3:  mmcm_data_5000m = 16'h1041;
            5'd4:  mmcm_data_5000m = 16'h1104;
            5'd5:  mmcm_data_5000m = 16'h0000;
            5'd6:  mmcm_data_5000m = 16'h1082;
            5'd7:  mmcm_data_5000m = 16'h0000;
            5'd8:  mmcm_data_5000m = 16'h1041;
            5'd9:  mmcm_data_5000m = 16'h00c0;
            5'd10: mmcm_data_5000m = 16'h01e8;
            5'd11: mmcm_data_5000m = 16'h2c01;
            5'd12: mmcm_data_5000m = 16'h2de9;
            5'd13: mmcm_data_5000m = 16'h0800;
            default: mmcm_data_5000m = 16'h9900;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_3125m;
        input [4:0] index;
        begin
            // TXOUTCLK=97.65625MHz, VCO=781.25MHz:
            // CLKFBOUT_MULT=8, CLKOUT1_DIVIDE=8, CLKOUT0_DIVIDE=16.
            // Encoded by the same Xilinx VPHY MMCME2 method used for 2500M.
            case (index)
            5'd0:  mmcm_data_3125m = 16'hffff;
            5'd1:  mmcm_data_3125m = 16'h1104;
            5'd2:  mmcm_data_3125m = 16'h0000;
            5'd3:  mmcm_data_3125m = 16'h1041;
            5'd4:  mmcm_data_3125m = 16'h1208;
            5'd5:  mmcm_data_3125m = 16'h0000;
            5'd6:  mmcm_data_3125m = 16'h1104;
            5'd7:  mmcm_data_3125m = 16'h0000;
            5'd8:  mmcm_data_3125m = 16'h1041;
            5'd9:  mmcm_data_3125m = 16'h00c0;
            5'd10: mmcm_data_3125m = 16'h01e8;
            5'd11: mmcm_data_3125m = 16'h5801;
            5'd12: mmcm_data_3125m = 16'h59e9;
            5'd13: mmcm_data_3125m = 16'h0800;
            default: mmcm_data_3125m = 16'h0900;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_6250m;
        input [4:0] index;
        begin
            // TXOUTCLK=195.3125MHz, VCO=781.25MHz:
            // CLKFBOUT_MULT=4, CLKOUT1_DIVIDE=4, CLKOUT0_DIVIDE=8.
            // Encoded by the same Xilinx VPHY MMCME2 method used for 5000M.
            case (index)
            5'd0:  mmcm_data_6250m = 16'hffff;
            5'd1:  mmcm_data_6250m = 16'h1082;
            5'd2:  mmcm_data_6250m = 16'h0000;
            5'd3:  mmcm_data_6250m = 16'h1041;
            5'd4:  mmcm_data_6250m = 16'h1104;
            5'd5:  mmcm_data_6250m = 16'h0000;
            5'd6:  mmcm_data_6250m = 16'h1082;
            5'd7:  mmcm_data_6250m = 16'h0000;
            5'd8:  mmcm_data_6250m = 16'h1041;
            5'd9:  mmcm_data_6250m = 16'h00c0;
            5'd10: mmcm_data_6250m = 16'h01e8;
            5'd11: mmcm_data_6250m = 16'h2c01;
            5'd12: mmcm_data_6250m = 16'h2de9;
            5'd13: mmcm_data_6250m = 16'h0800;
            default: mmcm_data_6250m = 16'h9900;
            endcase
        end
    endfunction

    function [15:0] mmcm_data_for_seq;
        input [3:0] seq_id;
        input [4:0] index;
        begin
            if (seq_id == MMCM_DRP_SEQ_PROFILE0_500M) begin
                mmcm_data_for_seq = mmcm_data_500m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE1_1000M) begin
                mmcm_data_for_seq = mmcm_data_1000m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE2_2000M) begin
                mmcm_data_for_seq = mmcm_data_2000m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE3_1250M) begin
                mmcm_data_for_seq = mmcm_data_1250m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE4_2500M) begin
                mmcm_data_for_seq = mmcm_data_2500m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE5_5000M) begin
                mmcm_data_for_seq = mmcm_data_5000m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE6_3125M) begin
                mmcm_data_for_seq = mmcm_data_3125m(index);
            end else if (seq_id == MMCM_DRP_SEQ_PROFILE7_6250M) begin
                mmcm_data_for_seq = mmcm_data_6250m(index);
            end else begin
                mmcm_data_for_seq = mmcm_data_500m(index);
            end
        end
    endfunction

    task set_error;
        input [7:0] code;
        begin
            rate_state <= RATE_ERROR;
            rate_busy <= 1'b0;
            rate_done <= 1'b0;
            rate_error <= 1'b1;
            rate_error_code <= code;
            apply_enable_blocked <= 1'b0;
            tx_quiesce_req <= 1'b0;
            rate_gt_tx_reset <= 1'b0;
            rate_txuserrdy_block <= 1'b0;
            rate_mmcm_reset <= 1'b0;
            rate_cpll_reset <= 1'b0;
            gt_drp_busy <= 1'b0;
            mmcm_drp_busy <= 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            rate_req_toggle_d       <= 1'b0;
            target_rate_id          <= RATE_ID_NONE;
            target_rate_mbps        <= 16'd0;
            target_txout_div_enc    <= 3'd3;
            target_cpll_refclk_div_enc <= 5'h10;
            target_cpll_fbdiv_45_enc <= 1'b0;
            target_cpll_fbdiv_enc   <= 7'h02;
            target_cpll_drp_value   <= 16'h1002;
            active_cpll_drp_value   <= 16'h1002;
            programmed_cpll_drp_value <= 16'd0;
            programmed_cpll_drp_valid <= 1'b0;
            expected_min_count      <= FREQ_500M_MIN_COUNT[23:0];
            expected_max_count      <= FREQ_500M_MAX_COUNT[23:0];
            target_refclk_id        <= REFCLK_125M;
            target_refclk_freq_hz   <= 32'd125000000;
            target_pll_type         <= PLL_TYPE_CPLL;
            target_gt_drp_seq_id    <= GT_DRP_SEQ_TXOUT_DIV;
            target_mmcm_drp_seq_id  <= MMCM_DRP_SEQ_PROFILE0_500M;
            target_expected_txusrclk2_hz <= 32'd7812500;
            target_lock_timeout     <= LOCK_TIMEOUT_CYCLES;
            target_reset_timeout    <= RESET_HOLD_CYCLES;
            target_profile_flags    <= PROFILE_FLAG_NONE;
            current_rate_id         <= RATE_ID_500M;
            current_rate_mbps       <= 16'd500;
            timeout_count           <= 32'd0;
            reset_hold_count        <= 32'd0;
            verify_count            <= 32'd0;
            gt_step                 <= GT_STEP_READ_OUTDIV;
            mmcm_index              <= 5'd0;
            gt_outdiv_readback      <= 16'd0;
            gt_cpll_readback        <= 16'd0;
            request_pending         <= 1'b0;

            rate_gt_tx_reset        <= 1'b0;
            rate_txuserrdy_block    <= 1'b0;
            rate_mmcm_reset         <= 1'b0;
            rate_cpll_reset         <= 1'b0;
            apply_enable_blocked    <= 1'b0;

            gt_drp_addr             <= 9'd0;
            gt_drp_di               <= 16'd0;
            gt_drp_en               <= 1'b0;
            gt_drp_we               <= 1'b0;
            mmcm_drp_addr           <= 7'd0;
            mmcm_drp_di             <= 16'd0;
            mmcm_drp_en             <= 1'b0;
            mmcm_drp_we             <= 1'b0;

            rate_state              <= RATE_IDLE;
            rate_busy               <= 1'b0;
            rate_done               <= 1'b0;
            rate_error              <= 1'b0;
            already_current_rate    <= 1'b0;
            rate_error_code         <= RATE_ERR_NONE;

            gt_drp_busy             <= 1'b0;
            gt_drp_done             <= 1'b0;
            gt_drp_error            <= 1'b0;
            gt_drp_write_attempted  <= 1'b0;
            gt_drp_readback_value   <= 16'd0;
            mmcm_drp_busy           <= 1'b0;
            mmcm_drp_done           <= 1'b0;
            mmcm_drp_error          <= 1'b0;
            mmcm_drp_write_attempted <= 1'b0;
            tx_quiesce_req          <= 1'b0;
            tx_idle_seen            <= 1'b0;
        end else begin
            gt_drp_en <= 1'b0;
            gt_drp_we <= 1'b0;
            mmcm_drp_en <= 1'b0;
            mmcm_drp_we <= 1'b0;
            rate_req_toggle_d <= gpio_ctrl[17];

            if (request_event && can_accept_rate_request) begin
                request_pending <= 1'b1;
                target_rate_id <= requested_rate_id;
                target_rate_mbps <= profile_rate_mbps(requested_rate_id);
                target_txout_div_enc <= profile_txout_div_enc(requested_rate_id);
                target_cpll_refclk_div_enc <= profile_cpll_refclk_div_enc(requested_rate_id);
                target_cpll_fbdiv_45_enc <= profile_cpll_fbdiv_45_enc(requested_rate_id);
                target_cpll_fbdiv_enc <= profile_cpll_fbdiv_enc(requested_rate_id);
                target_cpll_drp_value <= cpll_div_drp_value(
                    profile_cpll_refclk_div_enc(requested_rate_id),
                    profile_cpll_fbdiv_45_enc(requested_rate_id),
                    profile_cpll_fbdiv_enc(requested_rate_id));
                expected_min_count <= profile_freq_min_count(requested_rate_id);
                expected_max_count <= profile_freq_max_count(requested_rate_id);
                target_refclk_id <= profile_refclk_id(requested_rate_id);
                target_refclk_freq_hz <= profile_refclk_freq_hz(requested_rate_id);
                target_pll_type <= profile_pll_type(requested_rate_id);
                if (cpll_div_drp_value(profile_cpll_refclk_div_enc(requested_rate_id),
                                       profile_cpll_fbdiv_45_enc(requested_rate_id),
                                       profile_cpll_fbdiv_enc(requested_rate_id)) !=
                    programmed_cpll_drp_value || !programmed_cpll_drp_valid) begin
                    target_gt_drp_seq_id <= GT_DRP_SEQ_CPLL_TXOUT_DIV;
                end else begin
                    target_gt_drp_seq_id <= profile_gt_drp_seq_id(requested_rate_id);
                end
                target_mmcm_drp_seq_id <= profile_mmcm_drp_seq_id(requested_rate_id);
                target_expected_txusrclk2_hz <= profile_expected_txusrclk2_hz(requested_rate_id);
                target_lock_timeout <= profile_lock_timeout(requested_rate_id);
                target_reset_timeout <= profile_reset_timeout(requested_rate_id);
                target_profile_flags <= profile_flags(requested_rate_id);
            end

            case (rate_state)
            RATE_IDLE: begin
                rate_busy <= 1'b0;
                apply_enable_blocked <= 1'b0;
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b0;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                gt_drp_busy <= 1'b0;
                mmcm_drp_busy <= 1'b0;
                tx_quiesce_req <= 1'b0;
                if (request_pending) begin
                    request_pending <= 1'b0;
                    rate_state <= RATE_REQUEST;
                    rate_busy <= 1'b1;
                    rate_done <= 1'b0;
                    rate_error <= 1'b0;
                    already_current_rate <= 1'b0;
                    rate_error_code <= RATE_ERR_NONE;
                    gt_drp_done <= 1'b0;
                    gt_drp_error <= 1'b0;
                    gt_drp_write_attempted <= 1'b0;
                    mmcm_drp_done <= 1'b0;
                    mmcm_drp_error <= 1'b0;
                    mmcm_drp_write_attempted <= 1'b0;
                    tx_idle_seen <= 1'b0;
                    timeout_count <= 32'd0;
                end
            end

            RATE_DONE: begin
                rate_busy <= 1'b0;
                apply_enable_blocked <= 1'b0;
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b0;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                tx_quiesce_req <= 1'b0;
                gt_drp_busy <= 1'b0;
                mmcm_drp_busy <= 1'b0;
                if (request_pending) begin
                    request_pending <= 1'b0;
                    rate_state <= RATE_REQUEST;
                    rate_busy <= 1'b1;
                    rate_done <= 1'b0;
                    rate_error <= 1'b0;
                    already_current_rate <= 1'b0;
                    rate_error_code <= RATE_ERR_NONE;
                    gt_drp_done <= 1'b0;
                    gt_drp_error <= 1'b0;
                    gt_drp_write_attempted <= 1'b0;
                    mmcm_drp_done <= 1'b0;
                    mmcm_drp_error <= 1'b0;
                    mmcm_drp_write_attempted <= 1'b0;
                    timeout_count <= 32'd0;
                end
            end

            RATE_ERROR: begin
                rate_busy <= 1'b0;
                apply_enable_blocked <= 1'b0;
                tx_quiesce_req <= 1'b0;
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b0;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                gt_drp_busy <= 1'b0;
                mmcm_drp_busy <= 1'b0;
                if (request_pending) begin
                    request_pending <= 1'b0;
                    rate_state <= RATE_REQUEST;
                    rate_busy <= 1'b1;
                    rate_done <= 1'b0;
                    rate_error <= 1'b0;
                    already_current_rate <= 1'b0;
                    rate_error_code <= RATE_ERR_NONE;
                    gt_drp_done <= 1'b0;
                    gt_drp_error <= 1'b0;
                    mmcm_drp_done <= 1'b0;
                    mmcm_drp_error <= 1'b0;
                    timeout_count <= 32'd0;
                end
            end

            RATE_REQUEST: begin
                rate_state <= RATE_VALIDATE;
            end

            RATE_VALIDATE: begin
                if (!target_supported) begin
                    set_error(RATE_ERR_UNSUPPORTED_RATE);
                end else if ((target_refclk_id != REFCLK_125M) ||
                             (target_refclk_freq_hz != 32'd125000000) ||
                             (target_pll_type != PLL_TYPE_CPLL) ||
                             ((target_gt_drp_seq_id != GT_DRP_SEQ_TXOUT_DIV) &&
                              (target_gt_drp_seq_id != GT_DRP_SEQ_CPLL_TXOUT_DIV)) ||
                             ((target_profile_flags & PROFILE_FLAG_AD9528_DYNAMIC_REQUIRED) != 8'h00) ||
                             (target_expected_txusrclk2_hz == 32'd0)) begin
                    set_error(RATE_ERR_UNSUPPORTED_RATE);
                end else if (target_is_current) begin
                    rate_state <= RATE_DONE;
                    rate_busy <= 1'b0;
                    rate_done <= 1'b1;
                    already_current_rate <= 1'b1;
                    gt_drp_done <= 1'b0;
                    mmcm_drp_done <= 1'b0;
                end else begin
                    rate_state <= RATE_QUIESCE_TX;
                    apply_enable_blocked <= 1'b1;
                    tx_quiesce_req <= 1'b1;
                    timeout_count <= 32'd0;
                end
            end

            RATE_QUIESCE_TX: begin
                if (laser_idle) begin
                    tx_idle_seen <= 1'b1;
                    tx_quiesce_req <= 1'b0;
                    rate_state <= RATE_ASSERT_RESET;
                    rate_gt_tx_reset <= 1'b1;
                    rate_txuserrdy_block <= 1'b1;
                    rate_mmcm_reset <= 1'b1;
                    rate_cpll_reset <= (target_gt_drp_seq_id == GT_DRP_SEQ_CPLL_TXOUT_DIV);
                    reset_hold_count <= 32'd0;
                end else if (timeout_count >= TX_QUIESCE_TIMEOUT) begin
                    set_error(RATE_ERR_TX_QUIESCE_TIMEOUT);
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end

            RATE_ASSERT_RESET: begin
                apply_enable_blocked <= 1'b1;
                rate_gt_tx_reset <= 1'b1;
                rate_txuserrdy_block <= 1'b1;
                rate_mmcm_reset <= 1'b1;
                rate_cpll_reset <= (target_gt_drp_seq_id == GT_DRP_SEQ_CPLL_TXOUT_DIV);
                if (reset_hold_count >= target_reset_timeout) begin
                    rate_state <= RATE_PROGRAM_GT_DRP;
                    if (target_gt_drp_seq_id == GT_DRP_SEQ_CPLL_TXOUT_DIV) begin
                        gt_step <= GT_STEP_READ_CPLL;
                    end else begin
                        gt_step <= GT_STEP_READ_OUTDIV;
                    end
                    gt_drp_busy <= 1'b1;
                    timeout_count <= 32'd0;
                end else begin
                    reset_hold_count <= reset_hold_count + 1'b1;
                end
            end

            RATE_PROGRAM_GT_DRP: begin
                apply_enable_blocked <= 1'b1;
                rate_gt_tx_reset <= 1'b1;
                rate_txuserrdy_block <= 1'b1;
                rate_mmcm_reset <= 1'b1;
                rate_cpll_reset <= (target_gt_drp_seq_id == GT_DRP_SEQ_CPLL_TXOUT_DIV);
                gt_drp_busy <= 1'b1;
                case (gt_step)
                GT_STEP_READ_CPLL: begin
                    gt_drp_addr <= GTX_DRP_ADDR_CPLL_DIV;
                    gt_drp_en <= 1'b1;
                    gt_drp_we <= 1'b0;
                    gt_step <= GT_STEP_READ_CPLL_WAIT;
                    timeout_count <= 32'd0;
                end
                GT_STEP_READ_CPLL_WAIT: begin
                    if (gt_drp_rdy) begin
                        gt_cpll_readback <= gt_drp_do;
                        gt_drp_readback_value <= gt_drp_do;
                        gt_step <= GT_STEP_WRITE_CPLL;
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        gt_drp_error <= 1'b1;
                        programmed_cpll_drp_valid <= 1'b0;
                        set_error(RATE_ERR_GT_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                GT_STEP_WRITE_CPLL: begin
                    gt_drp_addr <= GTX_DRP_ADDR_CPLL_DIV;
                    gt_drp_di <= (gt_cpll_readback & ~GTX_DRP_CPLL_DIV_MASK) |
                                 cpll_div_drp_value(target_cpll_refclk_div_enc,
                                                    target_cpll_fbdiv_45_enc,
                                                    target_cpll_fbdiv_enc);
                    gt_drp_en <= 1'b1;
                    gt_drp_we <= 1'b1;
                    gt_drp_write_attempted <= 1'b1;
                    gt_step <= GT_STEP_WRITE_CPLL_WAIT;
                    timeout_count <= 32'd0;
                end
                GT_STEP_WRITE_CPLL_WAIT: begin
                    if (gt_drp_rdy) begin
                        gt_step <= GT_STEP_READBACK_CPLL;
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        gt_drp_error <= 1'b1;
                        programmed_cpll_drp_valid <= 1'b0;
                        set_error(RATE_ERR_GT_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                GT_STEP_READBACK_CPLL: begin
                    gt_drp_addr <= GTX_DRP_ADDR_CPLL_DIV;
                    gt_drp_en <= 1'b1;
                    gt_drp_we <= 1'b0;
                    gt_step <= GT_STEP_READBACK_CPLL_WAIT;
                    timeout_count <= 32'd0;
                end
                GT_STEP_READBACK_CPLL_WAIT: begin
                    if (gt_drp_rdy) begin
                        gt_drp_readback_value <= gt_drp_do;
                        if ((gt_drp_do & GTX_DRP_CPLL_DIV_MASK) ==
                            cpll_div_drp_value(target_cpll_refclk_div_enc,
                                               target_cpll_fbdiv_45_enc,
                                               target_cpll_fbdiv_enc)) begin
                            programmed_cpll_drp_value <= target_cpll_drp_value;
                            programmed_cpll_drp_valid <= 1'b1;
                            gt_step <= GT_STEP_READ_OUTDIV;
                        end else begin
                            gt_drp_error <= 1'b1;
                            programmed_cpll_drp_valid <= 1'b0;
                            set_error(RATE_ERR_GT_DRP_READBACK_MISMATCH);
                        end
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        gt_drp_error <= 1'b1;
                        programmed_cpll_drp_valid <= 1'b0;
                        set_error(RATE_ERR_GT_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                GT_STEP_READ_OUTDIV: begin
                    gt_drp_addr <= GTX_DRP_ADDR_OUT_DIV;
                    gt_drp_en <= 1'b1;
                    gt_drp_we <= 1'b0;
                    gt_step <= GT_STEP_READ_OUTDIV_WAIT;
                    timeout_count <= 32'd0;
                end
                GT_STEP_READ_OUTDIV_WAIT: begin
                    if (gt_drp_rdy) begin
                        gt_outdiv_readback <= gt_drp_do;
                        gt_drp_readback_value <= gt_drp_do;
                        gt_step <= GT_STEP_WRITE_OUTDIV;
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        gt_drp_error <= 1'b1;
                        set_error(RATE_ERR_GT_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                GT_STEP_WRITE_OUTDIV: begin
                    gt_drp_addr <= GTX_DRP_ADDR_OUT_DIV;
                    gt_drp_di <= (gt_outdiv_readback & 16'hff8f) |
                                 ({13'd0, target_txout_div_enc} << 4);
                    gt_drp_en <= 1'b1;
                    gt_drp_we <= 1'b1;
                    gt_drp_write_attempted <= 1'b1;
                    gt_step <= GT_STEP_WRITE_OUTDIV_WAIT;
                    timeout_count <= 32'd0;
                end
                GT_STEP_WRITE_OUTDIV_WAIT: begin
                    if (gt_drp_rdy) begin
                        gt_step <= GT_STEP_READBACK;
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        gt_drp_error <= 1'b1;
                        set_error(RATE_ERR_GT_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                GT_STEP_READBACK: begin
                    gt_drp_addr <= GTX_DRP_ADDR_OUT_DIV;
                    gt_drp_en <= 1'b1;
                    gt_drp_we <= 1'b0;
                    gt_step <= GT_STEP_READBACK_WAIT;
                    timeout_count <= 32'd0;
                end
                GT_STEP_READBACK_WAIT: begin
                    if (gt_drp_rdy) begin
                        gt_drp_readback_value <= gt_drp_do;
                        if (gt_drp_do[6:4] == target_txout_div_enc) begin
                            gt_drp_done <= 1'b1;
                            gt_drp_busy <= 1'b0;
                            gt_step <= GT_STEP_DONE;
                            rate_state <= RATE_PROGRAM_MMCM_DRP;
                            mmcm_index <= 5'd0;
                            mmcm_drp_busy <= 1'b1;
                            timeout_count <= 32'd0;
                        end else begin
                            gt_drp_error <= 1'b1;
                            set_error(RATE_ERR_GT_DRP_READBACK_MISMATCH);
                        end
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        gt_drp_error <= 1'b1;
                        set_error(RATE_ERR_GT_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end
                default: begin
                    gt_drp_error <= 1'b1;
                    if (target_gt_drp_seq_id == GT_DRP_SEQ_CPLL_TXOUT_DIV) begin
                        programmed_cpll_drp_valid <= 1'b0;
                    end
                    set_error(RATE_ERR_GT_DRP_TIMEOUT);
                end
                endcase
            end

            RATE_PROGRAM_MMCM_DRP: begin
                apply_enable_blocked <= 1'b1;
                rate_gt_tx_reset <= 1'b1;
                rate_txuserrdy_block <= 1'b1;
                rate_mmcm_reset <= 1'b1;
                rate_cpll_reset <= (target_gt_drp_seq_id == GT_DRP_SEQ_CPLL_TXOUT_DIV);
                mmcm_drp_busy <= 1'b1;
                if (mmcm_index < MMCM_TABLE_LEN) begin
                    if (timeout_count == 32'd0) begin
                        mmcm_drp_addr <= mmcm_addr_for_index(mmcm_index);
                        mmcm_drp_di <= mmcm_data_for_seq(target_mmcm_drp_seq_id, mmcm_index);
                        mmcm_drp_en <= 1'b1;
                        mmcm_drp_we <= 1'b1;
                        mmcm_drp_write_attempted <= 1'b1;
                        timeout_count <= 32'd1;
                    end else if (mmcm_drp_rdy) begin
                        mmcm_index <= mmcm_index + 1'b1;
                        timeout_count <= 32'd0;
                    end else if (timeout_count >= DRP_TIMEOUT_CYCLES) begin
                        mmcm_drp_error <= 1'b1;
                        set_error(RATE_ERR_MMCM_DRP_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else begin
                    mmcm_drp_done <= 1'b1;
                    mmcm_drp_busy <= 1'b0;
                    rate_state <= RATE_RELEASE_RESET;
                    timeout_count <= 32'd0;
                end
            end

            RATE_RELEASE_RESET: begin
                apply_enable_blocked <= 1'b1;
                // Break the reset interlock before waiting for MMCM lock:
                // rate_gt_tx_reset also drives the GT Wizard soft_reset_tx_in.
                // Keeping it asserted while waiting for tx_mmcm_locked_sync can
                // make the Wizard TX startup FSM keep tx_mmcm_reset_wizard high,
                // so the user-clock MMCM never gets a clean chance to lock.
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b1;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                rate_state <= RATE_WAIT_MMCM_RESET_RELEASE;
                timeout_count <= 32'd0;
            end

            RATE_WAIT_MMCM_RESET_RELEASE: begin
                apply_enable_blocked <= 1'b1;
                // Keep GT Wizard soft reset released and MMCM reset released.
                // Hold TXUSERRDY blocked until the MMCM has locked; this avoids
                // exposing the GT datapath to an unstable user clock while still
                // allowing the Wizard TX reset FSM to release its MMCM_RESET.
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b1;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                if (timeout_count >= target_reset_timeout) begin
                    rate_state <= RATE_WAIT_LOCK;
                    timeout_count <= 32'd0;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end

            RATE_WAIT_LOCK: begin
                apply_enable_blocked <= 1'b1;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                if (!cplllock_sync) begin
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b1;
                    if (timeout_count >= target_lock_timeout) begin
                        set_error(RATE_ERR_CPLL_LOCK_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else if (!tx_mmcm_locked_sync) begin
                    // Do not reassert rate_gt_tx_reset here.  The GT Wizard
                    // must see soft_reset_tx_in released so its startup FSM can
                    // drive tx_mmcm_reset_wizard low and allow MMCM lock.
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b1;
                    if (timeout_count >= target_lock_timeout) begin
                        set_error(RATE_ERR_MMCM_LOCK_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else if (!txresetdone_sync) begin
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b0;
                    if (timeout_count >= target_lock_timeout) begin
                        set_error(RATE_ERR_TX_RESETDONE_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else if (!gt_ready_ctrl) begin
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b0;
                    if (timeout_count >= target_lock_timeout) begin
                        set_error(RATE_ERR_GT_READY_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else begin
                    rate_state <= RATE_VERIFY_RATE;
                    verify_count <= 32'd0;
                    timeout_count <= 32'd0;
                end
            end

            RATE_VERIFY_RATE: begin
                apply_enable_blocked <= 1'b1;
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b0;
                rate_mmcm_reset <= 1'b0;
                rate_cpll_reset <= 1'b0;
                if (verify_count < VERIFY_SETTLE_CYCLES) begin
                    verify_count <= verify_count + 1'b1;
                end else if (!txusrclk2_alive_axi) begin
                    set_error(RATE_ERR_TXUSRCLK2_NOT_ALIVE);
                end else if (!freq_in_window) begin
                    set_error(RATE_ERR_TXUSRCLK2_FREQ_OUT_OF_WINDOW);
                end else begin
                    current_rate_id <= target_rate_id;
                    current_rate_mbps <= target_rate_mbps;
                    active_cpll_drp_value <= target_cpll_drp_value;
                    rate_state <= RATE_DONE;
                    rate_busy <= 1'b0;
                    rate_done <= 1'b1;
                    rate_error <= 1'b0;
                    rate_error_code <= RATE_ERR_NONE;
                    apply_enable_blocked <= 1'b0;
                end
            end

            default: begin
                set_error(RATE_ERR_UNSUPPORTED_RATE);
            end
            endcase
        end
    end

endmodule


`timescale 1ns/1ps

// Minimal TX-only dynamic rate switch controller for the already validated
// 500M Profile0 <-> 1000M Profile1 pair.
//
// This module intentionally supports only two rates.  It does not touch
// CPLL_FBDIV/CPLL_REFCLK_DIV, RXOUT_DIV, QPLL, AD9528 or any wide-range rate
// planning fields.  The GTXE2 and MMCME2 DRP tables are taken from
// docs/debug_reports/06_drp_parameter_confirmation_for_500m_1000m.md.
module laser_gt_rate_switch_500m_1000m #(
    parameter integer RESET_HOLD_CYCLES      = 1024,
    parameter integer TX_QUIESCE_TIMEOUT     = 1000000,
    parameter integer DRP_TIMEOUT_CYCLES     = 4096,
    parameter integer LOCK_TIMEOUT_CYCLES    = 5000000,
    parameter integer VERIFY_SETTLE_CYCLES   = 100000,
    parameter integer FREQ_500M_MIN_COUNT    = 7700,
    parameter integer FREQ_500M_MAX_COUNT    = 7950,
    parameter integer FREQ_1000M_MIN_COUNT   = 15400,
    parameter integer FREQ_1000M_MAX_COUNT   = 15900
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
    (* mark_debug = "true" *) output reg  [1:0]  current_rate_id,
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

    localparam [1:0] RATE_ID_NONE  = 2'd0;
    localparam [1:0] RATE_ID_500M  = 2'd1;
    localparam [1:0] RATE_ID_1000M = 2'd2;

    localparam [8:0] GTX_DRP_ADDR_OUT_DIV = 9'h088;

    localparam [3:0] GT_STEP_READ_OUTDIV      = 4'd0;
    localparam [3:0] GT_STEP_READ_OUTDIV_WAIT = 4'd1;
    localparam [3:0] GT_STEP_WRITE_OUTDIV     = 4'd2;
    localparam [3:0] GT_STEP_WRITE_OUTDIV_WAIT = 4'd3;
    localparam [3:0] GT_STEP_READBACK         = 4'd4;
    localparam [3:0] GT_STEP_READBACK_WAIT    = 4'd5;
    localparam [3:0] GT_STEP_DONE             = 4'd6;

    localparam integer MMCM_TABLE_LEN = 15;

    reg rate_req_toggle_d;
    reg [1:0] target_rate_id;
    reg [2:0] target_txout_div_enc;
    reg [15:0] expected_min_count;
    reg [15:0] expected_max_count;
    reg [31:0] timeout_count;
    reg [31:0] reset_hold_count;
    reg [31:0] verify_count;
    reg [3:0] gt_step;
    reg [4:0] mmcm_index;
    reg [15:0] gt_outdiv_readback;
    reg request_pending;

    wire request_event = gpio_ctrl[15] ^ rate_req_toggle_d;
    wire [1:0] requested_rate_id = gpio_ctrl[14:13];
    wire laser_busy = gpio_status[3];
    wire laser_done = gpio_status[4];
    wire laser_idle = (!laser_busy) || laser_done;
    wire target_supported = (target_rate_id == RATE_ID_500M) ||
                            (target_rate_id == RATE_ID_1000M);
    wire target_is_current = target_supported &&
                             (target_rate_id == current_rate_id);
    wire freq_in_window =
        (txusrclk2_freq_counter_axi >= {16'd0, expected_min_count}) &&
        (txusrclk2_freq_counter_axi <= {16'd0, expected_max_count});

    assign dbg_timeout_count = timeout_count;

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

    function [15:0] mmcm_data_for_target;
        input [1:0] rate_id;
        input [4:0] index;
        begin
            if (rate_id == RATE_ID_500M) begin
                mmcm_data_for_target = mmcm_data_500m(index);
            end else begin
                mmcm_data_for_target = mmcm_data_1000m(index);
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
            expected_min_count      <= FREQ_500M_MIN_COUNT[15:0];
            expected_max_count      <= FREQ_500M_MAX_COUNT[15:0];
            current_rate_id         <= RATE_ID_500M;
            current_rate_mbps       <= 16'd500;
            timeout_count           <= 32'd0;
            reset_hold_count        <= 32'd0;
            verify_count            <= 32'd0;
            gt_step                 <= GT_STEP_READ_OUTDIV;
            mmcm_index              <= 5'd0;
            gt_outdiv_readback      <= 16'd0;
            request_pending         <= 1'b0;

            rate_gt_tx_reset        <= 1'b0;
            rate_txuserrdy_block    <= 1'b0;
            rate_mmcm_reset         <= 1'b0;
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
            rate_req_toggle_d <= gpio_ctrl[15];

            if (request_event) begin
                request_pending <= 1'b1;
                target_rate_id <= requested_rate_id;
                case (requested_rate_id)
                RATE_ID_500M: begin
                    target_rate_mbps <= 16'd500;
                    target_txout_div_enc <= 3'b011;
                    expected_min_count <= FREQ_500M_MIN_COUNT[15:0];
                    expected_max_count <= FREQ_500M_MAX_COUNT[15:0];
                end
                RATE_ID_1000M: begin
                    target_rate_mbps <= 16'd1000;
                    target_txout_div_enc <= 3'b010;
                    expected_min_count <= FREQ_1000M_MIN_COUNT[15:0];
                    expected_max_count <= FREQ_1000M_MAX_COUNT[15:0];
                end
                default: begin
                    target_rate_mbps <= 16'd0;
                    target_txout_div_enc <= 3'b011;
                    expected_min_count <= FREQ_500M_MIN_COUNT[15:0];
                    expected_max_count <= FREQ_500M_MAX_COUNT[15:0];
                end
                endcase
            end

            case (rate_state)
            RATE_IDLE: begin
                rate_busy <= 1'b0;
                apply_enable_blocked <= 1'b0;
                rate_gt_tx_reset <= 1'b0;
                rate_txuserrdy_block <= 1'b0;
                rate_mmcm_reset <= 1'b0;
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
                if (reset_hold_count >= RESET_HOLD_CYCLES) begin
                    rate_state <= RATE_PROGRAM_GT_DRP;
                    gt_step <= GT_STEP_READ_OUTDIV;
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
                gt_drp_busy <= 1'b1;
                case (gt_step)
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
                    set_error(RATE_ERR_GT_DRP_TIMEOUT);
                end
                endcase
            end

            RATE_PROGRAM_MMCM_DRP: begin
                apply_enable_blocked <= 1'b1;
                rate_gt_tx_reset <= 1'b1;
                rate_txuserrdy_block <= 1'b1;
                rate_mmcm_reset <= 1'b1;
                mmcm_drp_busy <= 1'b1;
                if (mmcm_index < MMCM_TABLE_LEN) begin
                    if (timeout_count == 32'd0) begin
                        mmcm_drp_addr <= mmcm_addr_for_index(mmcm_index);
                        mmcm_drp_di <= mmcm_data_for_target(target_rate_id, mmcm_index);
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
                if (timeout_count >= RESET_HOLD_CYCLES) begin
                    rate_state <= RATE_WAIT_LOCK;
                    timeout_count <= 32'd0;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end

            RATE_WAIT_LOCK: begin
                apply_enable_blocked <= 1'b1;
                rate_mmcm_reset <= 1'b0;
                if (!tx_mmcm_locked_sync) begin
                    // Do not reassert rate_gt_tx_reset here.  The GT Wizard
                    // must see soft_reset_tx_in released so its startup FSM can
                    // drive tx_mmcm_reset_wizard low and allow MMCM lock.
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b1;
                    if (timeout_count >= LOCK_TIMEOUT_CYCLES) begin
                        set_error(RATE_ERR_MMCM_LOCK_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else if (!cplllock_sync) begin
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b1;
                    if (timeout_count >= LOCK_TIMEOUT_CYCLES) begin
                        set_error(RATE_ERR_GT_READY_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else if (!txresetdone_sync) begin
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b0;
                    if (timeout_count >= LOCK_TIMEOUT_CYCLES) begin
                        set_error(RATE_ERR_TX_RESETDONE_TIMEOUT);
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end else if (!gt_ready_ctrl) begin
                    rate_gt_tx_reset <= 1'b0;
                    rate_txuserrdy_block <= 1'b0;
                    if (timeout_count >= LOCK_TIMEOUT_CYCLES) begin
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
                if (verify_count < VERIFY_SETTLE_CYCLES) begin
                    verify_count <= verify_count + 1'b1;
                end else if (!txusrclk2_alive_axi) begin
                    set_error(RATE_ERR_TXUSRCLK2_NOT_ALIVE);
                end else if (!freq_in_window) begin
                    set_error(RATE_ERR_TXUSRCLK2_FREQ_OUT_OF_WINDOW);
                end else begin
                    current_rate_id <= target_rate_id;
                    current_rate_mbps <= target_rate_mbps;
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


`timescale 1ns/1ps

// Non-critical sequential geometry calculator for the one selected EOM window.
// All division/multiplication is replaced by bounded subtraction/addition.
module tx_eom_geometry_precompute (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire         eom_enable,
    input  wire [10:0]  global_pattern_index,
    input  wire [15:0]  lead_ticks,
    input  wire [15:0]  trail_ticks,
    input  wire [4:0]   repeat_cycles,
    input  wire [7:0]   pattern_len,
    input  wire         phase_shift_en,
    input  wire [7:0]   head_delay_bits,
    input  wire [119:0] gap_len_bits,
    input  wire [2:0]   eom_subdiv_log2,
    output reg          ready,
    output reg          request_valid,
    output reg  [23:0]  start_tick,
    output reg  [23:0]  end_tick,
    output reg  [7:0]   selected_phase,
    output reg  [3:0]   selected_repeat
);
    localparam [3:0] ST_IDLE=4'd0, ST_DIV=4'd1, ST_SUM=4'd2,
                     ST_PHASE_MUL=4'd3, ST_REPEAT_MUL=4'd4,
                     ST_BITS_TO_TICKS=4'd5, ST_END_TO_TICKS=4'd6,
                     ST_APPLY_MARGIN=4'd7, ST_DISABLED=4'd8;
    reg [3:0] state;
    reg [7:0] phase_count;
    reg [10:0] remaining_index;
    reg [4:0] sum_index;
    reg [23:0] total_gap_bits;
    reg [23:0] prefix_gap_bits;
    reg [23:0] pattern_bits_sum;
    reg [23:0] frame_bits;
    reg [23:0] phase_offset_bits;
    reg [23:0] repeat_offset_bits;
    reg [7:0] multiply_index;
    reg [2:0] shift_bits;
    reg [23:0] bits_per_tick;
    reg [23:0] selected_start_bits;
    reg [23:0] selected_end_bits;
    reg [23:0] start_tick_floor;
    reg [23:0] end_rounded_bits;
    reg [23:0] end_tick_ceil;

    function [7:0] gap_at;
        input [119:0] gaps;
        input [3:0] index;
        begin
            case (index)
                4'd0: gap_at=gaps[7:0];     4'd1: gap_at=gaps[15:8];
                4'd2: gap_at=gaps[23:16];   4'd3: gap_at=gaps[31:24];
                4'd4: gap_at=gaps[39:32];   4'd5: gap_at=gaps[47:40];
                4'd6: gap_at=gaps[55:48];   4'd7: gap_at=gaps[63:56];
                4'd8: gap_at=gaps[71:64];   4'd9: gap_at=gaps[79:72];
                4'd10: gap_at=gaps[87:80];  4'd11: gap_at=gaps[95:88];
                4'd12: gap_at=gaps[103:96]; 4'd13: gap_at=gaps[111:104];
                4'd14: gap_at=gaps[119:112]; default: gap_at=8'd0;
            endcase
        end
    endfunction

    // Fixed-slice selection keeps the variable shift control out of the
    // lead/trail arithmetic stage. Valid runtime settings use shift 2..6;
    // the remaining cases are conservative and preserve the original shift
    // semantics for malformed/debug inputs.
    function [23:0] bits_to_ticks;
        input [23:0] bit_count;
        input [2:0] shift_count;
        begin
            case (shift_count)
                3'd0: bits_to_ticks=bit_count;
                3'd1: bits_to_ticks={1'd0,bit_count[23:1]};
                3'd2: bits_to_ticks={2'd0,bit_count[23:2]};
                3'd3: bits_to_ticks={3'd0,bit_count[23:3]};
                3'd4: bits_to_ticks={4'd0,bit_count[23:4]};
                3'd5: bits_to_ticks={5'd0,bit_count[23:5]};
                3'd6: bits_to_ticks={6'd0,bit_count[23:6]};
                default: bits_to_ticks={7'd0,bit_count[23:7]};
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state<=ST_IDLE; ready<=1'b0; request_valid<=1'b0;
            start_tick<=24'd0; end_tick<=24'd0;
            selected_phase<=8'd0; selected_repeat<=4'd0;
            phase_count<=8'd1; remaining_index<=11'd0; sum_index<=5'd0;
            total_gap_bits<=24'd0; prefix_gap_bits<=24'd0;
            pattern_bits_sum<=24'd0; frame_bits<=24'd0;
            phase_offset_bits<=24'd0; repeat_offset_bits<=24'd0;
            multiply_index<=8'd0; shift_bits<=3'd6;
            bits_per_tick<=24'd64; selected_start_bits<=24'd0;
            selected_end_bits<=24'd0; start_tick_floor<=24'd0;
            end_rounded_bits<=24'd0; end_tick_ceil<=24'd0;
        end else if (start) begin
            ready<=1'b0; request_valid<=1'b0; start_tick<=24'd0; end_tick<=24'd0;
            selected_phase<=8'd0; selected_repeat<=4'd0;
            phase_count<=phase_shift_en ? pattern_len : 8'd1;
            remaining_index<=global_pattern_index;
            sum_index<=5'd0; total_gap_bits<=24'd0; prefix_gap_bits<=24'd0;
            pattern_bits_sum<=24'd0; frame_bits<=24'd0;
            phase_offset_bits<=24'd0; repeat_offset_bits<=24'd0;
            multiply_index<=8'd0;
            shift_bits<=3'd6-eom_subdiv_log2;
            bits_per_tick<=24'd1 << (3'd6-eom_subdiv_log2);
            start_tick_floor<=24'd0;
            end_rounded_bits<=24'd0;
            end_tick_ceil<=24'd0;
            if (!eom_enable) begin
                request_valid<=1'b0; state<=ST_DISABLED;
            end else begin
                state<=ST_DIV;
            end
        end else begin
            case (state)
                ST_IDLE: begin end
                ST_DIV: begin
                    if ((repeat_cycles < 5'd1) || (repeat_cycles > 5'd16) ||
                        (pattern_len != 8'd63 && pattern_len != 8'd127) ||
                        (selected_phase >= phase_count)) begin
                        request_valid<=1'b0; ready<=1'b1; state<=ST_IDLE;
                    end else if (remaining_index >= repeat_cycles) begin
                        remaining_index<=remaining_index-repeat_cycles;
                        selected_phase<=selected_phase+1'b1;
                    end else begin
                        selected_repeat<=remaining_index[3:0];
                        sum_index<=5'd0; state<=ST_SUM;
                    end
                end
                ST_SUM: begin
                    if (sum_index < repeat_cycles) begin
                        pattern_bits_sum<=pattern_bits_sum+pattern_len;
                        if (sum_index < repeat_cycles-1'b1) begin
                            total_gap_bits<=total_gap_bits+gap_at(gap_len_bits,sum_index[3:0]);
                            if (sum_index < selected_repeat)
                                prefix_gap_bits<=prefix_gap_bits+
                                                 gap_at(gap_len_bits,sum_index[3:0]);
                        end
                        sum_index<=sum_index+1'b1;
                    end else begin
                        frame_bits<=head_delay_bits+pattern_bits_sum+total_gap_bits;
                        multiply_index<=8'd0; state<=ST_PHASE_MUL;
                    end
                end
                ST_PHASE_MUL: begin
                    if (multiply_index < selected_phase) begin
                        phase_offset_bits<=phase_offset_bits+frame_bits;
                        multiply_index<=multiply_index+1'b1;
                    end else begin
                        multiply_index<=8'd0; state<=ST_REPEAT_MUL;
                    end
                end
                ST_REPEAT_MUL: begin
                    if (multiply_index < selected_repeat) begin
                        repeat_offset_bits<=repeat_offset_bits+pattern_len;
                        multiply_index<=multiply_index+1'b1;
                    end else begin
                        selected_start_bits<=phase_offset_bits+head_delay_bits+
                                             repeat_offset_bits+prefix_gap_bits;
                        selected_end_bits<=phase_offset_bits+head_delay_bits+
                                           repeat_offset_bits+prefix_gap_bits+
                                           pattern_len;
                        state<=ST_BITS_TO_TICKS;
                    end
                end
                ST_BITS_TO_TICKS: begin
                    start_tick_floor<=
                        bits_to_ticks(selected_start_bits,shift_bits);
                    end_rounded_bits<=
                        selected_end_bits+bits_per_tick-1'b1;
                    state<=ST_END_TO_TICKS;
                end
                ST_END_TO_TICKS: begin
                    end_tick_ceil<=
                        bits_to_ticks(end_rounded_bits,shift_bits);
                    state<=ST_APPLY_MARGIN;
                end
                ST_APPLY_MARGIN: begin
                    if (start_tick_floor > lead_ticks)
                        start_tick<=start_tick_floor-lead_ticks;
                    else
                        start_tick<=24'd0;
                    end_tick<=end_tick_ceil+trail_ticks;
                    request_valid<=1'b1; ready<=1'b1; state<=ST_IDLE;
                end
                ST_DISABLED: begin
                    request_valid<=1'b0; ready<=1'b1; state<=ST_IDLE;
                end
                default: begin
                    request_valid<=1'b0; ready<=1'b1; state<=ST_IDLE;
                end
            endcase
        end
    end
endmodule

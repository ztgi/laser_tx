`timescale 1ns/1ps

// 64-bit-per-clock phase scheduler and gap inserter.
//
// The implementation works at word granularity.  A phase is at least 63 bits,
// therefore one 64-bit word can cross at most one phase boundary.  Gap bounds
// are reduced to 0..64 once per word and every output lane is then selected in
// parallel.  This avoids the former 64-step state dependency chain.
module pattern_tx_engine (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire         enable,
    input  wire         pattern_valid,
    input  wire [126:0] base_pattern,
    input  wire [7:0]   pattern_len,
    input  wire [31:0]  repeat_cycles,
    input  wire [15:0]  insert_after,
    input  wire [7:0]   gap_len_bits,
    input  wire         phase_shift_en,
    input  wire         loop_en,
    output reg  [63:0]  txdata,
    output reg  [63:0]  valid_mask,
    output reg          phase_active,
    output reg          phase_start_pulse,
    output reg          sequence_active,
    output reg          busy,
    output reg          done,
    output reg  [7:0]   phase_offset,
    output reg  [7:0]   current_state
);
    localparam ST_IDLE = 8'd0;
    localparam ST_RUN  = 8'd1;
    localparam ST_DONE = 8'd2;

    // Active configuration is captured at start and remains local to this
    // clock domain for the complete sequence.
    reg [7:0]   len_active;
    reg         phase_shift_active;
    reg         loop_active;
    reg [39:0]  phase_total_active;
    reg [39:0]  gap_start_active;
    reg [39:0]  gap_end_active;
    reg         gap_present_active;

    // phase_pattern holds S_k.  pattern_cursor bit zero is the next valid
    // pattern bit.  In 63-bit mode the sequence is repeated across all 127
    // bits so a complete 64-bit word is directly addressable.
    reg [126:0] phase_pattern;
    reg [126:0] pattern_cursor;
    reg [39:0]  phase_pos;
    reg         running;
    reg         phase_start_pending;

    wire [39:0] repeat_wide = {8'b0, repeat_cycles};
    wire [39:0] insert_wide = {24'b0, insert_after};
    wire [39:0] pattern_bits_input =
        (pattern_len == 8'd63) ? ((repeat_wide << 6) - repeat_wide) :
                                 ((repeat_wide << 7) - repeat_wide);
    wire [39:0] gap_start_input =
        (pattern_len == 8'd63) ? ((insert_wide << 6) - insert_wide) :
                                 ((insert_wide << 7) - insert_wide);
    wire [39:0] gap_end_input = gap_start_input + {32'b0, gap_len_bits};
    wire [39:0] phase_total_input = pattern_bits_input + {32'b0, gap_len_bits};
    wire [126:0] expanded_pattern_input =
        (pattern_len == 8'd63) ?
        {base_pattern[0], base_pattern[62:0], base_pattern[62:0]} :
        base_pattern;

    // Rotate a periodic sequence so output bit zero is count valid bits later.
    // Count is at most 64; no divider or modulo operator is inferred.
    function [126:0] rotate_sequence;
        input [126:0] sequence_in;
        input [6:0]   count;
        input [7:0]   sequence_len;
        reg [253:0] doubled;
        reg [253:0] shifted;
        reg [62:0]  rotated63;
        begin
            if (sequence_len == 8'd63) begin
                doubled = 254'b0;
                // sequence_in already contains 127 periodic bits in 63-bit
                // mode, enough for a 63-bit window after advancing up to 64.
                doubled[126:0] = sequence_in;
                shifted = doubled >> count;
                rotated63 = shifted[62:0];
                rotate_sequence = {rotated63[0], rotated63, rotated63};
            end else begin
                doubled = {sequence_in, sequence_in};
                shifted = doubled >> count;
                rotate_sequence = shifted[126:0];
            end
        end
    endfunction

    // Number of gap bits before position within a 0..64 word window.
    function [6:0] gap_bits_before;
        input [6:0] position;
        input [6:0] gap_start_rel;
        input [6:0] gap_end_rel;
        begin
            if (position <= gap_start_rel)
                gap_bits_before = 7'd0;
            else if (position >= gap_end_rel)
                gap_bits_before = gap_end_rel - gap_start_rel;
            else
                gap_bits_before = position - gap_start_rel;
        end
    endfunction

    integer lane;
    integer next_local_pos;
    reg [39:0] phase_remaining;
    reg [39:0] wide_delta_start;
    reg [39:0] wide_delta_end;
    reg [6:0]  remaining_rel;
    reg [6:0]  current_gap_start_rel;
    reg [6:0]  current_gap_end_rel;
    reg [6:0]  next_gap_start_rel;
    reg [6:0]  next_gap_end_rel;
    reg [6:0]  current_gap_width;
    reg [6:0]  next_gap_width;
    reg [6:0]  current_valid_count;
    reg [6:0]  next_consumed_count;
    reg [6:0]  next_valid_count;
    reg [7:0]  next_phase_offset_calc;
    reg         last_phase_calc;
    reg         has_next_phase_calc;
    reg [126:0] next_phase_pattern_calc;
    reg [126:0] current_after_gap_vec;
    reg [126:0] next_before_gap_aligned;
    reg [126:0] next_after_gap_aligned;
    reg [7:0]   next_after_shift;

    reg [63:0]  txdata_calc;
    reg [63:0]  valid_mask_calc;
    reg         phase_start_calc;
    reg         word_active_calc;

    reg         running_next;
    reg         done_next;
    reg [7:0]   phase_offset_next;
    reg [39:0]  phase_pos_next;
    reg [126:0] phase_pattern_next;
    reg [126:0] pattern_cursor_next;
    reg         phase_start_pending_next;
    reg [126:0] cursor_update_base;
    reg [6:0]   cursor_update_count;

    always @* begin
        phase_remaining = phase_total_active - phase_pos;
        remaining_rel = (phase_remaining >= 40'd64) ?
                        7'd64 : phase_remaining[6:0];

        last_phase_calc = (!phase_shift_active) ||
                          (phase_offset == (len_active - 1'b1));
        has_next_phase_calc = loop_active || !last_phase_calc;
        next_phase_offset_calc = last_phase_calc ? 8'd0 :
                                                  (phase_offset + 1'b1);

        if (len_active == 8'd63)
            next_phase_pattern_calc = rotate_sequence(phase_pattern, 7'd1, 8'd63);
        else
            next_phase_pattern_calc = rotate_sequence(phase_pattern, 7'd1, 8'd127);

        // Reduce the current phase's absolute gap interval to this word.
        current_gap_start_rel = 7'd64;
        current_gap_end_rel = 7'd64;
        if (gap_present_active && (phase_pos < gap_end_active)) begin
            if (phase_pos >= gap_start_active) begin
                current_gap_start_rel = 7'd0;
                wide_delta_end = gap_end_active - phase_pos;
                current_gap_end_rel = (wide_delta_end >= 40'd64) ?
                                      7'd64 : wide_delta_end[6:0];
            end else begin
                wide_delta_start = gap_start_active - phase_pos;
                wide_delta_end = gap_end_active - phase_pos;
                current_gap_start_rel = (wide_delta_start >= 40'd64) ?
                                        7'd64 : wide_delta_start[6:0];
                current_gap_end_rel = (wide_delta_end >= 40'd64) ?
                                      7'd64 : wide_delta_end[6:0];
            end
        end

        // Relative gap interval for a possible next phase in this word.
        next_gap_start_rel = 7'd64;
        next_gap_end_rel = 7'd64;
        if (gap_present_active && (gap_start_active < 40'd64)) begin
            next_gap_start_rel = gap_start_active[6:0];
            next_gap_end_rel = (gap_end_active >= 40'd64) ?
                               7'd64 : gap_end_active[6:0];
        end

        current_gap_width = current_gap_end_rel - current_gap_start_rel;
        next_gap_width = next_gap_end_rel - next_gap_start_rel;
        current_after_gap_vec = pattern_cursor << current_gap_width;
        next_before_gap_aligned = next_phase_pattern_calc << remaining_rel;
        next_after_shift = remaining_rel + next_gap_width;
        next_after_gap_aligned = next_phase_pattern_calc << next_after_shift;

        txdata_calc = 64'b0;
        valid_mask_calc = 64'b0;
        word_active_calc = running && enable;
        phase_start_calc = word_active_calc && phase_start_pending;

        for (lane = 0; lane < 64; lane = lane + 1) begin
            if (word_active_calc && (lane < remaining_rel)) begin
                if ((lane >= current_gap_start_rel) &&
                    (lane < current_gap_end_rel)) begin
                    txdata_calc[lane] = 1'b0;
                    valid_mask_calc[lane] = 1'b0;
                end else begin
                    valid_mask_calc[lane] = 1'b1;
                    if (lane < current_gap_start_rel)
                        txdata_calc[lane] = pattern_cursor[lane];
                    else
                        txdata_calc[lane] = current_after_gap_vec[lane];
                end
            end else if (word_active_calc && has_next_phase_calc &&
                         (lane >= remaining_rel)) begin
                next_local_pos = lane - remaining_rel;
                if ((next_local_pos >= next_gap_start_rel) &&
                    (next_local_pos < next_gap_end_rel)) begin
                    txdata_calc[lane] = 1'b0;
                    valid_mask_calc[lane] = 1'b0;
                end else begin
                    valid_mask_calc[lane] = 1'b1;
                    if (next_local_pos < next_gap_start_rel)
                        txdata_calc[lane] = next_before_gap_aligned[lane];
                    else
                        txdata_calc[lane] = next_after_gap_aligned[lane];
                end
            end
        end

        if (word_active_calc && (phase_remaining < 40'd64) &&
            has_next_phase_calc)
            phase_start_calc = 1'b1;

        // Word-level next-state calculation.
        running_next = running;
        done_next = done;
        phase_offset_next = phase_offset;
        phase_pos_next = phase_pos;
        phase_pattern_next = phase_pattern;
        pattern_cursor_next = pattern_cursor;
        phase_start_pending_next = phase_start_pending;
        cursor_update_base = pattern_cursor;
        cursor_update_count = 7'd0;
        current_valid_count = 7'd0;
        next_consumed_count = 7'd0;
        next_valid_count = 7'd0;

        if (word_active_calc) begin
            phase_start_pending_next = 1'b0;
            if (phase_remaining > 40'd64) begin
                phase_pos_next = phase_pos + 40'd64;
                current_valid_count = 7'd64 - current_gap_width;
                cursor_update_base = pattern_cursor;
                cursor_update_count = current_valid_count;
                pattern_cursor_next = rotate_sequence(
                    cursor_update_base, cursor_update_count, len_active);
            end else if (phase_remaining == 40'd64) begin
                if (has_next_phase_calc) begin
                    phase_offset_next = next_phase_offset_calc;
                    phase_pos_next = 40'd0;
                    phase_pattern_next = next_phase_pattern_calc;
                    pattern_cursor_next = next_phase_pattern_calc;
                    phase_start_pending_next = 1'b1;
                    if (last_phase_calc && loop_active)
                        done_next = 1'b1;
                end else begin
                    running_next = 1'b0;
                    done_next = 1'b1;
                end
            end else begin
                if (has_next_phase_calc) begin
                    next_consumed_count = 7'd64 - remaining_rel;
                    next_valid_count = next_consumed_count -
                        gap_bits_before(next_consumed_count,
                                        next_gap_start_rel,
                                        next_gap_end_rel);
                    phase_offset_next = next_phase_offset_calc;
                    phase_pos_next = {33'b0, next_consumed_count};
                    phase_pattern_next = next_phase_pattern_calc;
                    cursor_update_base = next_phase_pattern_calc;
                    cursor_update_count = next_valid_count;
                    pattern_cursor_next = rotate_sequence(
                        cursor_update_base, cursor_update_count, len_active);
                    phase_start_pending_next = 1'b0;
                    if (last_phase_calc && loop_active)
                        done_next = 1'b1;
                end else begin
                    running_next = 1'b0;
                    done_next = 1'b1;
                end
            end
        end
    end

    // Output and state commit.  TXDATA, valid_mask, phase/gate source status,
    // and phase_start_pulse all cross the same register boundary.
    always @(posedge clk) begin
        if (rst) begin
            txdata <= 64'b0;
            valid_mask <= 64'b0;
            phase_active <= 1'b0;
            phase_start_pulse <= 1'b0;
            sequence_active <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            phase_offset <= 8'b0;
            current_state <= ST_IDLE;
            len_active <= 8'd63;
            phase_shift_active <= 1'b0;
            loop_active <= 1'b0;
            phase_total_active <= 40'd63;
            gap_start_active <= 40'd0;
            gap_end_active <= 40'd0;
            gap_present_active <= 1'b0;
            phase_pattern <= 127'b0;
            pattern_cursor <= 127'b0;
            phase_pos <= 40'b0;
            running <= 1'b0;
            phase_start_pending <= 1'b0;
        end else if (start && enable && pattern_valid) begin
            txdata <= 64'b0;
            valid_mask <= 64'b0;
            phase_active <= 1'b0;
            phase_start_pulse <= 1'b0;
            sequence_active <= 1'b1;
            busy <= 1'b1;
            done <= 1'b0;
            phase_offset <= 8'b0;
            current_state <= ST_RUN;
            len_active <= pattern_len;
            phase_shift_active <= phase_shift_en;
            loop_active <= loop_en;
            phase_total_active <= phase_total_input;
            gap_start_active <= gap_start_input;
            gap_end_active <= gap_end_input;
            gap_present_active <= (gap_len_bits != 0);
            phase_pattern <= expanded_pattern_input;
            pattern_cursor <= expanded_pattern_input;
            phase_pos <= 40'b0;
            running <= 1'b1;
            phase_start_pending <= 1'b1;
        end else if (!enable) begin
            txdata <= 64'b0;
            valid_mask <= 64'b0;
            phase_active <= 1'b0;
            phase_start_pulse <= 1'b0;
            sequence_active <= 1'b0;
            busy <= 1'b0;
            running <= 1'b0;
            current_state <= ST_IDLE;
        end else if (running) begin
            txdata <= txdata_calc;
            valid_mask <= valid_mask_calc;
            phase_active <= word_active_calc;
            phase_start_pulse <= phase_start_calc;
            sequence_active <= word_active_calc;
            busy <= word_active_calc;
            done <= done_next;
            phase_offset <= phase_offset_next;
            current_state <= word_active_calc ? ST_RUN : ST_DONE;
            phase_pos <= phase_pos_next;
            phase_pattern <= phase_pattern_next;
            pattern_cursor <= pattern_cursor_next;
            running <= running_next;
            phase_start_pending <= phase_start_pending_next;
        end else begin
            txdata <= 64'b0;
            valid_mask <= 64'b0;
            phase_active <= 1'b0;
            phase_start_pulse <= 1'b0;
            sequence_active <= 1'b0;
            busy <= 1'b0;
            current_state <= done ? ST_DONE : ST_IDLE;
        end
    end
endmodule

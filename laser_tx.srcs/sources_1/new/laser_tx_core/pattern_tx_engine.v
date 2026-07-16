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
    reg         pattern_mode_63_active;
    reg         phase_shift_active;
    reg         loop_active;
    reg [39:0]  phase_total_active;
    reg [39:0]  gap_start_active;
    reg [39:0]  gap_end_active;
    reg         gap_present_active;

    // The periodic pattern itself is held constant for a sequence.  A small
    // logical index identifies the next valid pattern bit.  The previous
    // implementation fed a 127-bit variable rotation back into itself every
    // cycle; that made phase_pos -> pattern_cursor a 27-level single-cycle
    // path.  Keeping only the index in the feedback path preserves the bit
    // sequence while reducing the state update to bounded 7-bit arithmetic.
    reg [126:0] pattern_base_active;
    reg [6:0]   pattern_index;
    reg [39:0]  phase_remaining_state;
    reg [39:0]  gap_start_remaining_state;
    reg [39:0]  gap_end_remaining_state;
    reg         running;
    reg         phase_start_pending;

    // Registered word geometry splits the wide phase/gap arithmetic from the
    // pattern-index feedback and TX-data selection.  The descriptor always
    // describes the word emitted in the current cycle; wide counters prepare
    // only the following descriptor.
    reg [1:0]   phase_relation_q; // 0: <64, 1: ==64, 2: >64
    reg [6:0]   remaining_rel_q;
    reg [6:0]   current_gap_start_rel_q;
    reg [6:0]   current_gap_end_rel_q;
    reg [6:0]   initial_gap_start_rel_active;
    reg [6:0]   initial_gap_end_rel_active;

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

    // Dedicated 63-bit rotate network.  Only the 63-bit pattern and the
    // bounded 6-bit index enter this cone; no runtime length or mode test is
    // replicated through the output-word variable select.
    function [126:0] rotate_sequence_63;
        input [62:0] sequence_in;
        input [5:0]  count;
        reg [125:0] doubled;
        reg [125:0] shifted;
        reg [62:0]  rotated;
        begin
            doubled = {sequence_in, sequence_in};
            shifted = doubled >> count;
            rotated = shifted[62:0];
            rotate_sequence_63 = {rotated[0], rotated, rotated};
        end
    endfunction

    // Dedicated 127-bit rotate network.  The modulus is fixed by structure;
    // the full seven-bit index is the only variable-select control.
    function [126:0] rotate_sequence_127;
        input [126:0] sequence_in;
        input [6:0]   count;
        reg [253:0] doubled;
        reg [253:0] shifted;
        begin
            doubled = {sequence_in, sequence_in};
            shifted = doubled >> count;
            rotate_sequence_127 = shifted[126:0];
        end
    endfunction

    // Advance a periodic pattern index by at most one 64-bit word.  The sum
    // can cross the 63-bit modulus twice, but can cross the 127-bit modulus
    // only once.  No divider or general modulo operator is inferred.
    function [6:0] advance_pattern_index;
        input [6:0] index_in;
        input [6:0] count;
        input       sequence_is_63;
        reg [8:0] sum_ext;
        reg [8:0] sub63_ext;
        reg [8:0] sub126_ext;
        reg [8:0] sub127_ext;
        reg       ge63;
        reg       ge126;
        reg       ge127;
        begin
            // All modulo candidates are formed in parallel.  The MSB of an
            // extended unsigned subtraction is the borrow indication for
            // the valid 0..190 sum range, so no separate wide comparators or
            // serial compare-then-subtract chains are required.
            sum_ext    = {2'b00, index_in} + {2'b00, count};
            sub63_ext  = sum_ext - 9'd63;
            sub126_ext = sum_ext - 9'd126;
            sub127_ext = sum_ext - 9'd127;
            ge63       = ~sub63_ext[8];
            ge126      = ~sub126_ext[8];
            ge127      = ~sub127_ext[8];

            if (sequence_is_63) begin
                case ({ge126, ge63})
                    2'b11:  advance_pattern_index = sub126_ext[6:0];
                    2'b01:  advance_pattern_index = sub63_ext[6:0];
                    default: advance_pattern_index = sum_ext[6:0];
                endcase
            end else begin
                advance_pattern_index = ge127 ? sub127_ext[6:0]
                                              : sum_ext[6:0];
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
    reg [39:0] phase_remaining_next;
    reg [39:0] gap_start_remaining_next;
    reg [39:0] gap_end_remaining_next;
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
    reg [7:0]  next_phase_offset_63_comb;
    reg [7:0]  next_phase_offset_127_comb;
    reg         last_phase_calc;
    reg         last_phase_63_comb;
    reg         last_phase_127_comb;
    reg         has_next_phase_calc;
    reg         has_next_phase_63_comb;
    reg         has_next_phase_127_comb;
    reg [126:0] current_pattern_63_comb;
    reg [126:0] current_pattern_127_comb;
    reg [126:0] next_phase_pattern_63_comb;
    reg [126:0] next_phase_pattern_127_comb;
    reg [126:0] current_after_gap_63_comb;
    reg [126:0] current_after_gap_127_comb;
    reg [126:0] next_before_gap_63_comb;
    reg [126:0] next_before_gap_127_comb;
    reg [126:0] next_after_gap_63_comb;
    reg [126:0] next_after_gap_127_comb;
    reg [7:0]   next_after_shift;

    reg [63:0]  word_63_comb;
    reg [63:0]  word_127_comb;
    reg [63:0]  valid_63_comb;
    reg [63:0]  valid_127_comb;
    reg [63:0]  txdata_calc;
    reg [63:0]  valid_mask_calc;
    reg         phase_start_63_comb;
    reg         phase_start_127_comb;
    reg         phase_start_calc;
    reg         word_active_calc;

    reg         running_next;
    reg         done_next;
    reg [7:0]   phase_offset_next;
    reg [6:0]   pattern_index_next;
    reg         phase_start_pending_next;

    reg [1:0]   phase_relation_next_q;
    reg [6:0]   remaining_rel_next_q;
    reg [6:0]   current_gap_start_rel_next_q;
    reg [6:0]   current_gap_end_rel_next_q;

    always @* begin
        last_phase_63_comb = (!phase_shift_active) ||
                             (phase_offset == 8'd62);
        last_phase_127_comb = (!phase_shift_active) ||
                              (phase_offset == 8'd126);
        has_next_phase_63_comb = loop_active || !last_phase_63_comb;
        has_next_phase_127_comb = loop_active || !last_phase_127_comb;
        next_phase_offset_63_comb = last_phase_63_comb ? 8'd0 :
                                                          (phase_offset + 1'b1);
        next_phase_offset_127_comb = last_phase_127_comb ? 8'd0 :
                                                            (phase_offset + 1'b1);

        // The active mode is used only after both fixed-modulus candidates
        // have been built.  It is not an input to either rotate network.
        last_phase_calc = pattern_mode_63_active ? last_phase_63_comb :
                                                   last_phase_127_comb;
        has_next_phase_calc = pattern_mode_63_active ?
                              has_next_phase_63_comb :
                              has_next_phase_127_comb;
        next_phase_offset_calc = pattern_mode_63_active ?
                                 next_phase_offset_63_comb :
                                 next_phase_offset_127_comb;

        current_pattern_63_comb = rotate_sequence_63(
            pattern_base_active[62:0], pattern_index[5:0]);
        current_pattern_127_comb = rotate_sequence_127(
            pattern_base_active, pattern_index);
        next_phase_pattern_63_comb = rotate_sequence_63(
            pattern_base_active[62:0], next_phase_offset_63_comb[5:0]);
        next_phase_pattern_127_comb = rotate_sequence_127(
            pattern_base_active, next_phase_offset_127_comb[6:0]);

        current_gap_start_rel = current_gap_start_rel_q;
        current_gap_end_rel = current_gap_end_rel_q;

        // Relative gap interval for a possible next phase in this word.
        next_gap_start_rel = 7'd64;
        next_gap_end_rel = 7'd64;
        if (gap_present_active) begin
            next_gap_start_rel = initial_gap_start_rel_active;
            next_gap_end_rel = initial_gap_end_rel_active;
        end

        current_gap_width = current_gap_end_rel - current_gap_start_rel;
        next_gap_width = next_gap_end_rel - next_gap_start_rel;
        current_after_gap_63_comb =
            current_pattern_63_comb << current_gap_width;
        current_after_gap_127_comb =
            current_pattern_127_comb << current_gap_width;
        next_before_gap_63_comb =
            next_phase_pattern_63_comb << remaining_rel_q;
        next_before_gap_127_comb =
            next_phase_pattern_127_comb << remaining_rel_q;
        next_after_shift = remaining_rel_q + next_gap_width;
        next_after_gap_63_comb =
            next_phase_pattern_63_comb << next_after_shift;
        next_after_gap_127_comb =
            next_phase_pattern_127_comb << next_after_shift;

        word_63_comb = 64'b0;
        word_127_comb = 64'b0;
        valid_63_comb = 64'b0;
        valid_127_comb = 64'b0;
        word_active_calc = running && enable;
        phase_start_63_comb = word_active_calc && phase_start_pending;
        phase_start_127_comb = word_active_calc && phase_start_pending;

        for (lane = 0; lane < 64; lane = lane + 1) begin
            if (word_active_calc && (lane < remaining_rel_q)) begin
                if ((lane >= current_gap_start_rel) &&
                    (lane < current_gap_end_rel)) begin
                    word_63_comb[lane] = 1'b0;
                    word_127_comb[lane] = 1'b0;
                    valid_63_comb[lane] = 1'b0;
                    valid_127_comb[lane] = 1'b0;
                end else begin
                    valid_63_comb[lane] = 1'b1;
                    valid_127_comb[lane] = 1'b1;
                    if (lane < current_gap_start_rel) begin
                        word_63_comb[lane] = current_pattern_63_comb[lane];
                        word_127_comb[lane] = current_pattern_127_comb[lane];
                    end else begin
                        word_63_comb[lane] = current_after_gap_63_comb[lane];
                        word_127_comb[lane] = current_after_gap_127_comb[lane];
                    end
                end
            end else if (word_active_calc && (lane >= remaining_rel_q)) begin
                next_local_pos = lane - remaining_rel_q;
                if ((next_local_pos >= next_gap_start_rel) &&
                    (next_local_pos < next_gap_end_rel)) begin
                    word_63_comb[lane] = 1'b0;
                    word_127_comb[lane] = 1'b0;
                    valid_63_comb[lane] = 1'b0;
                    valid_127_comb[lane] = 1'b0;
                end else begin
                    if (has_next_phase_63_comb) begin
                        valid_63_comb[lane] = 1'b1;
                        if (next_local_pos < next_gap_start_rel)
                            word_63_comb[lane] = next_before_gap_63_comb[lane];
                        else
                            word_63_comb[lane] = next_after_gap_63_comb[lane];
                    end
                    if (has_next_phase_127_comb) begin
                        valid_127_comb[lane] = 1'b1;
                        if (next_local_pos < next_gap_start_rel)
                            word_127_comb[lane] = next_before_gap_127_comb[lane];
                        else
                            word_127_comb[lane] = next_after_gap_127_comb[lane];
                    end
                end
            end
        end

        if (word_active_calc && (phase_relation_q == 2'd0) &&
            has_next_phase_63_comb)
            phase_start_63_comb = 1'b1;
        if (word_active_calc && (phase_relation_q == 2'd0) &&
            has_next_phase_127_comb)
            phase_start_127_comb = 1'b1;

        // The only 63/127 selection in the output-word datapath is this
        // final mux after both specialized networks are complete.
        txdata_calc = pattern_mode_63_active ? word_63_comb : word_127_comb;
        valid_mask_calc = pattern_mode_63_active ? valid_63_comb :
                                                   valid_127_comb;
        phase_start_calc = pattern_mode_63_active ? phase_start_63_comb :
                                                   phase_start_127_comb;

        // Word-level next-state calculation.
        running_next = running;
        done_next = done;
        phase_offset_next = phase_offset;
        pattern_index_next = pattern_index;
        phase_start_pending_next = phase_start_pending;
        phase_remaining_next = phase_remaining_state;
        gap_start_remaining_next = gap_start_remaining_state;
        gap_end_remaining_next = gap_end_remaining_state;
        current_valid_count = 7'd0;
        next_consumed_count = 7'd0;
        next_valid_count = 7'd0;

        if (word_active_calc) begin
            phase_start_pending_next = 1'b0;
            if (phase_relation_q == 2'd2) begin
                phase_remaining_next = phase_remaining_state - 40'd64;
                gap_start_remaining_next =
                    (gap_start_remaining_state > 40'd64) ?
                    (gap_start_remaining_state - 40'd64) : 40'd0;
                gap_end_remaining_next =
                    (gap_end_remaining_state > 40'd64) ?
                    (gap_end_remaining_state - 40'd64) : 40'd0;
                current_valid_count = 7'd64 - current_gap_width;
                pattern_index_next = advance_pattern_index(
                    pattern_index, current_valid_count,
                    pattern_mode_63_active);
            end else if (phase_relation_q == 2'd1) begin
                if (has_next_phase_calc) begin
                    phase_offset_next = next_phase_offset_calc;
                    phase_remaining_next = phase_total_active;
                    gap_start_remaining_next = gap_start_active;
                    gap_end_remaining_next = gap_end_active;
                    pattern_index_next = next_phase_offset_calc[6:0];
                    phase_start_pending_next = 1'b1;
                    if (last_phase_calc && loop_active)
                        done_next = 1'b1;
                end else begin
                    running_next = 1'b0;
                    done_next = 1'b1;
                end
            end else begin
                if (has_next_phase_calc) begin
                    next_consumed_count = 7'd64 - remaining_rel_q;
                    next_valid_count = next_consumed_count -
                        gap_bits_before(next_consumed_count,
                                        next_gap_start_rel,
                                        next_gap_end_rel);
                    phase_offset_next = next_phase_offset_calc;
                    phase_remaining_next = phase_total_active -
                                           {33'b0, next_consumed_count};
                    gap_start_remaining_next =
                        (gap_start_active > {33'b0, next_consumed_count}) ?
                        (gap_start_active - {33'b0, next_consumed_count}) :
                        40'd0;
                    gap_end_remaining_next =
                        (gap_end_active > {33'b0, next_consumed_count}) ?
                        (gap_end_active - {33'b0, next_consumed_count}) :
                        40'd0;
                    pattern_index_next = advance_pattern_index(
                        next_phase_offset_calc[6:0],
                        next_valid_count, pattern_mode_63_active);
                    phase_start_pending_next = 1'b0;
                    if (last_phase_calc && loop_active)
                        done_next = 1'b1;
                end else begin
                    running_next = 1'b0;
                    done_next = 1'b1;
                end
            end
        end

        // Prepare the following word descriptor.  Only these descriptor
        // registers see the wide phase/gap counter arithmetic.
        if (phase_remaining_next > 40'd64) begin
            phase_relation_next_q = 2'd2;
            remaining_rel_next_q = 7'd64;
        end else if (phase_remaining_next == 40'd64) begin
            phase_relation_next_q = 2'd1;
            remaining_rel_next_q = 7'd64;
        end else begin
            phase_relation_next_q = 2'd0;
            remaining_rel_next_q = phase_remaining_next[6:0];
        end

        current_gap_start_rel_next_q = 7'd64;
        current_gap_end_rel_next_q = 7'd64;
        if (gap_present_active && (gap_end_remaining_next != 40'd0)) begin
            current_gap_start_rel_next_q =
                (gap_start_remaining_next >= 40'd64) ?
                7'd64 : gap_start_remaining_next[6:0];
            current_gap_end_rel_next_q =
                (gap_end_remaining_next >= 40'd64) ?
                7'd64 : gap_end_remaining_next[6:0];
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
            pattern_mode_63_active <= 1'b1;
            phase_shift_active <= 1'b0;
            loop_active <= 1'b0;
            phase_total_active <= 40'd63;
            gap_start_active <= 40'd0;
            gap_end_active <= 40'd0;
            gap_present_active <= 1'b0;
            pattern_base_active <= 127'b0;
            pattern_index <= 7'b0;
            phase_remaining_state <= 40'd63;
            gap_start_remaining_state <= 40'd0;
            gap_end_remaining_state <= 40'd0;
            running <= 1'b0;
            phase_start_pending <= 1'b0;
            phase_relation_q <= 2'd0;
            remaining_rel_q <= 7'd63;
            current_gap_start_rel_q <= 7'd64;
            current_gap_end_rel_q <= 7'd64;
            initial_gap_start_rel_active <= 7'd64;
            initial_gap_end_rel_active <= 7'd64;
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
            pattern_mode_63_active <= (pattern_len == 8'd63);
            phase_shift_active <= phase_shift_en;
            loop_active <= loop_en;
            phase_total_active <= phase_total_input;
            gap_start_active <= gap_start_input;
            gap_end_active <= gap_end_input;
            gap_present_active <= (gap_len_bits != 0);
            pattern_base_active <= expanded_pattern_input;
            pattern_index <= 7'b0;
            phase_remaining_state <= phase_total_input;
            gap_start_remaining_state <= gap_start_input;
            gap_end_remaining_state <= gap_end_input;
            running <= 1'b1;
            phase_start_pending <= 1'b1;
            phase_relation_q <= (phase_total_input > 40'd64) ? 2'd2 :
                                ((phase_total_input == 40'd64) ? 2'd1 : 2'd0);
            remaining_rel_q <= (phase_total_input >= 40'd64) ?
                               7'd64 : phase_total_input[6:0];
            current_gap_start_rel_q <=
                ((gap_len_bits != 0) && (gap_start_input < 40'd64)) ?
                gap_start_input[6:0] : 7'd64;
            current_gap_end_rel_q <=
                ((gap_len_bits != 0) && (gap_end_input < 40'd64)) ?
                gap_end_input[6:0] : 7'd64;
            initial_gap_start_rel_active <=
                ((gap_len_bits != 0) && (gap_start_input < 40'd64)) ?
                gap_start_input[6:0] : 7'd64;
            initial_gap_end_rel_active <=
                ((gap_len_bits != 0) && (gap_end_input < 40'd64)) ?
                gap_end_input[6:0] : 7'd64;
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
            pattern_index <= pattern_index_next;
            phase_remaining_state <= phase_remaining_next;
            gap_start_remaining_state <= gap_start_remaining_next;
            gap_end_remaining_state <= gap_end_remaining_next;
            running <= running_next;
            phase_start_pending <= phase_start_pending_next;
            phase_relation_q <= phase_relation_next_q;
            remaining_rel_q <= remaining_rel_next_q;
            current_gap_start_rel_q <= current_gap_start_rel_next_q;
            current_gap_end_rel_q <= current_gap_end_rel_next_q;
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

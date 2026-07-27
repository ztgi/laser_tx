`timescale 1ns/1ps

// TX sequence V2 scheduler. Delay bits always drive data and valid low. Each
// repeated pattern restarts from the active phase's precomputed pattern image.
module pattern_tx_engine #(parameter integer MAX_REPEAT_CYCLES = 16) (
    input wire clk, input wire rst, input wire start, input wire enable,
    input wire pattern_valid, input wire [126:0] base_pattern,
    input wire [7:0] pattern_len, input wire [4:0] repeat_cycles,
    input wire [7:0] head_delay_bits, input wire [119:0] gap_len_bits,
    input wire phase_shift_en, input wire loop_en,
    input wire eom_geometry_armed, input wire eom_tx_start_level,
    input wire eom_request_valid,
    input wire eom_done_pulse,
    output reg engine_start_accept_pulse,
    output reg [63:0] txdata, output reg [63:0] valid_mask,
    output reg phase_active, output reg phase_start_pulse,
    output reg sequence_active, output reg busy, output reg done,
    output reg [7:0] phase_offset, output reg [7:0] current_state
);
    localparam [7:0] ST_IDLE=0, ST_PRECOMPUTE=1, ST_ARM=2, ST_HEAD=3,
                     ST_PATTERN=4, ST_GAP=5, ST_WAIT_EOM=6,
                     ST_DONE=7, ST_ERROR=8'h80;
    localparam SEG_DELAY=1'b0, SEG_PATTERN=1'b1;

    // A descriptor names the segment following the current pattern. The
    // pattern field is already phase-rotated and the delay field is the exact
    // delay before that segment, so neither the full gap array nor phase/repeat
    // scheduling enters the 64-lane output mux.
    localparam integer DESC_PATTERN_LSB = 0;
    localparam integer DESC_GAP_PHASE   = 127;
    localparam integer DESC_DELAY_LSB   = 128;
    localparam integer DESC_PHASE_LSB   = 137;
    localparam integer DESC_REPEAT_LSB  = 145;
    localparam integer DESC_VALID       = 149;
    localparam integer DESC_WIDTH       = 150;
    localparam integer WORD_PLAN_WIDTH  = 128;
    localparam integer APPEND_DATA_LSB  = 0;
    localparam integer APPEND_MASK_LSB  = 64;
    localparam integer APPEND_COUNT_LSB = 128;
    localparam integer APPEND_PHASE_START = 136;
    localparam integer APPEND_PLAN_WIDTH = 137;

    reg segment_state, running;
    reg pattern_mode_63_active, phase_shift_active, loop_active;
    reg [4:0] repeat_count_active;
    reg [7:0] head_delay_active;
    reg [119:0] gap_len_active;
    reg [126:0] phase_zero_pattern_state;
    reg [126:0] pattern_stream_state;
    reg [DESC_WIDTH-1:0] next_descriptor_state;
    reg [DESC_WIDTH-1:0] after_descriptor_state;
    reg [DESC_WIDTH-1:0] third_descriptor_state;
    // Registered output plans isolate the 64-lane TX packer from the wide
    // descriptor and its phase/repeat/gap scheduling logic.
    reg [63:0] pattern_word_data_state;
    reg [63:0] pattern_word_mask_state;
    reg [63:0] append_word_data_state;
    reg [63:0] append_word_mask_state;
    reg [7:0] append_word_count_state;
    reg append_phase_start_state;
    reg [3:0] repeat_index_state;
    reg [7:0] phase_index_state;
    // Retained as a local debug/state cursor, but it no longer drives the
    // 64-lane output data selection.
    reg [6:0] pattern_index_state;
    reg [7:0] pattern_remaining_state;
    reg [8:0] delay_remaining_state;
    reg delay_has_pattern_state, delay_phase_active_state;
    reg pattern_start_pending;

    reg waiting_geometry, waiting_eom;
    reg eom_request_active, eom_complete_seen;

    function [7:0] gap_value;
        input [119:0] gaps;
        input [3:0] index;
        begin
            case(index)
                0: gap_value=gaps[7:0];       1: gap_value=gaps[15:8];
                2: gap_value=gaps[23:16];     3: gap_value=gaps[31:24];
                4: gap_value=gaps[39:32];     5: gap_value=gaps[47:40];
                6: gap_value=gaps[55:48];     7: gap_value=gaps[63:56];
                8: gap_value=gaps[71:64];     9: gap_value=gaps[79:72];
                10: gap_value=gaps[87:80];    11: gap_value=gaps[95:88];
                12: gap_value=gaps[103:96];   13: gap_value=gaps[111:104];
                14: gap_value=gaps[119:112];  default: gap_value=0;
            endcase
        end
    endfunction

    function [126:0] normalize_phase_zero;
        input [126:0] value;
        input is_63;
        begin
            normalize_phase_zero = is_63 ?
                {value[0], value[62:0], value[62:0]} : value;
        end
    endfunction

    // Advancing one phase is a fixed one-bit permutation. It replaces the
    // variable 63/127-bit rotate formerly driven by phase_index_state.
    function [126:0] rotate_phase_once;
        input [126:0] value;
        input is_63;
        reg [62:0] rotated63;
        begin
            if (is_63) begin
                rotated63 = {value[0], value[62:1]};
                rotate_phase_once =
                    {rotated63[0], rotated63, rotated63};
            end else begin
                rotate_phase_once = {value[0], value[126:1]};
            end
        end
    endfunction

    function [6:0] advance_index;
        input [6:0] index_in;
        input [6:0] count;
        input is_63;
        reg [8:0] sum, sub63, sub126, sub127;
        begin
            sum={2'b0,index_in}+{2'b0,count};
            sub63=sum-63; sub126=sum-126; sub127=sum-127;
            if(is_63) begin
                if(!sub126[8]) advance_index=sub126[6:0];
                else if(!sub63[8]) advance_index=sub63[6:0];
                else advance_index=sum[6:0];
            end else begin
                advance_index=!sub127[8]?sub127[6:0]:sum[6:0];
            end
        end
    endfunction

    function [DESC_WIDTH-1:0] make_next_descriptor;
        input [3:0] current_repeat;
        input [7:0] current_phase;
        input [126:0] current_phase_pattern;
        input [4:0] repeat_count;
        input phase_shift;
        input loop_mode;
        input mode_63;
        input [7:0] head_delay;
        input [119:0] gaps;
        input [126:0] phase_zero_pattern;
        reg [DESC_WIDTH-1:0] descriptor;
        reg [3:0] next_repeat;
        reg [7:0] next_phase;
        reg [8:0] next_delay;
        reg next_gap_phase;
        reg [126:0] next_pattern;
        begin
            descriptor=0;
            next_repeat=0;
            next_phase=current_phase;
            next_delay=0;
            next_gap_phase=0;
            next_pattern=current_phase_pattern;
            if ({1'b0,current_repeat}+1 < repeat_count) begin
                descriptor[DESC_VALID]=1'b1;
                next_repeat=current_repeat+1'b1;
                next_delay={1'b0,gap_value(gaps,current_repeat)};
                next_gap_phase=1'b1;
            end else if (phase_shift &&
                         ((mode_63 && current_phase<8'd62) ||
                          (!mode_63 && current_phase<8'd126))) begin
                descriptor[DESC_VALID]=1'b1;
                next_repeat=0;
                next_phase=current_phase+1'b1;
                next_delay={1'b0,head_delay};
                next_pattern=rotate_phase_once(current_phase_pattern,mode_63);
            end else if (loop_mode) begin
                descriptor[DESC_VALID]=1'b1;
                next_repeat=0;
                next_phase=0;
                next_delay={1'b0,head_delay};
                next_pattern=phase_zero_pattern;
            end
            descriptor[DESC_PATTERN_LSB +: 127]=next_pattern;
            descriptor[DESC_GAP_PHASE]=next_gap_phase;
            descriptor[DESC_DELAY_LSB +: 9]=next_delay;
            descriptor[DESC_PHASE_LSB +: 8]=next_phase;
            descriptor[DESC_REPEAT_LSB +: 4]=next_repeat;
            make_next_descriptor=descriptor;
        end
    endfunction

    function [WORD_PLAN_WIDTH-1:0] make_pattern_word_plan;
        input [126:0] pattern_stream;
        input [7:0] pattern_remaining;
        integer word_lane;
        begin
            make_pattern_word_plan=0;
            for (word_lane=0;word_lane<64;word_lane=word_lane+1) begin
                if (word_lane<pattern_remaining) begin
                    make_pattern_word_plan[word_lane]=
                        pattern_stream[word_lane];
                    make_pattern_word_plan[64+word_lane]=1'b1;
                end
            end
        end
    endfunction

    // Prepare the portion of the following pattern that can share the current
    // 64-bit TX word. This work is registered with the segment state, so the
    // active output cycle does not contain descriptor decode plus a 64-lane
    // variable select.
    function [APPEND_PLAN_WIDTH-1:0] make_append_word_plan;
        input [7:0] current_pattern_remaining;
        input [DESC_WIDTH-1:0] following_descriptor;
        integer current_count;
        integer room_count;
        integer append_start;
        integer append_count;
        reg [126:0] following_pattern;
        reg [8:0] following_delay;
        reg [3:0] following_repeat;
        reg [63:0] shifted_append_data;
        reg [63:0] shifted_append_mask;
        begin
            make_append_word_plan=0;
            current_count=current_pattern_remaining>=64?
                          64:current_pattern_remaining;
            room_count=64-current_count;
            following_pattern=
                following_descriptor[DESC_PATTERN_LSB +: 127];
            following_delay=
                following_descriptor[DESC_DELAY_LSB +: 9];
            following_repeat=
                following_descriptor[DESC_REPEAT_LSB +: 4];
            if (following_descriptor[DESC_VALID] &&
                current_count!=0 &&
                following_delay<room_count) begin
                append_start=current_count+following_delay;
                append_count=room_count-following_delay;
                // A real append always follows at least one bit from the
                // current pattern, hence room_count is at most 63. Both
                // supported pattern lengths (63/127) therefore contain every
                // bit that can be appended. Build the aligned word with one
                // barrel shift instead of 64 replicated lane compares and
                // variable bit selects.
                shifted_append_data=
                    following_pattern[63:0] << append_start;
                shifted_append_mask=
                    64'hFFFF_FFFF_FFFF_FFFF << append_start;
                make_append_word_plan[
                    APPEND_DATA_LSB +: 64]=shifted_append_data;
                make_append_word_plan[
                    APPEND_MASK_LSB +: 64]=shifted_append_mask;
                make_append_word_plan[
                    APPEND_COUNT_LSB +: 8]=append_count[7:0];
                make_append_word_plan[APPEND_PHASE_START]=
                    (following_repeat==0)&&(append_count!=0);
            end
        end
    endfunction

    wire next_valid_state=next_descriptor_state[DESC_VALID];
    wire [3:0] next_repeat_state=
        next_descriptor_state[DESC_REPEAT_LSB +: 4];
    wire [7:0] next_phase_state=
        next_descriptor_state[DESC_PHASE_LSB +: 8];
    wire [8:0] next_delay_state=
        next_descriptor_state[DESC_DELAY_LSB +: 9];
    wire next_gap_phase_state=next_descriptor_state[DESC_GAP_PHASE];
    wire [126:0] next_pattern_state=
        next_descriptor_state[DESC_PATTERN_LSB +: 127];

    // The descriptor look-ahead queue is registered. In particular, the
    // descriptor following "next" is not rebuilt in the same cycle that an
    // append data/mask plan is generated.
    wire [DESC_WIDTH-1:0] after_descriptor_calc =
        after_descriptor_state;
    wire after_valid_calc=after_descriptor_calc[DESC_VALID];
    wire [3:0] after_repeat_calc=
        after_descriptor_calc[DESC_REPEAT_LSB +: 4];
    wire [7:0] after_phase_calc=
        after_descriptor_calc[DESC_PHASE_LSB +: 8];
    wire [8:0] after_delay_calc=
        after_descriptor_calc[DESC_DELAY_LSB +: 9];
    wire after_gap_phase_calc=after_descriptor_calc[DESC_GAP_PHASE];
    wire [126:0] after_pattern_calc=
        after_descriptor_calc[DESC_PATTERN_LSB +: 127];

    wire [DESC_WIDTH-1:0] third_descriptor_calc =
        third_descriptor_state;
    wire third_valid_calc=third_descriptor_calc[DESC_VALID];
    wire [3:0] third_repeat_calc=
        third_descriptor_calc[DESC_REPEAT_LSB +: 4];
    wire [7:0] third_phase_calc=
        third_descriptor_calc[DESC_PHASE_LSB +: 8];
    wire [126:0] third_pattern_calc=
        third_descriptor_calc[DESC_PATTERN_LSB +: 127];
    wire [DESC_WIDTH-1:0] fourth_descriptor_calc =
        make_next_descriptor(
            third_repeat_calc, third_phase_calc, third_pattern_calc,
            repeat_count_active, phase_shift_active, loop_active,
            pattern_mode_63_active, head_delay_active, gap_len_active,
            phase_zero_pattern_state);
    wire fourth_valid_calc=fourth_descriptor_calc[DESC_VALID];
    wire [3:0] fourth_repeat_calc=
        fourth_descriptor_calc[DESC_REPEAT_LSB +: 4];
    wire [7:0] fourth_phase_calc=
        fourth_descriptor_calc[DESC_PHASE_LSB +: 8];
    wire [126:0] fourth_pattern_calc=
        fourth_descriptor_calc[DESC_PATTERN_LSB +: 127];
    wire [DESC_WIDTH-1:0] fifth_descriptor_calc =
        make_next_descriptor(
            fourth_repeat_calc, fourth_phase_calc, fourth_pattern_calc,
            repeat_count_active, phase_shift_active, loop_active,
            pattern_mode_63_active, head_delay_active, gap_len_active,
            phase_zero_pattern_state);

    wire task_mode_63=(pattern_len==8'd63);
    wire [126:0] task_phase_zero_pattern=
        normalize_phase_zero(base_pattern,task_mode_63);
    wire [DESC_WIDTH-1:0] task_next_descriptor=
        make_next_descriptor(
            4'd0,8'd0,task_phase_zero_pattern,repeat_cycles,
            phase_shift_en,loop_en,task_mode_63,head_delay_bits,
            gap_len_bits,task_phase_zero_pattern);
    wire [DESC_WIDTH-1:0] task_after_descriptor=
        make_next_descriptor(
            task_next_descriptor[DESC_REPEAT_LSB +: 4],
            task_next_descriptor[DESC_PHASE_LSB +: 8],
            task_next_descriptor[DESC_PATTERN_LSB +: 127],
            repeat_cycles,phase_shift_en,loop_en,task_mode_63,
            head_delay_bits,gap_len_bits,task_phase_zero_pattern);
    wire [DESC_WIDTH-1:0] task_third_descriptor=
        make_next_descriptor(
            task_after_descriptor[DESC_REPEAT_LSB +: 4],
            task_after_descriptor[DESC_PHASE_LSB +: 8],
            task_after_descriptor[DESC_PATTERN_LSB +: 127],
            repeat_cycles,phase_shift_en,loop_en,task_mode_63,
            head_delay_bits,gap_len_bits,task_phase_zero_pattern);

    reg [63:0] txdata_calc, valid_calc;
    reg phase_active_calc, phase_start_calc;
    reg running_next, done_next, segment_next;
    reg [3:0] repeat_next;
    reg [7:0] phase_next;
    reg [6:0] index_next;
    reg [7:0] pattern_remaining_next;
    reg [8:0] delay_remaining_next;
    reg delay_has_pattern_next, delay_phase_active_next;
    reg pattern_start_pending_next;
    reg [126:0] pattern_stream_next;
    reg [DESC_WIDTH-1:0] next_descriptor_next;
    reg [DESC_WIDTH-1:0] after_descriptor_next;
    reg [DESC_WIDTH-1:0] third_descriptor_next;
    reg [DESC_WIDTH-1:0] append_source_descriptor_next;
    wire [WORD_PLAN_WIDTH-1:0] pattern_word_plan_next =
        (running_next && segment_next==SEG_PATTERN) ?
        make_pattern_word_plan(
            pattern_stream_next,pattern_remaining_next) : 0;
    wire [APPEND_PLAN_WIDTH-1:0] append_word_plan_next =
        (running_next && segment_next==SEG_PATTERN) ?
        make_append_word_plan(
            pattern_remaining_next,append_source_descriptor_next) : 0;
    wire [WORD_PLAN_WIDTH-1:0] task_pattern_word_plan =
        make_pattern_word_plan(task_phase_zero_pattern,pattern_len);
    wire [APPEND_PLAN_WIDTH-1:0] task_append_word_plan =
        make_append_word_plan(pattern_len,task_next_descriptor);
    integer lane, first_count, available, delay_count;
    integer second_count, active_pattern_len;

    // The output packer consumes only registered, already aligned segment
    // descriptors. Phase/gap/loop scheduling is isolated in the descriptor
    // builder above and cannot directly select any TX output lane.
    always @* begin
        txdata_calc=0;
        valid_calc=0;
        phase_active_calc=0;
        phase_start_calc=0;
        running_next=running;
        done_next=done;
        segment_next=segment_state;
        repeat_next=repeat_index_state;
        phase_next=phase_index_state;
        index_next=pattern_index_state;
        pattern_remaining_next=pattern_remaining_state;
        delay_remaining_next=delay_remaining_state;
        delay_has_pattern_next=delay_has_pattern_state;
        delay_phase_active_next=delay_phase_active_state;
        pattern_start_pending_next=pattern_start_pending;
        pattern_stream_next=pattern_stream_state;
        next_descriptor_next=next_descriptor_state;
        after_descriptor_next=after_descriptor_state;
        third_descriptor_next=third_descriptor_state;
        append_source_descriptor_next=next_descriptor_state;
        first_count=0;
        available=0;
        delay_count=0;
        second_count=0;
        active_pattern_len=pattern_mode_63_active?63:127;

        if (running && enable && segment_state==SEG_PATTERN) begin
            first_count=pattern_remaining_state>=64?
                        64:pattern_remaining_state;
            txdata_calc=pattern_word_data_state;
            valid_calc=pattern_word_mask_state;
            phase_active_calc=1'b1;
            phase_start_calc=pattern_start_pending;
            pattern_start_pending_next=1'b0;

            if (pattern_remaining_state>64) begin
                pattern_stream_next=pattern_stream_state>>64;
                pattern_remaining_next=pattern_remaining_state-64;
                index_next=advance_index(
                    pattern_index_state,7'd64,pattern_mode_63_active);
            end else begin
                available=64-first_count;
                if (append_word_count_state!=0) begin
                    second_count=append_word_count_state;
                    txdata_calc=
                        pattern_word_data_state|append_word_data_state;
                    valid_calc=
                        pattern_word_mask_state|append_word_mask_state;
                    if (append_phase_start_state)
                        phase_start_calc=1'b1;
                    repeat_next=next_repeat_state;
                    phase_next=next_phase_state;
                    if (second_count<active_pattern_len) begin
                        segment_next=SEG_PATTERN;
                        pattern_stream_next=
                            next_pattern_state>>second_count;
                        pattern_remaining_next=
                            active_pattern_len-second_count;
                        index_next=second_count[6:0];
                        next_descriptor_next=after_descriptor_calc;
                        after_descriptor_next=third_descriptor_calc;
                        third_descriptor_next=fourth_descriptor_calc;
                        append_source_descriptor_next=
                            after_descriptor_calc;
                    end else if (after_valid_calc) begin
                        repeat_next=after_repeat_calc;
                        phase_next=after_phase_calc;
                        pattern_stream_next=after_pattern_calc;
                        pattern_remaining_next=active_pattern_len;
                        index_next=0;
                        next_descriptor_next=third_descriptor_calc;
                        after_descriptor_next=fourth_descriptor_calc;
                        third_descriptor_next=fifth_descriptor_calc;
                        append_source_descriptor_next=
                            third_descriptor_calc;
                        if (after_delay_calc==0) begin
                            segment_next=SEG_PATTERN;
                            pattern_start_pending_next=
                                after_repeat_calc==0;
                        end else begin
                            segment_next=SEG_DELAY;
                            delay_remaining_next=after_delay_calc;
                            delay_has_pattern_next=1'b1;
                            delay_phase_active_next=
                                after_gap_phase_calc;
                        end
                    end else begin
                        running_next=1'b0;
                        done_next=1'b1;
                    end
                end else if (next_valid_state) begin
                    repeat_next=next_repeat_state;
                    phase_next=next_phase_state;
                    pattern_stream_next=next_pattern_state;
                    pattern_remaining_next=active_pattern_len;
                    index_next=0;
                    next_descriptor_next=after_descriptor_calc;
                    after_descriptor_next=third_descriptor_calc;
                    third_descriptor_next=fourth_descriptor_calc;
                    append_source_descriptor_next=after_descriptor_calc;
                    if (next_delay_state==available) begin
                        segment_next=SEG_PATTERN;
                        pattern_start_pending_next=next_repeat_state==0;
                    end else begin
                        segment_next=SEG_DELAY;
                        delay_remaining_next=next_delay_state-available;
                        delay_has_pattern_next=1'b1;
                        delay_phase_active_next=next_gap_phase_state;
                    end
                end else begin
                    running_next=1'b0;
                    done_next=1'b1;
                end
            end
        end else if (running && enable) begin
            delay_count=delay_remaining_state>=64?
                        64:delay_remaining_state;
            available=64-delay_count;
            phase_active_calc=delay_phase_active_state;
            if (delay_remaining_state>64) begin
                delay_remaining_next=delay_remaining_state-64;
            end else if (delay_has_pattern_state) begin
                second_count=available;
                if (second_count>active_pattern_len)
                    second_count=active_pattern_len;
                for (lane=0;lane<64;lane=lane+1) begin
                    if (lane>=delay_count &&
                        lane<delay_count+second_count) begin
                        txdata_calc[lane]=
                            pattern_stream_state[lane-delay_count];
                        valid_calc[lane]=1'b1;
                    end
                end
                phase_start_calc=
                    (repeat_index_state==0)&&(second_count!=0);
                phase_active_calc=
                    phase_active_calc||(second_count!=0);
                if (second_count==0) begin
                    segment_next=SEG_PATTERN;
                    pattern_start_pending_next=repeat_index_state==0;
                end else if (second_count<active_pattern_len) begin
                    segment_next=SEG_PATTERN;
                    pattern_stream_next=
                        pattern_stream_state>>second_count;
                    index_next=second_count[6:0];
                    pattern_remaining_next=
                        active_pattern_len-second_count;
                    pattern_start_pending_next=1'b0;
                end else if (next_valid_state) begin
                    repeat_next=next_repeat_state;
                    phase_next=next_phase_state;
                    pattern_stream_next=next_pattern_state;
                    pattern_remaining_next=active_pattern_len;
                    index_next=0;
                    next_descriptor_next=after_descriptor_calc;
                    after_descriptor_next=third_descriptor_calc;
                    third_descriptor_next=fourth_descriptor_calc;
                    append_source_descriptor_next=after_descriptor_calc;
                    if (next_delay_state==0) begin
                        segment_next=SEG_PATTERN;
                        pattern_start_pending_next=next_repeat_state==0;
                    end else begin
                        segment_next=SEG_DELAY;
                        delay_remaining_next=next_delay_state;
                        delay_has_pattern_next=1'b1;
                        delay_phase_active_next=next_gap_phase_state;
                    end
                end else begin
                    running_next=1'b0;
                    done_next=1'b1;
                end
            end else begin
                running_next=1'b0;
                done_next=1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            txdata<=0;
            valid_mask<=0;
            phase_active<=0;
            phase_start_pulse<=0;
            sequence_active<=0;
            busy<=0;
            done<=0;
            phase_offset<=0;
            current_state<=ST_IDLE;
            engine_start_accept_pulse<=0;
            segment_state<=SEG_DELAY;
            running<=0;
            pattern_mode_63_active<=1;
            phase_shift_active<=0;
            loop_active<=0;
            repeat_count_active<=1;
            head_delay_active<=0;
            gap_len_active<=0;
            phase_zero_pattern_state<=0;
            pattern_stream_state<=0;
            next_descriptor_state<=0;
            after_descriptor_state<=0;
            third_descriptor_state<=0;
            pattern_word_data_state<=0;
            pattern_word_mask_state<=0;
            append_word_data_state<=0;
            append_word_mask_state<=0;
            append_word_count_state<=0;
            append_phase_start_state<=0;
            repeat_index_state<=0;
            phase_index_state<=0;
            pattern_index_state<=0;
            pattern_remaining_state<=63;
            delay_remaining_state<=0;
            delay_has_pattern_state<=0;
            delay_phase_active_state<=0;
            pattern_start_pending<=0;
            waiting_geometry<=0;
            waiting_eom<=0;
            eom_request_active<=0;
            eom_complete_seen<=0;
        end else begin
            engine_start_accept_pulse<=1'b0;
            phase_start_pulse<=1'b0;
            if (eom_done_pulse)
                eom_complete_seen<=1'b1;

            if (start && !busy) begin
                txdata<=0;
                valid_mask<=0;
                phase_active<=0;
                done<=0;
                if (enable && pattern_valid &&
                    repeat_cycles>=1 &&
                    repeat_cycles<=MAX_REPEAT_CYCLES &&
                    (pattern_len==63 || pattern_len==127)) begin
                    engine_start_accept_pulse<=1'b1;
                    sequence_active<=1'b1;
                    busy<=1'b1;
                    current_state<=ST_PRECOMPUTE;
                    waiting_geometry<=1'b1;
                    waiting_eom<=1'b0;
                    running<=1'b0;
                    eom_request_active<=1'b0;
                    eom_complete_seen<=1'b0;
                    segment_state<=
                        head_delay_bits==0?SEG_PATTERN:SEG_DELAY;
                    pattern_mode_63_active<=task_mode_63;
                    phase_shift_active<=phase_shift_en;
                    loop_active<=loop_en;
                    repeat_count_active<=repeat_cycles;
                    head_delay_active<=head_delay_bits;
                    gap_len_active<=gap_len_bits;
                    phase_zero_pattern_state<=task_phase_zero_pattern;
                    pattern_stream_state<=task_phase_zero_pattern;
                    next_descriptor_state<=task_next_descriptor;
                    after_descriptor_state<=task_after_descriptor;
                    third_descriptor_state<=task_third_descriptor;
                    if (head_delay_bits==0) begin
                        pattern_word_data_state<=
                            task_pattern_word_plan[63:0];
                        pattern_word_mask_state<=
                            task_pattern_word_plan[127:64];
                        append_word_data_state<=
                            task_append_word_plan[
                                APPEND_DATA_LSB +: 64];
                        append_word_mask_state<=
                            task_append_word_plan[
                                APPEND_MASK_LSB +: 64];
                        append_word_count_state<=
                            task_append_word_plan[
                                APPEND_COUNT_LSB +: 8];
                        append_phase_start_state<=
                            task_append_word_plan[APPEND_PHASE_START];
                    end else begin
                        pattern_word_data_state<=0;
                        pattern_word_mask_state<=0;
                        append_word_data_state<=0;
                        append_word_mask_state<=0;
                        append_word_count_state<=0;
                        append_phase_start_state<=0;
                    end
                    repeat_index_state<=0;
                    phase_index_state<=0;
                    pattern_index_state<=0;
                    pattern_remaining_state<=pattern_len;
                    delay_remaining_state<={1'b0,head_delay_bits};
                    delay_has_pattern_state<=1'b1;
                    delay_phase_active_state<=1'b0;
                    pattern_start_pending<=head_delay_bits==0;
                    phase_offset<=0;
                end else begin
                    sequence_active<=0;
                    busy<=0;
                    running<=0;
                    waiting_geometry<=0;
                    waiting_eom<=0;
                    current_state<=ST_ERROR;
                end
            end else if (!enable) begin
                txdata<=0;
                valid_mask<=0;
                phase_active<=0;
                sequence_active<=0;
                busy<=0;
                running<=0;
                waiting_geometry<=0;
                waiting_eom<=0;
                eom_request_active<=0;
                eom_complete_seen<=0;
                pattern_word_data_state<=0;
                pattern_word_mask_state<=0;
                append_word_data_state<=0;
                append_word_mask_state<=0;
                append_word_count_state<=0;
                append_phase_start_state<=0;
                current_state<=ST_IDLE;
            end else if (waiting_geometry) begin
                txdata<=0;
                valid_mask<=0;
                phase_active<=0;
                if (eom_geometry_armed && eom_tx_start_level) begin
                    // This TX word boundary is the first output boundary. The
                    // related EOM controller labels the same physical edge as
                    // task tick zero.
                    waiting_geometry<=1'b0;
                    eom_request_active<=eom_request_valid;
                    running<=1'b1;
                    busy<=1'b1;
                    sequence_active<=1'b1;
                    current_state<=
                        head_delay_active==0?ST_PATTERN:ST_HEAD;
                end
            end else if (running) begin
                txdata<=txdata_calc;
                valid_mask<=valid_calc;
                phase_active<=phase_active_calc;
                phase_start_pulse<=phase_start_calc;
                phase_offset<=phase_next;
                segment_state<=segment_next;
                repeat_index_state<=repeat_next;
                phase_index_state<=phase_next;
                pattern_index_state<=index_next;
                pattern_remaining_state<=pattern_remaining_next;
                delay_remaining_state<=delay_remaining_next;
                delay_has_pattern_state<=delay_has_pattern_next;
                delay_phase_active_state<=delay_phase_active_next;
                pattern_start_pending<=pattern_start_pending_next;
                pattern_stream_state<=pattern_stream_next;
                next_descriptor_state<=next_descriptor_next;
                after_descriptor_state<=after_descriptor_next;
                third_descriptor_state<=third_descriptor_next;
                pattern_word_data_state<=pattern_word_plan_next[63:0];
                pattern_word_mask_state<=pattern_word_plan_next[127:64];
                append_word_data_state<=
                    append_word_plan_next[APPEND_DATA_LSB +: 64];
                append_word_mask_state<=
                    append_word_plan_next[APPEND_MASK_LSB +: 64];
                append_word_count_state<=
                    append_word_plan_next[APPEND_COUNT_LSB +: 8];
                append_phase_start_state<=
                    append_word_plan_next[APPEND_PHASE_START];
                running<=running_next;
                if (!running_next && done_next) begin
                    if (eom_request_active &&
                        !(eom_complete_seen || eom_done_pulse)) begin
                        waiting_eom<=1'b1;
                        busy<=1'b1;
                        done<=1'b0;
                        sequence_active<=1'b1;
                        current_state<=ST_WAIT_EOM;
                    end else begin
                        waiting_eom<=1'b0;
                        busy<=1'b0;
                        done<=1'b1;
                        sequence_active<=1'b0;
                        current_state<=ST_DONE;
                    end
                end else begin
                    busy<=1'b1;
                    done<=1'b0;
                    sequence_active<=1'b1;
                    current_state<=segment_next==SEG_PATTERN?
                                   ST_PATTERN:
                                   (delay_phase_active_next?ST_GAP:ST_HEAD);
                end
            end else if (waiting_eom) begin
                txdata<=0;
                valid_mask<=0;
                phase_active<=0;
                if (eom_complete_seen || eom_done_pulse) begin
                    waiting_eom<=1'b0;
                    busy<=1'b0;
                    done<=1'b1;
                    sequence_active<=1'b0;
                    current_state<=ST_DONE;
                end
            end else begin
                txdata<=0;
                valid_mask<=0;
                phase_active<=0;
                sequence_active<=0;
                busy<=0;
                current_state<=done?ST_DONE:ST_IDLE;
            end
        end
    end
endmodule

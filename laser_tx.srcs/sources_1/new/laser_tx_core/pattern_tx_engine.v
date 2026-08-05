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
    output reg first_sequence_word_fire,
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
    localparam integer META_WIDTH = 226;
    localparam integer META_BASE_PATTERN_LSB = 0;
    localparam integer META_BASE_START_LSB = 64;
    localparam integer META_BASE_COUNT_LSB = 70;
    localparam integer META_APPEND_PATTERN_LSB = 77;
    localparam integer META_APPEND_START_LSB = 141;
    localparam integer META_APPEND_COUNT_LSB = 147;
    localparam integer META_PHASE_ACTIVE = 154;
    localparam integer META_PHASE_START = 155;
    localparam integer META_FIRST_SEQUENCE = 156;
    localparam integer META_LAST = 157;
    localparam integer META_PHASE_AFTER_LSB = 158;
    localparam integer META_STATE_AFTER_LSB = 166;
    localparam integer META_REPEAT_LSB = 174;
    localparam integer META_PHASE_LSB = 178;
    localparam integer META_PATTERN_INDEX_LSB = 186;
    localparam integer META_DESCRIPTOR_ID_LSB = 193;
    localparam integer META_RESERVED_LSB = 201;

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
    // Three elastic stages isolate the TX output edge from descriptor decode:
    // N-2 captures only narrow append/base metadata, N-1 aligns and registers
    // a complete word plan, and N consumes that registered plan.
    reg append_meta_valid_q;
    reg [63:0] base_pattern_meta_q;
    reg [5:0] base_start_meta_q;
    reg [6:0] base_count_meta_q;
    reg [63:0] append_pattern_meta_q;
    reg [5:0] append_start_meta_q;
    reg [6:0] append_count_meta_q;
    reg phase_active_meta_q, append_phase_start_meta_q;
    reg first_sequence_meta_q, last_meta_q;
    reg [7:0] phase_after_meta_q, state_after_meta_q;
    reg [3:0] repeat_meta_q;
    reg [7:0] phase_meta_q;
    reg [6:0] pattern_index_meta_q;
    reg [7:0] descriptor_id_meta_q;

    reg next_append_plan_valid_q;
    reg [63:0] next_append_plan_data_q;
    reg [63:0] next_append_plan_mask_q;
    reg [6:0] next_append_plan_count_q;
    reg next_phase_active_q, next_phase_start_q;
    reg next_first_sequence_q, next_last_q;
    reg [7:0] next_phase_after_q, next_state_after_q;
    reg [3:0] next_repeat_q;
    reg [7:0] next_phase_q;
    reg [6:0] next_pattern_index_q;
    reg [7:0] next_descriptor_id_q;

    reg current_append_plan_valid_q;
    reg [63:0] current_append_plan_data_q;
    reg [63:0] current_append_plan_mask_q;
    reg [6:0] current_append_plan_count_q;
    reg current_phase_active_q, current_phase_start_q;
    reg current_first_sequence_q, current_last_q;
    reg [7:0] current_phase_after_q, current_state_after_q;
    reg [3:0] current_repeat_q;
    reg [7:0] current_phase_q;
    reg [6:0] current_pattern_index_q;
    reg [7:0] current_descriptor_id_q;
    reg [7:0] descriptor_id_state;
    reg output_running;
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

    function [63:0] low_mask;
        input [6:0] count;
        begin
            if (count == 0)
                low_mask = 64'd0;
            else if (count >= 64)
                low_mask = 64'hFFFF_FFFF_FFFF_FFFF;
            else
                low_mask = 64'hFFFF_FFFF_FFFF_FFFF >> (64-count);
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

    reg phase_active_calc, phase_start_calc, first_sequence_calc;
    reg running_next, segment_next, planner_word_last_calc;
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
    reg [7:0] descriptor_id_next;
    reg [63:0] base_pattern_calc, append_pattern_calc;
    reg [5:0] base_start_calc, append_start_calc;
    reg [6:0] base_count_calc, append_count_calc;
    integer lane, first_count, available, delay_count;
    integer second_count, active_pattern_len, append_start_int;

    wire [63:0] base_meta_mask =
        low_mask(base_count_meta_q) << base_start_meta_q;
    wire [63:0] append_meta_mask =
        low_mask(append_count_meta_q) << append_start_meta_q;
    wire [63:0] base_meta_data =
        (base_pattern_meta_q & low_mask(base_count_meta_q)) <<
        base_start_meta_q;
    wire [63:0] append_meta_data =
        (append_pattern_meta_q & low_mask(append_count_meta_q)) <<
        append_start_meta_q;
    wire [63:0] aligned_plan_data =
        base_meta_data | append_meta_data;
    wire [63:0] aligned_plan_mask =
        base_meta_mask | append_meta_mask;

    wire output_consume =
        output_running && current_append_plan_valid_q;
    wire current_plan_ready =
        !current_append_plan_valid_q || output_consume;
    wire next_plan_ready =
        !next_append_plan_valid_q || current_plan_ready;
    wire append_meta_ready =
        !append_meta_valid_q || next_plan_ready;
    wire planner_step = running && enable && append_meta_ready;

    // The scheduler below only emits compact word metadata. It never drives
    // txdata/valid_mask. All variable alignment is performed one registered
    // stage later, and the output edge consumes only a complete plan.
    always @* begin
        base_pattern_calc=0;
        base_start_calc=0;
        base_count_calc=0;
        append_pattern_calc=0;
        append_start_calc=0;
        append_count_calc=0;
        phase_active_calc=0;
        phase_start_calc=0;
        first_sequence_calc=0;
        planner_word_last_calc=0;
        running_next=running;
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
        descriptor_id_next=descriptor_id_state;
        first_count=0;
        available=0;
        delay_count=0;
        second_count=0;
        append_start_int=0;
        active_pattern_len=pattern_mode_63_active?63:127;

        if (running && enable && segment_state==SEG_PATTERN) begin
            first_count=pattern_remaining_state>=64?
                        64:pattern_remaining_state;
            base_pattern_calc=pattern_stream_state[63:0];
            base_count_calc=first_count[6:0];
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
                if (next_valid_state && first_count!=0 &&
                    next_delay_state<available) begin
                    append_start_int=first_count+next_delay_state;
                    second_count=available-next_delay_state;
                    append_pattern_calc=next_pattern_state[63:0];
                    append_start_calc=append_start_int[5:0];
                    append_count_calc=second_count[6:0];
                    if ((next_repeat_state==0)&&(second_count!=0))
                        phase_start_calc=1'b1;
                    repeat_next=next_repeat_state;
                    phase_next=next_phase_state;
                    descriptor_id_next=descriptor_id_state+1'b1;
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
                    end else if (after_valid_calc) begin
                        repeat_next=after_repeat_calc;
                        phase_next=after_phase_calc;
                        descriptor_id_next=descriptor_id_state+2'd2;
                        pattern_stream_next=after_pattern_calc;
                        pattern_remaining_next=active_pattern_len;
                        index_next=0;
                        next_descriptor_next=third_descriptor_calc;
                        after_descriptor_next=fourth_descriptor_calc;
                        third_descriptor_next=fifth_descriptor_calc;
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
                        planner_word_last_calc=1'b1;
                    end
                end else if (next_valid_state) begin
                    repeat_next=next_repeat_state;
                    phase_next=next_phase_state;
                    descriptor_id_next=descriptor_id_state+1'b1;
                    pattern_stream_next=next_pattern_state;
                    pattern_remaining_next=active_pattern_len;
                    index_next=0;
                    next_descriptor_next=after_descriptor_calc;
                    after_descriptor_next=third_descriptor_calc;
                    third_descriptor_next=fourth_descriptor_calc;
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
                    planner_word_last_calc=1'b1;
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
                base_pattern_calc=pattern_stream_state[63:0];
                base_start_calc=delay_count[5:0];
                base_count_calc=second_count[6:0];
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
                    descriptor_id_next=descriptor_id_state+1'b1;
                    pattern_stream_next=next_pattern_state;
                    pattern_remaining_next=active_pattern_len;
                    index_next=0;
                    next_descriptor_next=after_descriptor_calc;
                    after_descriptor_next=third_descriptor_calc;
                    third_descriptor_next=fourth_descriptor_calc;
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
                    planner_word_last_calc=1'b1;
                end
            end else begin
                running_next=1'b0;
                planner_word_last_calc=1'b1;
            end
        end

        first_sequence_calc =
            phase_start_calc &&
            (((phase_index_state==0)&&(repeat_index_state==0)) ||
             ((append_count_calc!=0)&&(next_phase_state==0) &&
              (next_repeat_state==0)));
    end

    always @(posedge clk) begin
        if (rst) begin
            txdata<=0; valid_mask<=0;
            phase_active<=0; phase_start_pulse<=0;
            sequence_active<=0; busy<=0; done<=0;
            phase_offset<=0; current_state<=ST_IDLE;
            engine_start_accept_pulse<=0;
            first_sequence_word_fire<=0;
            segment_state<=SEG_DELAY; running<=0; output_running<=0;
            pattern_mode_63_active<=1; phase_shift_active<=0;
            loop_active<=0; repeat_count_active<=1;
            head_delay_active<=0; gap_len_active<=0;
            phase_zero_pattern_state<=0; pattern_stream_state<=0;
            next_descriptor_state<=0; after_descriptor_state<=0;
            third_descriptor_state<=0; descriptor_id_state<=0;
            repeat_index_state<=0; phase_index_state<=0;
            pattern_index_state<=0; pattern_remaining_state<=63;
            delay_remaining_state<=0; delay_has_pattern_state<=0;
            delay_phase_active_state<=0; pattern_start_pending<=0;
            append_meta_valid_q<=0;
            base_pattern_meta_q<=0; base_start_meta_q<=0;
            base_count_meta_q<=0; append_pattern_meta_q<=0;
            append_start_meta_q<=0; append_count_meta_q<=0;
            phase_active_meta_q<=0; append_phase_start_meta_q<=0;
            first_sequence_meta_q<=0; last_meta_q<=0;
            phase_after_meta_q<=0; state_after_meta_q<=0;
            repeat_meta_q<=0; phase_meta_q<=0;
            pattern_index_meta_q<=0; descriptor_id_meta_q<=0;
            next_append_plan_valid_q<=0;
            next_append_plan_data_q<=0; next_append_plan_mask_q<=0;
            next_append_plan_count_q<=0;
            next_phase_active_q<=0; next_phase_start_q<=0;
            next_first_sequence_q<=0; next_last_q<=0;
            next_phase_after_q<=0; next_state_after_q<=0;
            next_repeat_q<=0; next_phase_q<=0;
            next_pattern_index_q<=0; next_descriptor_id_q<=0;
            current_append_plan_valid_q<=0;
            current_append_plan_data_q<=0;
            current_append_plan_mask_q<=0;
            current_append_plan_count_q<=0;
            current_phase_active_q<=0; current_phase_start_q<=0;
            current_first_sequence_q<=0; current_last_q<=0;
            current_phase_after_q<=0; current_state_after_q<=0;
            current_repeat_q<=0; current_phase_q<=0;
            current_pattern_index_q<=0; current_descriptor_id_q<=0;
            waiting_geometry<=0; waiting_eom<=0;
            eom_request_active<=0; eom_complete_seen<=0;
        end else begin
            engine_start_accept_pulse<=1'b0;
            first_sequence_word_fire<=1'b0;
            phase_start_pulse<=1'b0;
            if (eom_done_pulse)
                eom_complete_seen<=1'b1;

            if (start && !busy) begin
                txdata<=0; valid_mask<=0; phase_active<=0; done<=0;
                if (enable && pattern_valid &&
                    repeat_cycles>=1 &&
                    repeat_cycles<=MAX_REPEAT_CYCLES &&
                    (pattern_len==63 || pattern_len==127)) begin
                    engine_start_accept_pulse<=1'b1;
                    sequence_active<=1'b1; busy<=1'b1;
                    current_state<=ST_PRECOMPUTE;
                    waiting_geometry<=1'b1; waiting_eom<=1'b0;
                    running<=1'b1; output_running<=1'b0;
                    eom_request_active<=1'b0; eom_complete_seen<=1'b0;
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
                    descriptor_id_state<=0;
                    repeat_index_state<=0; phase_index_state<=0;
                    pattern_index_state<=0;
                    pattern_remaining_state<=pattern_len;
                    delay_remaining_state<={1'b0,head_delay_bits};
                    delay_has_pattern_state<=1'b1;
                    delay_phase_active_state<=1'b0;
                    pattern_start_pending<=head_delay_bits==0;
                    phase_offset<=0;
                    append_meta_valid_q<=0;
                    next_append_plan_valid_q<=0;
                    current_append_plan_valid_q<=0;
                end else begin
                    sequence_active<=0; busy<=0; running<=0;
                    output_running<=0; waiting_geometry<=0;
                    waiting_eom<=0; current_state<=ST_ERROR;
                end
            end else if (!enable) begin
                txdata<=0; valid_mask<=0; phase_active<=0;
                sequence_active<=0; busy<=0; running<=0;
                output_running<=0; waiting_geometry<=0; waiting_eom<=0;
                eom_request_active<=0; eom_complete_seen<=0;
                append_meta_valid_q<=0;
                next_append_plan_valid_q<=0;
                current_append_plan_valid_q<=0;
                current_state<=ST_IDLE;
            end else begin
                // N stage: consume only the fully registered word plan.
                if (current_plan_ready) begin
                    current_append_plan_valid_q<=next_append_plan_valid_q;
                    if (next_append_plan_valid_q) begin
                        current_append_plan_data_q<=
                            next_append_plan_data_q;
                        current_append_plan_mask_q<=
                            next_append_plan_mask_q;
                        current_append_plan_count_q<=
                            next_append_plan_count_q;
                        current_phase_active_q<=next_phase_active_q;
                        current_phase_start_q<=next_phase_start_q;
                        current_first_sequence_q<=
                            next_first_sequence_q;
                        current_last_q<=next_last_q;
                        current_phase_after_q<=next_phase_after_q;
                        current_state_after_q<=next_state_after_q;
                        current_repeat_q<=next_repeat_q;
                        current_phase_q<=next_phase_q;
                        current_pattern_index_q<=
                            next_pattern_index_q;
                        current_descriptor_id_q<=next_descriptor_id_q;
                    end
                end

                // N-1 stage: the only variable shifts use registered,
                // low-width start/count metadata.
                if (next_plan_ready) begin
                    next_append_plan_valid_q<=append_meta_valid_q;
                    if (append_meta_valid_q) begin
                        next_append_plan_data_q<=aligned_plan_data;
                        next_append_plan_mask_q<=aligned_plan_mask;
                        next_append_plan_count_q<=append_count_meta_q;
                        next_phase_active_q<=phase_active_meta_q;
                        next_phase_start_q<=append_phase_start_meta_q;
                        next_first_sequence_q<=first_sequence_meta_q;
                        next_last_q<=last_meta_q;
                        next_phase_after_q<=phase_after_meta_q;
                        next_state_after_q<=state_after_meta_q;
                        next_repeat_q<=repeat_meta_q;
                        next_phase_q<=phase_meta_q;
                        next_pattern_index_q<=pattern_index_meta_q;
                        next_descriptor_id_q<=descriptor_id_meta_q;
                    end
                end

                // N-2 stage: snapshot append/base metadata and identity.
                if (append_meta_ready) begin
                    append_meta_valid_q<=planner_step;
                    if (planner_step) begin
                        base_pattern_meta_q<=base_pattern_calc;
                        base_start_meta_q<=base_start_calc;
                        base_count_meta_q<=base_count_calc;
                        append_pattern_meta_q<=append_pattern_calc;
                        append_start_meta_q<=append_start_calc;
                        append_count_meta_q<=append_count_calc;
                        phase_active_meta_q<=phase_active_calc;
                        append_phase_start_meta_q<=phase_start_calc;
                        first_sequence_meta_q<=first_sequence_calc;
                        last_meta_q<=planner_word_last_calc;
                        phase_after_meta_q<=phase_next;
                        state_after_meta_q<=
                            planner_word_last_calc ? ST_DONE :
                            (segment_next==SEG_PATTERN ? ST_PATTERN :
                             (delay_phase_active_next?ST_GAP:ST_HEAD));
                        repeat_meta_q<=repeat_index_state;
                        phase_meta_q<=phase_index_state;
                        pattern_index_meta_q<=pattern_index_state;
                        descriptor_id_meta_q<=descriptor_id_state;
                    end
                end

                if (planner_step) begin
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
                    descriptor_id_state<=descriptor_id_next;
                    running<=running_next;
                end

                if (waiting_geometry) begin
                    txdata<=0; valid_mask<=0; phase_active<=0;
                    if (current_append_plan_valid_q)
                        current_state<=ST_ARM;
                    if (current_append_plan_valid_q &&
                        eom_geometry_armed && eom_tx_start_level) begin
                        waiting_geometry<=1'b0;
                        output_running<=1'b1;
                        eom_request_active<=eom_request_valid;
                        busy<=1'b1; sequence_active<=1'b1;
                        current_state<=ST_ARM;
                    end
                end else if (output_running) begin
                    if (current_append_plan_valid_q) begin
                        txdata<=current_append_plan_data_q;
                        valid_mask<=current_append_plan_mask_q;
                        phase_active<=current_phase_active_q;
                        phase_start_pulse<=current_phase_start_q;
                        first_sequence_word_fire<=
                            current_first_sequence_q &&
                            (|current_append_plan_mask_q);
                        phase_offset<=current_phase_after_q;
                        if (current_last_q) begin
                            output_running<=1'b0;
                            if (eom_request_active &&
                                !(eom_complete_seen || eom_done_pulse)) begin
                                waiting_eom<=1'b1;
                                busy<=1'b1; done<=1'b0;
                                sequence_active<=1'b1;
                                current_state<=ST_WAIT_EOM;
                            end else begin
                                waiting_eom<=1'b0;
                                busy<=1'b0; done<=1'b1;
                                sequence_active<=1'b0;
                                current_state<=ST_DONE;
                            end
                        end else begin
                            busy<=1'b1; done<=1'b0;
                            sequence_active<=1'b1;
                            current_state<=current_state_after_q;
                        end
                    end else begin
                        // The elastic pipeline is dimensioned for one word per
                        // cycle. Reaching this branch indicates an internal
                        // underflow; keep the external interface safely idle.
                        txdata<=0; valid_mask<=0; phase_active<=0;
                    end
                end else if (waiting_eom) begin
                    txdata<=0; valid_mask<=0; phase_active<=0;
                    if (eom_complete_seen || eom_done_pulse) begin
                        waiting_eom<=1'b0; busy<=1'b0; done<=1'b1;
                        sequence_active<=1'b0; current_state<=ST_DONE;
                    end
                end else begin
                    txdata<=0; valid_mask<=0; phase_active<=0;
                    sequence_active<=0; busy<=0;
                    current_state<=done?ST_DONE:ST_IDLE;
                end
            end
        end
    end
endmodule

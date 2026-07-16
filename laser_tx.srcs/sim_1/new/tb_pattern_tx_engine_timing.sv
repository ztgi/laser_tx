`timescale 1ns/1ps

module tb_pattern_tx_engine_timing;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start = 1'b0;
    logic enable = 1'b1;
    logic pattern_valid = 1'b1;
    logic [126:0] base_pattern;
    logic [7:0] pattern_len;
    logic [31:0] repeat_cycles;
    logic [15:0] insert_after;
    logic [7:0] gap_len_bits;
    logic phase_shift_en;
    logic loop_en;
    wire [63:0] txdata;
    wire [63:0] valid_mask;
    wire phase_active;
    wire phase_start_pulse;
    wire sequence_active;
    wire busy;
    wire done;
    wire [7:0] phase_offset;
    wire [7:0] current_state;

    realtime half_period = 3.103;
    integer errors = 0;

    always begin
        #(half_period) clk = ~clk;
    end

    pattern_tx_engine dut (
        .clk(clk), .rst(rst), .start(start), .enable(enable),
        .pattern_valid(pattern_valid), .base_pattern(base_pattern),
        .pattern_len(pattern_len), .repeat_cycles(repeat_cycles),
        .insert_after(insert_after), .gap_len_bits(gap_len_bits),
        .phase_shift_en(phase_shift_en), .loop_en(loop_en),
        .txdata(txdata), .valid_mask(valid_mask),
        .phase_active(phase_active), .phase_start_pulse(phase_start_pulse),
        .sequence_active(sequence_active), .busy(busy), .done(done),
        .phase_offset(phase_offset), .current_state(current_state)
    );

    task automatic fail(input string message);
        begin
            $display("ERROR @ %0t: %s", $time, message);
            errors = errors + 1;
        end
    endtask

    function automatic logic expected_pattern_bit(
        input integer phase,
        input integer data_pos
    );
        integer idx;
        begin
            idx = data_pos % pattern_len;
            if (phase_shift_en)
                idx = (idx + phase) % pattern_len;
            expected_pattern_bit = base_pattern[idx];
        end
    endfunction

    task automatic pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task automatic run_and_check(input string case_name);
        integer phase_bits;
        integer phase_total;
        integer phase_count;
        integer total_bits;
        integer global_pos;
        integer lane;
        integer absolute_pos;
        integer phase;
        integer local_pos;
        integer data_pos;
        integer word_count;
        integer timeout;
        logic exp_valid;
        logic exp_data;
        begin
            phase_bits = pattern_len * repeat_cycles;
            phase_total = phase_bits + gap_len_bits;
            phase_count = phase_shift_en ? pattern_len : 1;
            total_bits = phase_total * phase_count;
            global_pos = 0;
            word_count = 0;

            pulse_start();
            timeout = 0;
            while (!busy && timeout < 10) begin
                @(posedge clk); #0.1;
                timeout = timeout + 1;
            end
            if (timeout == 10)
                fail($sformatf("%s failed to enter busy", case_name));

            while (!done && word_count < ((total_bits + 63) / 64 + 4)) begin
                @(posedge clk); #0.1;
                if (phase_active) begin
                    for (lane = 0; lane < 64; lane = lane + 1) begin
                        absolute_pos = global_pos + lane;
                        if (absolute_pos < total_bits) begin
                            phase = absolute_pos / phase_total;
                            local_pos = absolute_pos % phase_total;
                            exp_valid = !((local_pos >= (insert_after * pattern_len)) &&
                                          (local_pos < ((insert_after * pattern_len) + gap_len_bits)));
                            if (local_pos < (insert_after * pattern_len))
                                data_pos = local_pos;
                            else if (local_pos >= ((insert_after * pattern_len) + gap_len_bits))
                                data_pos = local_pos - gap_len_bits;
                            else
                                data_pos = 0;
                            exp_data = exp_valid ? expected_pattern_bit(phase, data_pos) : 1'b0;
                        end else begin
                            exp_valid = 1'b0;
                            exp_data = 1'b0;
                        end
                        if (valid_mask[lane] !== exp_valid)
                            fail($sformatf("%s mask word=%0d lane=%0d", case_name, word_count, lane));
                        if (txdata[lane] !== exp_data)
                            fail($sformatf("%s data word=%0d lane=%0d", case_name, word_count, lane));
                    end
                    global_pos = global_pos + 64;
                    word_count = word_count + 1;
                end
            end
            if (!done)
                fail($sformatf("%s did not finish", case_name));
            if (global_pos < total_bits)
                fail($sformatf("%s ended early at %0d of %0d bits", case_name, global_pos, total_bits));
            $display("PASS %s words=%0d", case_name, word_count);
        end
    endtask

    initial begin
        base_pattern = 127'h5A69_36C5_17E2_4B89_2D73_4E1A_6B5C_7D3F;
        pattern_len = 8'd63;
        repeat_cycles = 32'd4;
        insert_after = 16'd2;
        gap_len_bits = 8'd5;
        phase_shift_en = 1'b1;
        loop_en = 1'b0;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        run_and_check("63-bit phase/gap/wrap");

        repeat (3) @(posedge clk);
        pattern_len = 8'd127;
        repeat_cycles = 32'd2;
        insert_after = 16'd1;
        gap_len_bits = 8'd11;
        phase_shift_en = 1'b0;
        run_and_check("127-bit direct/gap/wrap");

        // Disable is the existing quiesce semantic: it aborts the active
        // sequence and returns the engine to IDLE rather than pausing state.
        pattern_len = 8'd63;
        repeat_cycles = 32'd8;
        insert_after = 16'd3;
        gap_len_bits = 8'd7;
        phase_shift_en = 1'b1;
        pulse_start();
        repeat (4) @(posedge clk);
        enable = 1'b0;
        repeat (2) @(posedge clk); #0.1;
        if (busy || phase_active || valid_mask != 64'b0 || current_state != 8'd0)
            fail("disable/quiesce did not return engine to IDLE");
        enable = 1'b1;
        run_and_check("restart after disable/quiesce");

        // Reset while active must clear all externally visible activity.
        pulse_start();
        repeat (3) @(posedge clk);
        rst = 1'b1;
        repeat (2) @(posedge clk); #0.1;
        if (busy || done || phase_active || valid_mask != 64'b0)
            fail("reset did not clear engine outputs");
        rst = 1'b0;

        // A runtime user-clock change must not alter word sequence semantics.
        half_period = 1.5515;
        pattern_len = 8'd127;
        repeat_cycles = 32'd1;
        insert_after = 16'd1;
        gap_len_bits = 8'd0;
        phase_shift_en = 1'b0;
        run_and_check("runtime clock period change");

        if (errors == 0)
            $display("PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS");
        else
            $display("PATTERN_TX_ENGINE_TIMING_REGRESSION_FAIL errors=%0d", errors);
        $finish;
    end
endmodule

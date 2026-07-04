`timescale 1ns/1ps

module tb_laser_tx_core;
    logic axi_clk = 1'b0;
    logic txusrclk2 = 1'b0;
    logic axi_rstn = 1'b0;
    logic tx_rst = 1'b1;
    logic gt_ready = 1'b0;
    logic [31:0] gpio_ctrl = 32'b0;
    wire [31:0] gpio_status;
    wire bram_clk;
    wire bram_rst;
    wire bram_en;
    wire [3:0] bram_we;
    wire [31:0] bram_addr;
    wire [31:0] bram_din;
    logic [31:0] bram_dout = 32'b0;
    wire [63:0] txdata;
    wire [63:0] valid_mask;
    wire eom_out, soa_gate_out, acq_trig_out, acq_gate_out;
    wire dbg_bram_en, dbg_bram_rst;
    wire [31:0] dbg_bram_addr, dbg_bram_dout;
    wire dbg_busy_tx, dbg_done_tx, dbg_phase_active_tx;
    wire dbg_phase_start_pulse_tx, dbg_cfg_update_pulse_tx;
    wire dbg_pattern_valid_tx, dbg_engine_start_tx, dbg_gt_ready_tx;
    wire [7:0] dbg_phase_offset_tx, dbg_current_state_tx;

    logic [31:0] bram_mem [0:2047];
    integer errors = 0;
    integer i;

    always #5 axi_clk = ~axi_clk;
    always #3 txusrclk2 = ~txusrclk2;

    always @(posedge bram_clk)
        if (bram_rst)
            bram_dout <= 32'b0;
        else if (bram_en)
            bram_dout <= bram_mem[bram_addr[12:2]];

    laser_tx_core dut (
        .axi_clk(axi_clk), .axi_rstn(axi_rstn),
        .txusrclk2(txusrclk2), .tx_rst(tx_rst),
        .gt_ready(gt_ready),
        .gpio_ctrl(gpio_ctrl), .gpio_status(gpio_status),
        .bram_clk(bram_clk), .bram_rst(bram_rst),
        .bram_en(bram_en), .bram_we(bram_we),
        .bram_addr(bram_addr), .bram_din(bram_din), .bram_dout(bram_dout),
        .txdata(txdata), .valid_mask(valid_mask),
        .eom_out(eom_out), .soa_gate_out(soa_gate_out),
        .acq_trig_out(acq_trig_out), .acq_gate_out(acq_gate_out),
        .dbg_bram_en(dbg_bram_en), .dbg_bram_addr(dbg_bram_addr),
        .dbg_bram_dout(dbg_bram_dout), .dbg_bram_rst(dbg_bram_rst),
        .dbg_busy_tx(dbg_busy_tx), .dbg_done_tx(dbg_done_tx),
        .dbg_phase_active_tx(dbg_phase_active_tx),
        .dbg_phase_start_pulse_tx(dbg_phase_start_pulse_tx),
        .dbg_phase_offset_tx(dbg_phase_offset_tx),
        .dbg_current_state_tx(dbg_current_state_tx),
        .dbg_cfg_update_pulse_tx(dbg_cfg_update_pulse_tx),
        .dbg_pattern_valid_tx(dbg_pattern_valid_tx),
        .dbg_engine_start_tx(dbg_engine_start_tx),
        .dbg_gt_ready_tx(dbg_gt_ready_tx)
    );

    task automatic fail(input string message);
        begin
            $display("ERROR @ %0t: %s", $time, message);
            errors = errors + 1;
        end
    endtask

    task automatic set_enable(input logic enable_value);
        begin
            @(negedge axi_clk);
            gpio_ctrl[9] = enable_value;
            repeat (4) @(posedge txusrclk2);
            #1;
        end
    endtask

    task automatic check_loaded_config_legal(input string scenario_name);
        begin
            if (dut.repeat_cycles_tx == 32'd0)
                fail($sformatf("%s illegal repeat_cycles=0", scenario_name));
            if (dut.insert_after_tx > dut.repeat_cycles_tx[15:0])
                fail($sformatf("%s illegal insert_after > repeat_cycles", scenario_name));
            if (dut.pattern_len_tx != 8'd63 && dut.pattern_len_tx != 8'd127)
                fail($sformatf("%s unexpected pattern_len_tx=%0d", scenario_name, dut.pattern_len_tx));
            if (dut.gap_len_bits_tx > 8'd127)
                fail($sformatf("%s unexpected gap_len_bits=%0d", scenario_name, dut.gap_len_bits_tx));
        end
    endtask

    task automatic monitor_start_window(input string scenario_name);
        integer timeout;
        integer cycle_idx;
        bit left_idle;
        bit busy_seen;
        bit done_seen;
        bit valid_mask_seen;
        begin
            timeout = 0;
            while (!dbg_engine_start_tx && timeout < 100) begin
                @(posedge txusrclk2);
                #1;
                timeout = timeout + 1;
            end

            if (timeout == 100) begin
                fail($sformatf("%s engine_start_tx timeout", scenario_name));
            end else begin
                if (!gt_ready || !dbg_gt_ready_tx)
                    fail($sformatf("%s gt_ready not stable when engine_start_tx asserted", scenario_name));
                if (tx_rst)
                    fail($sformatf("%s tx_rst still asserted when engine_start_tx asserted", scenario_name));
                if (!dut.cfg_valid_tx)
                    fail($sformatf("%s cfg_valid_tx is not 1 when engine_start_tx asserted", scenario_name));
                if (dut.cfg_error_axi)
                    fail($sformatf("%s cfg_error is 1 when engine_start_tx asserted", scenario_name));
                if (!dbg_pattern_valid_tx)
                    fail($sformatf("%s pattern_valid_tx is not 1 when engine_start_tx asserted", scenario_name));
                check_loaded_config_legal(scenario_name);

                left_idle = (dbg_current_state_tx != 8'd0);
                busy_seen = dbg_busy_tx;
                done_seen = dbg_done_tx;
                valid_mask_seen = (valid_mask != 64'd0);

                for (cycle_idx = 0; cycle_idx < 10; cycle_idx = cycle_idx + 1) begin
                    @(posedge txusrclk2);
                    #1;
                    if (dbg_current_state_tx != 8'd0)
                        left_idle = 1'b1;
                    if (dbg_busy_tx)
                        busy_seen = 1'b1;
                    if (dbg_done_tx)
                        done_seen = 1'b1;
                    if (valid_mask != 64'd0)
                        valid_mask_seen = 1'b1;
                end

                $display("%s startup window: gt_ready=%0b dbg_gt_ready_tx=%0b tx_rst=%0b cfg_valid_tx=%0b cfg_error=%0b pattern_valid_tx=%0b state_left_idle=%0b busy_seen=%0b done_seen=%0b valid_mask_seen=%0b repeat_cycles=%0d insert_after=%0d gap_len_bits=%0d loop_en=%0b direct_len_sel=%0b",
                         scenario_name, gt_ready, dbg_gt_ready_tx, tx_rst, dut.cfg_valid_tx,
                         dut.cfg_error_axi, dbg_pattern_valid_tx, left_idle, busy_seen, done_seen,
                         valid_mask_seen, dut.repeat_cycles_tx, dut.insert_after_tx, dut.gap_len_bits_tx,
                         dut.loop_en_tx, gpio_ctrl[12]);

                if (!left_idle)
                    fail($sformatf("%s current_state_tx stayed IDLE after engine_start_tx", scenario_name));
                if (!busy_seen)
                    fail($sformatf("%s busy_tx never asserted after engine_start_tx", scenario_name));
                if (!valid_mask_seen)
                    fail($sformatf("%s valid_mask stayed zero after engine_start_tx", scenario_name));
            end
        end
    endtask

    task automatic apply_config(
        input [7:0] index,
        input logic source_sel,
        input logic len_sel
    );
        logic old_update_toggle;
        integer timeout;
        begin
            old_update_toggle = dut.cfg_update_toggle_axi;
            @(negedge axi_clk);
            gpio_ctrl[7:0] = index;
            gpio_ctrl[11] = source_sel;
            gpio_ctrl[12] = len_sel;
            gpio_ctrl[8] = ~gpio_ctrl[8];
            timeout = 0;
            while ((dut.cfg_update_toggle_axi == old_update_toggle) && timeout < 100) begin
                @(posedge axi_clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 100)
                fail("apply update-toggle timeout");
        end
    endtask

    task automatic wait_cfg_result(input logic expect_valid);
        integer timeout;
        begin
            timeout = 0;
            while (((expect_valid && !gpio_status[0]) ||
                    (!expect_valid && !gpio_status[1])) && timeout < 100) begin
                @(posedge axi_clk);
                timeout = timeout + 1;
            end
            if (timeout == 100)
                fail("configuration loader timeout");
        end
    endtask

    task automatic check_scenario1;
        integer word_count;
        integer lane;
        integer global_bit;
        integer pos_phase;
        integer phase;
        integer data_pos;
        integer bit_idx;
        integer expected_trig;
        integer timeout;
        logic exp_valid;
        logic exp_data;
        begin
            $display("Scenario 1: PRBS6, 63 phases, repeat/gap checking");
            set_enable(1'b0);
            apply_config(8'd0, 1'b0, 1'b0);
            wait_cfg_result(1'b1);
            if (!gpio_status[0] || gpio_status[1]) fail("scenario 1 cfg flags");
            fork
                monitor_start_window("scenario 1");
            join_none
            set_enable(1'b1);

            timeout = 0;
            while (!dut.busy_tx && timeout < 100) begin
                @(posedge txusrclk2); #1;
                timeout = timeout + 1;
            end
            if (timeout == 100) fail("scenario 1 did not start");

            word_count = 0;
            global_bit = 0;
            while (!dut.done_tx && word_count < 300) begin
                @(posedge txusrclk2); #1;
                if (dut.phase_active_tx) begin
                    expected_trig = 0;
                    for (lane = 0; lane < 64; lane = lane + 1) begin
                        if (global_bit + lane < 16191) begin
                            phase = (global_bit + lane) / 257;
                            pos_phase = (global_bit + lane) % 257;
                            if (pos_phase == 0)
                                expected_trig = 1;
                            exp_valid = !((pos_phase >= 126) && (pos_phase < 131));
                            if (pos_phase < 126)
                                data_pos = pos_phase;
                            else if (pos_phase >= 131)
                                data_pos = pos_phase - 5;
                            else
                                data_pos = 0;
                            bit_idx = data_pos % 63;
                            exp_data = exp_valid ? dut.base_pattern[(phase + bit_idx) % 63] : 1'b0;
                        end else begin
                            exp_valid = 1'b0;
                            exp_data = 1'b0;
                        end
                        if (valid_mask[lane] !== exp_valid)
                            fail($sformatf("scenario 1 mask word=%0d lane=%0d", word_count, lane));
                        if (txdata[lane] !== exp_data)
                            fail($sformatf("scenario 1 data word=%0d lane=%0d", word_count, lane));
                    end
                    if (eom_out !== (|valid_mask)) fail("scenario 1 EOM alignment");
                    if (!soa_gate_out || !acq_gate_out) fail("scenario 1 phase gates low");
                    if (acq_trig_out !== expected_trig) fail("scenario 1 phase trigger");
                    global_bit = global_bit + 64;
                    word_count = word_count + 1;
                end
            end
            if (!dut.done_tx) fail("scenario 1 done timeout");
            if (word_count != 253) fail($sformatf("scenario 1 word count %0d", word_count));
            if (dut.phase_offset_tx != 8'd62) fail("scenario 1 final phase offset");
        end
    endtask

    task automatic check_scenario2;
        integer word_count;
        integer lane;
        integer global_bit;
        integer pos_phase;
        integer phase;
        integer data_pos;
        integer bit_idx;
        integer timeout;
        logic exp_valid;
        logic exp_data;
        logic [126:0] direct;
        begin
            $display("Scenario 2: direct 127-bit pattern");
            direct = {31'h52a55aa5, 32'h89abcdef, 32'h01234567, 32'hdeadbeef};
            set_enable(1'b0);
            apply_config(8'd1, 1'b1, 1'b1);
            wait_cfg_result(1'b1);
            fork
                monitor_start_window("scenario 2");
            join_none
            set_enable(1'b1);

            timeout = 0;
            while (!dut.busy_tx && timeout < 100) begin
                @(posedge txusrclk2); #1;
                timeout = timeout + 1;
            end
            if (timeout == 100) fail("scenario 2 did not start");
            if (dut.pattern_len_tx != 8'd127) fail("scenario 2 length is not 127");
            if (dut.base_pattern !== direct) fail("scenario 2 direct pattern assembly");

            word_count = 0;
            global_bit = 0;
            while (!dut.done_tx && word_count < 550) begin
                @(posedge txusrclk2); #1;
                if (dut.phase_active_tx) begin
                    for (lane = 0; lane < 64; lane = lane + 1) begin
                        if (global_bit + lane < 33274) begin
                            phase = (global_bit + lane) / 262;
                            pos_phase = (global_bit + lane) % 262;
                            exp_valid = !((pos_phase >= 127) && (pos_phase < 135));
                            if (pos_phase < 127)
                                data_pos = pos_phase;
                            else if (pos_phase >= 135)
                                data_pos = pos_phase - 8;
                            else
                                data_pos = 0;
                            bit_idx = data_pos % 127;
                            exp_data = exp_valid ? direct[(phase + bit_idx) % 127] : 1'b0;
                        end else begin
                            exp_valid = 1'b0;
                            exp_data = 1'b0;
                        end
                        if (valid_mask[lane] !== exp_valid)
                            fail($sformatf("scenario 2 mask word=%0d lane=%0d", word_count, lane));
                        if (txdata[lane] !== exp_data)
                            fail($sformatf("scenario 2 data word=%0d lane=%0d", word_count, lane));
                    end
                    if (dut.phase_offset_tx > 8'd126) fail("scenario 2 phase exceeded 126");
                    if (eom_out !== (|valid_mask)) fail("scenario 2 EOM alignment");
                    global_bit = global_bit + 64;
                    word_count = word_count + 1;
                end
            end
            if (!dut.done_tx) fail("scenario 2 done timeout");
            if (word_count != 520) fail($sformatf("scenario 2 word count %0d", word_count));
            if (dut.phase_offset_tx != 8'd126) fail("scenario 2 final phase offset");
        end
    endtask

    task automatic check_scenario3;
        integer cycles;
        begin
            $display("Scenario 3: invalid repeat_cycles=0");
            set_enable(1'b0);
            apply_config(8'd2, 1'b0, 1'b0);
            wait_cfg_result(1'b0);
            if (!gpio_status[1] || gpio_status[0]) fail("scenario 3 cfg flags");
            if (gpio_status[31:24] != 8'h01) fail("scenario 3 error code");
            set_enable(1'b1);
            for (cycles = 0; cycles < 30; cycles = cycles + 1) begin
                @(posedge txusrclk2); #1;
                if (dut.busy_tx) fail("scenario 3 engine started");
            end
            set_enable(1'b0);
        end
    endtask

    initial begin
        for (i = 0; i < 2048; i = i + 1)
            bram_mem[i] = 32'b0;

        // Record 0: PRBS6, repeat=4, gap after two patterns.
        bram_mem[0] = 32'h0000003f;
        bram_mem[1] = 32'd4;
        bram_mem[2] = {8'b0, 16'd2, 8'd5};
        bram_mem[3] = {22'b0, 1'b0, 1'b1, 8'd6};

        // Record 1: direct 127-bit, repeat=2, 8-bit gap after one pattern.
        bram_mem[8]  = 32'h0000007f;
        bram_mem[9]  = 32'd2;
        bram_mem[10] = {8'b0, 16'd1, 8'd8};
        bram_mem[11] = {22'b0, 1'b0, 1'b1, 8'd7};
        bram_mem[12] = 32'hdeadbeef;
        bram_mem[13] = 32'h01234567;
        bram_mem[14] = 32'h89abcdef;
        bram_mem[15] = 32'h52a55aa5;

        // Record 2: illegal repeat count.
        bram_mem[16] = 32'h0000003f;
        bram_mem[17] = 32'd0;
        bram_mem[18] = {8'b0, 16'd0, 8'd0};
        bram_mem[19] = {22'b0, 1'b0, 1'b1, 8'd6};

        gpio_ctrl[9] = 1'b0;
        repeat (5) @(posedge axi_clk);
        axi_rstn = 1'b1;
        repeat (3) @(posedge txusrclk2);
        gt_ready = 1'b1;
        repeat (4) @(posedge txusrclk2);
        tx_rst = 1'b0;
        repeat (4) @(posedge txusrclk2);

        // Native Port B is read-only and tied to the AXI clock/reset domain.
        #1;
        if (bram_clk !== axi_clk) fail("bram_clk is not tied to axi_clk");
        if (bram_rst !== ~axi_rstn) fail("bram_rst polarity/tie-off error");
        if (bram_we !== 4'b0000) fail("BRAM Port B is not read-only");
        if (bram_din !== 32'd0) fail("read-only BRAM DIN is not zero");
        if (dbg_bram_en !== bram_en || dbg_bram_addr !== bram_addr ||
            dbg_bram_dout !== bram_dout || dbg_bram_rst !== bram_rst)
            fail("BRAM debug mirror mismatch");

        check_scenario1();
        check_scenario2();
        check_scenario3();

        if (errors == 0)
            $display("PASS: all laser_tx_core scenarios passed");
        else
            $display("FAIL: %0d checks failed", errors);
        $finish;
    end
endmodule

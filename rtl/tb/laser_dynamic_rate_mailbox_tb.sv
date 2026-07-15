`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"

module laser_dynamic_rate_mailbox_tb;
    reg clk = 0;
    reg rst = 1;
    reg [3:0] control = 0;
    wire [31:0] status;
    wire bram_en;
    wire [7:0] bram_addr;
    wire [3:0] bram_we;
    wire [31:0] bram_wdata;
    reg [31:0] bram_rdata;
    wire desc_valid;
    wire [2047:0] active;
    wire refclk_event, abort_event, rollback_event;
    reg exec_prepared=0, exec_done=0, exec_error=0, exec_rollback=0, exec_verify=0;
    reg [31:0] mem [0:255];
    integer i;

    always #5 clk = ~clk;
    always @(posedge clk)
        if (bram_en) begin
            if (|bram_we)
                mem[bram_addr] <= bram_wdata;
            else
                bram_rdata <= mem[bram_addr];
        end

    laser_dynamic_rate_mailbox dut (
        .clk(clk), .rst(rst), .control_toggles(control),
        .status_gpio(status), .bram_en(bram_en),
        .bram_word_addr(bram_addr), .bram_we(bram_we),
        .bram_wdata(bram_wdata), .bram_rdata(bram_rdata),
        .active_descriptor_valid(desc_valid), .active_words_flat(active),
        .descriptor_commit_event(), .executor_prepared_ack(exec_prepared),
        .executor_switch_done(exec_done), .executor_switch_error(exec_error),
        .executor_rollback_done(exec_rollback), .executor_verify_pass(exec_verify),
        .executor_failed_stage(8'd0),
        .refclk_ready_event(refclk_event), .abort_event(abort_event),
        .rollback_ready_event(rollback_event)
    );

    function automatic [31:0] crc_byte(input [31:0] ci, input [7:0] d);
        reg [31:0] c;
        integer b;
        begin
            c = ci ^ d;
            for (b = 0; b < 8; b = b + 1)
                c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
            crc_byte = c;
        end
    endfunction

    function automatic [31:0] crc_word(input [31:0] ci, input [31:0] d);
        reg [31:0] c;
        begin
            c = crc_byte(ci, d[7:0]);
            c = crc_byte(c, d[15:8]);
            c = crc_byte(c, d[23:16]);
            crc_word = crc_byte(c, d[31:24]);
        end
    endfunction

    task automatic build_valid(input [31:0] transaction_seq);
        reg [31:0] c;
        begin
            for (i = 0; i < 256; i = i + 1) mem[i] = 0;
            mem[0] = 32'h31505452;
            mem[1] = {16'd64, 16'd1};
            mem[2] = transaction_seq;
            mem[5] = 32'hB2D05E00;
            mem[6] = 32'd0;
            mem[7] = 32'hB2D05E00;
            mem[8] = 32'd0;
            mem[10] = 32'h00010404;
            mem[11] = 32'h00000002;
            mem[12] = 32'd46875;
            mem[13] = 32'd500;
            mem[14] = 32'd2;
            mem[32] = 32'h00001234;
            mem[33] = 32'h00005678;
            mem[34] = 32'h00009ABC;
            mem[35] = 32'h0000DEF0;
            c = 32'hFFFFFFFF;
            for (i = 0; i < 64; i = i + 1)
                if (i != 3) c = crc_word(c, mem[i]);
            mem[3] = c ^ 32'hFFFFFFFF;
        end
    endtask

    task automatic pulse_prepare;
        begin
            control[0] = ~control[0];
            @(posedge clk);
        end
    endtask

    task automatic wait_complete;
        integer timeout;
        begin
            timeout = 0;
            while (!status[5] && !status[3] && timeout < 200) begin
                @(posedge clk); timeout = timeout + 1;
            end
            if (timeout == 200) $fatal(1, "mailbox timeout");
        end
    endtask

    task automatic reset_dut;
        begin
            rst = 1; repeat (3) @(posedge clk); rst = 0; @(posedge clk);
        end
    endtask

    task automatic expect_reject(input [7:0] expected_stage);
        begin
            pulse_prepare(); wait_complete();
            if (!status[3] || status[15:8] != expected_stage || status[5])
                $fatal(1, "expected reject stage=%0d status=%08x", expected_stage, status);
        end
    endtask

    initial begin
        bram_rdata = 0;
        build_valid(32'h12345678);
        reset_dut();

        // REFCLK_READY before PREPARE must be consumed and flagged.
        control[1] = ~control[1]; @(posedge clk); @(posedge clk);
        if (!status[7]) $fatal(1, "early REFCLK_READY was not rejected");
        reset_dut();

        // A legal descriptor is latched. Later shadow changes must not alter it.
        pulse_prepare(); wait_complete();
        exec_prepared=1; @(posedge clk); exec_prepared=0; @(posedge clk);
        if (!status[1] || !status[5] || active[2*32 +: 32] != 32'h12345678)
            $fatal(1, "valid descriptor failed status=%08x seq=%08x", status, active[2*32 +: 32]);
        repeat (6) @(posedge clk);
        if (mem[8'h60] != 32'h12345678)
            $fatal(1, "PL status sequence was not written to BRAM");
        mem[2] = 32'hDEADBEEF;
        repeat (4) @(posedge clk);
        if (active[2*32 +: 32] != 32'h12345678)
            $fatal(1, "active descriptor followed shadow writes");
        // Duplicate/busy PREPARE is consumed and cannot replay after abort.
        control[0] = ~control[0]; @(posedge clk);
        @(negedge clk); control[2] = ~control[2]; @(posedge clk); #1;
        if (!abort_event || !status[0]) $fatal(1, "abort was not forwarded while ownership held");
        @(posedge clk);
        exec_rollback=1; @(posedge clk); exec_rollback=0; @(posedge clk);
        if (!status[4] || status[0]) $fatal(1, "executor rollback did not release transaction");
        repeat (5) @(posedge clk);
        if (status[0]) $fatal(1, "busy PREPARE replayed");

        build_valid(1); mem[0] = 0; reset_dut(); expect_reject(1);
        build_valid(1); mem[1][15:0] = 2; reset_dut(); expect_reject(2);
        build_valid(1); mem[1][31:16] = 63; reset_dut(); expect_reject(3);
        build_valid(1); mem[3] = mem[3] ^ 1; reset_dut(); expect_reject(4);
        build_valid(1); mem[14] = 17; begin : recalc_crc
            reg [31:0] c;
            c = 32'hFFFFFFFF;
            for (i = 0; i < 64; i = i + 1)
                if (i != 3) c = crc_word(c, mem[i]);
            mem[3] = c ^ 32'hFFFFFFFF;
        end
        reset_dut(); expect_reject(5);

        $display("PASS: dynamic mailbox descriptor validation and locking");
        $finish;
    end
endmodule

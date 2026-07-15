`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"
module laser_gt_dynamic_rate_executor_tb;
    reg clk=0,rst=1,start=0,refclk=0,abort=0,rollback=0;
    reg [2047:0] words=0;
    reg [31:0] freq=100;
    wire request,grant,resource_release_w,gt_en,gt_we,mm_en,mm_we;
    wire [8:0] gt_addr; wire [15:0] gt_di;
    wire [6:0] mm_addr; wire [15:0] mm_di;
    reg [15:0] gt_cpll_reg=16'h1002, gt_out_reg=16'h0030;
    reg [15:0] mmcm_reg=16'hAAAA;
    wire prepared,done,error,rb_done,verify;
    wire [7:0] failed,state;
    assign grant=request;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if (gt_en && gt_we) begin
            if (gt_addr==9'h05e) gt_cpll_reg <= gt_di;
            if (gt_addr==9'h088) gt_out_reg <= gt_di;
        end
        if (mm_en && mm_we) mmcm_reg <= mm_di;
    end
    initial begin #20000; $fatal(1,"timeout state=%0d error=%0d freq=%0d",state,failed,freq); end
    laser_gt_dynamic_rate_executor #(.RESET_HOLD_CYCLES(2),.TIMEOUT_CYCLES(20)) dut(
        .clk(clk),.rst(rst),.start(start),.descriptor_valid(1'b1),.active_words_flat(words),
        .refclk_ready_event(refclk),.abort_event(abort),.rollback_ready_event(rollback),
        .resource_request(request),.resource_grant(grant),.resource_reject(1'b0),
        .resource_owned(1'b1),.resource_release(resource_release_w),
        .tx_idle(1'b1),.cplllock_sync(1'b1),.qplllock_sync(1'b1),
        .qpllrefclklost_sync(1'b0),.tx_mmcm_locked_sync(1'b1),
        .txresetdone_sync(1'b1),.gt_ready_ctrl(1'b1),.txusrclk2_alive_axi(1'b1),
        .txusrclk2_freq_counter_axi(freq),.current_qpll_selected(1'b0),
        .current_refclk_north_selected(1'b0),.laser_enable_request(1'b1),
        .gt_reset(),.txuserrdy_block(),.mmcm_reset(),.cpll_reset(),.qpll_reset(),
        .qpll_selected(),.refclk_north_selected(),.apply_blocked(),.gt_drp_addr(gt_addr),.gt_drp_di(gt_di),
        .gt_drp_do((gt_addr == 9'h05e) ? gt_cpll_reg : gt_out_reg),.gt_drp_en(gt_en),
        .gt_drp_we(gt_we),.gt_drp_rdy(gt_en),.mmcm_drp_addr(mm_addr),
        .mmcm_drp_di(mm_di),.mmcm_drp_do(mmcm_reg),.mmcm_drp_en(mm_en),
        .mmcm_drp_we(mm_we),.mmcm_drp_rdy(mm_en),.prepared_ack(prepared),
        .switch_done(done),.switch_error(error),.rollback_done(rb_done),
        .verify_pass(verify),.failed_stage(failed),.dynamic_state(state));

    task build_desc(input [31:0] expected);
        begin
            words=0;
            // [1:0]=CPLL, [17:2]=confirmed 0x05E DRP field image.
            words[`LASER_DYN_WORD_GT_PLL*32 +:32]=(32'h1002 << 2);
            words[`LASER_DYN_WORD_GT_TXOUT*32 +:32]=32'h2;
            words[`LASER_DYN_WORD_VERIFY_EXPECTED*32 +:32]=expected;
            words[`LASER_DYN_WORD_VERIFY_TOLERANCE*32 +:32]=5;
            words[`LASER_DYN_WORD_MMCM_COUNT*32 +:32]=1;
            words[`LASER_DYN_WORD_MMCM_BASE*32 +:32]=7'h08;
            words[(`LASER_DYN_WORD_MMCM_BASE+1)*32 +:32]=16'h1234;
        end
    endtask
    task launch;
        begin start=1;@(posedge clk);start=0;while(!prepared)@(posedge clk);
            @(negedge clk);refclk=1;@(posedge clk);@(negedge clk);refclk=0;
        end
    endtask
    initial begin
        build_desc(200);repeat(3)@(posedge clk);rst=0;@(posedge clk);
        launch();freq=200;
        while(!done && !error)@(posedge clk);
        if(!done||error||!verify) $fatal(1,"success path failed state=%0d error=%0d",state,failed);
        repeat(3)@(posedge clk);

        rst=1;freq=100;gt_cpll_reg=16'h1002;gt_out_reg=16'h0030;mmcm_reg=16'hAAAA;
        repeat(3)@(posedge clk);rst=0;@(posedge clk);
        launch();freq=150;
        while(!error)@(posedge clk);
        if(failed!=8'd10) $fatal(1,"verify failure not reported");
        freq=100;@(negedge clk);rollback=1;@(posedge clk);@(negedge clk);rollback=0;
        while(!rb_done)@(posedge clk);
        if(error) $fatal(1,"rollback did not clear error");
        $display("PASS: dynamic executor success and previous-state rollback");$finish;
    end
endmodule

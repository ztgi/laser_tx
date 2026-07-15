`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"

module laser_gt_dynamic_rate_fault_tb;
    reg clk=0,rst=1,start=0,refclk=0,abort=0,rollback=0;
    reg [2047:0] words=0;
    reg tx_idle=1,cpll_lock=1,qpll_lock=1,mmcm_lock=1;
    reg txresetdone=1,gt_ready=1,alive=1,gt_rdy_enable=1,mm_rdy_enable=1;
    reg [31:0] freq=100;
    wire request,grant,gt_en,gt_we,mm_en,mm_we;
    wire [8:0] gt_addr; wire [15:0] gt_di;
    wire [6:0] mm_addr; wire [15:0] mm_di;
    reg [15:0] gt_cpll_reg=16'h1002,gt_out_reg=16'h0030,mmcm_reg=16'haaaa;
    wire prepared,done,error,rb_done,verify,gt_reset,user_block,mm_reset,qpll_sel,north_sel;
    wire [7:0] failed,state;
    assign grant=request;
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(gt_en&&gt_we) begin
            if(gt_addr==9'h05e) gt_cpll_reg<=gt_di;
            if(gt_addr==9'h088) gt_out_reg<=gt_di;
        end
        if(mm_en&&mm_we) mmcm_reg<=mm_di;
    end

    laser_gt_dynamic_rate_executor #(.RESET_HOLD_CYCLES(2),.TIMEOUT_CYCLES(12)) dut(
        .clk(clk),.rst(rst),.start(start),.descriptor_valid(1'b1),.active_words_flat(words),
        .refclk_ready_event(refclk),.abort_event(abort),.rollback_ready_event(rollback),
        .resource_request(request),.resource_grant(grant),.resource_reject(1'b0),
        .resource_owned(grant),.resource_release(),.tx_idle(tx_idle),
        .cplllock_sync(cpll_lock),.qplllock_sync(qpll_lock),.qpllrefclklost_sync(1'b0),
        .tx_mmcm_locked_sync(mmcm_lock),.txresetdone_sync(txresetdone),.gt_ready_ctrl(gt_ready),
        .txusrclk2_alive_axi(alive),.txusrclk2_freq_counter_axi(freq),
        .current_qpll_selected(1'b0),.current_refclk_north_selected(1'b0),
        .laser_enable_request(1'b1),.gt_reset(gt_reset),.txuserrdy_block(user_block),
        .mmcm_reset(mm_reset),.cpll_reset(),.qpll_reset(),.qpll_selected(qpll_sel),
        .refclk_north_selected(north_sel),.apply_blocked(),.gt_drp_addr(gt_addr),
        .gt_drp_di(gt_di),.gt_drp_do((gt_addr == 9'h05e) ? gt_cpll_reg : gt_out_reg),
        .gt_drp_en(gt_en),.gt_drp_we(gt_we),.gt_drp_rdy(gt_en&&gt_rdy_enable),
        .mmcm_drp_addr(mm_addr),.mmcm_drp_di(mm_di),.mmcm_drp_do(mmcm_reg),
        .mmcm_drp_en(mm_en),.mmcm_drp_we(mm_we),.mmcm_drp_rdy(mm_en&&mm_rdy_enable),
        .prepared_ack(prepared),.switch_done(done),.switch_error(error),
        .rollback_done(rb_done),.verify_pass(verify),.failed_stage(failed),.dynamic_state(state));

    task build_desc(input [1:0] pll,input [31:0] expected);
        begin
            words=0;
            words[`LASER_DYN_WORD_SEQUENCE*32 +:32]=32'h55aa0001;
            words[`LASER_DYN_WORD_FLAGS*32 +:32]=(pll==1)?1:0;
            words[`LASER_DYN_WORD_GT_PLL*32 +:32]=(32'h1002<<2)|pll;
            words[`LASER_DYN_WORD_GT_TXOUT*32 +:32]=1;
            words[`LASER_DYN_WORD_VERIFY_EXPECTED*32 +:32]=expected;
            words[`LASER_DYN_WORD_VERIFY_TOLERANCE*32 +:32]=5;
            words[`LASER_DYN_WORD_MMCM_COUNT*32 +:32]=1;
            words[`LASER_DYN_WORD_MMCM_BASE*32 +:32]=7'h08;
            words[(`LASER_DYN_WORD_MMCM_BASE+1)*32 +:32]=16'h1234;
        end
    endtask
    task reset_case;
        begin
            rst=1;start=0;refclk=0;abort=0;rollback=0;tx_idle=1;
            cpll_lock=1;qpll_lock=1;mmcm_lock=1;txresetdone=1;gt_ready=1;
            alive=1;gt_rdy_enable=1;mm_rdy_enable=1;freq=100;
            gt_cpll_reg=16'h1002;gt_out_reg=16'h0030;mmcm_reg=16'haaaa;
            repeat(3)@(posedge clk);@(negedge clk);rst=0;@(posedge clk);
        end
    endtask
    task launch;
        begin
            @(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
            while(!prepared&&!error)@(posedge clk);
            if(error)$fatal(1,"prepare error=%0d",failed);
            @(negedge clk);refclk=1;@(posedge clk);@(negedge clk);refclk=0;
        end
    endtask
    task expect_error(input [7:0] code);
        begin
            while(!error)@(posedge clk);
            if(failed!=code||!gt_reset||!user_block||!mm_reset)
                $fatal(1,"error mismatch got=%0d want=%0d state=%0d",failed,code,state);
        end
    endtask
    task rollback_ok;
        begin
            freq=100;cpll_lock=1;qpll_lock=1;mmcm_lock=1;txresetdone=1;gt_ready=1;
            gt_rdy_enable=1;mm_rdy_enable=1;
            @(negedge clk);rollback=1;@(posedge clk);@(negedge clk);rollback=0;
            while(!rb_done)@(posedge clk);
        end
    endtask

    initial begin
        #100000 $fatal(1,"global timeout state=%0d failed=%0d",state,failed);
    end
    initial begin
        // QPLL/GTNORTH success path.
        reset_case();build_desc(1,200);launch();freq=200;
        while(!done&&!error)@(posedge clk);
        if(!done||error||!qpll_sel||!north_sel)$fatal(1,"QPLL success path failed");

        // GT DRP timeout during the snapshot path.
        reset_case();build_desc(0,200);gt_rdy_enable=0;
        launch();expect_error(8'd5);rollback_ok();

        // PLL lock timeout after successful GT programming.
        reset_case();build_desc(0,200);cpll_lock=0;launch();expect_error(8'd7);rollback_ok();

        // MMCM DRP timeout after snapshot and PLL lock.
        reset_case();build_desc(0,200);launch();
        while(state!=8'd21)@(posedge clk);mm_rdy_enable=0;expect_error(8'd6);rollback_ok();

        // MMCM lock timeout.
        reset_case();build_desc(0,200);mmcm_lock=0;launch();expect_error(8'd8);rollback_ok();

        // TXRESETDONE/GT ready timeout.
        reset_case();build_desc(0,200);txresetdone=0;gt_ready=0;launch();expect_error(8'd9);rollback_ok();

        // ABORT uses the same safe rollback path.
        reset_case();build_desc(0,200);cpll_lock=0;launch();
        while(state!=8'd20)@(posedge clk);@(negedge clk);abort=1;@(posedge clk);@(negedge clk);abort=0;
        expect_error(8'd11);rollback_ok();

        // Active descriptor mutation is rejected before writes.
        reset_case();build_desc(0,200);@(negedge clk);start=1;@(posedge clk);@(negedge clk);start=0;
        while(!prepared)@(posedge clk);words[`LASER_DYN_WORD_SEQUENCE*32 +:32]=32'h55aa0002;
        expect_error(8'd12);rollback_ok();

        // A failed previous-rate verification must remain safely locked.
        reset_case();build_desc(0,200);launch();freq=5000;expect_error(8'd10);
        @(negedge clk);rollback=1;@(posedge clk);@(negedge clk);rollback=0;
        while(state!=8'd147)@(posedge clk);
        @(posedge clk);
        if(!error||!gt_reset||!user_block)$fatal(1,"rollback verify failure was not safe");

        $display("PASS: dynamic executor QPLL and injected failure/rollback paths");
        $finish;
    end
endmodule

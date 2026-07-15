`timescale 1ns/1ps
module laser_gt_rate_resource_arbiter_tb;
    reg clk=0, rst=1, legacy_busy=0, dyn_req=0, dyn_rel=0;
    reg l_reset=0, l_user_block=0, l_mmcm_reset=0, d_reset=1;
    wire grant, reject, legacy_allowed, owner, gt_reset, busy, conflict;
    wire [1:0] owner_code;
    always #5 clk=~clk;
    laser_gt_rate_resource_arbiter dut (
        .clk(clk),.rst(rst),.legacy_busy(legacy_busy),.dynamic_request(dyn_req),
        .dynamic_release(dyn_rel),.dynamic_grant(grant),
        .dynamic_reject(reject),.legacy_request_allowed(legacy_allowed),
        .owner_dynamic(owner),.owner(owner_code),.busy(busy),.conflict_error(conflict),
        .legacy_gt_reset(l_reset),.dynamic_gt_reset(d_reset),
        .legacy_txuserrdy_block(l_user_block),.dynamic_txuserrdy_block(1'b1),
        .legacy_mmcm_reset(l_mmcm_reset),.dynamic_mmcm_reset(1'b1),
        .legacy_cpll_reset(1'b0),.dynamic_cpll_reset(1'b1),
        .legacy_qpll_reset(1'b0),.dynamic_qpll_reset(1'b1),
        .legacy_qpll_selected(1'b0),.dynamic_qpll_selected(1'b1),
        .legacy_refclk_north_selected(1'b0),.dynamic_refclk_north_selected(1'b1),
        .legacy_apply_blocked(1'b0),.dynamic_apply_blocked(1'b1),
        .legacy_gt_drp_addr(9'h1),.dynamic_gt_drp_addr(9'h2),
        .legacy_gt_drp_di(16'h1111),.dynamic_gt_drp_di(16'h2222),
        .legacy_gt_drp_en(1'b0),.dynamic_gt_drp_en(1'b1),
        .legacy_gt_drp_we(1'b0),.dynamic_gt_drp_we(1'b1),
        .legacy_mmcm_drp_addr(7'h1),.dynamic_mmcm_drp_addr(7'h2),
        .legacy_mmcm_drp_di(16'h1111),.dynamic_mmcm_drp_di(16'h2222),
        .legacy_mmcm_drp_en(1'b0),.dynamic_mmcm_drp_en(1'b1),
        .legacy_mmcm_drp_we(1'b0),.dynamic_mmcm_drp_we(1'b1),
        .gt_reset(gt_reset),.txuserrdy_block(),.mmcm_reset(),.cpll_reset(),
        .qpll_reset(),.qpll_selected(),.refclk_north_selected(),.apply_blocked(),.gt_drp_addr(),
        .gt_drp_di(),.gt_drp_en(),.gt_drp_we(),.mmcm_drp_addr(),
        .mmcm_drp_di(),.mmcm_drp_en(),.mmcm_drp_we());
    initial begin
        repeat(2) @(posedge clk); rst=0;
        legacy_busy=1; dyn_req=1; @(posedge clk); #1;
        if(grant || !reject || !conflict || owner_code!=0) $fatal(1,"dynamic request was not rejected over busy legacy");
        dyn_req=0; @(posedge clk);
        legacy_busy=0; @(posedge clk); @(posedge clk);
        dyn_req=1; @(posedge clk); dyn_req=0; @(posedge clk);
        if(!grant || !owner || !gt_reset || legacy_allowed) $fatal(1,"grant/mux failed");
        legacy_busy=1; repeat(2) @(posedge clk);
        if(!grant) $fatal(1,"owner changed mid-transaction");
        legacy_busy=0;
        dyn_rel=1; @(posedge clk); dyn_rel=0; @(posedge clk);
        if(grant || !owner || !gt_reset)
            $fatal(1,"release did not retain programmed dynamic owner");
        legacy_busy=1; repeat(2) @(posedge clk);
        if(!owner) $fatal(1,"legacy owner changed before safe reset");
        l_reset=1; l_user_block=1; l_mmcm_reset=1;
        repeat(2) @(posedge clk);
        if(owner || !gt_reset) $fatal(1,"safe legacy takeover failed");
        $display("PASS: unique GT/MMCM resource arbitration"); $finish;
    end
endmodule

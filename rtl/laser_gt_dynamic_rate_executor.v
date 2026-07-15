`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"

// Executes one already-validated active descriptor. All GT/MMCM writes are
// read back before advancing. The previous hardware image remains valid until
// DONE and is restored only after the matching mailbox ROLLBACK_READY event.
module laser_gt_dynamic_rate_executor #(
    parameter integer RESET_HOLD_CYCLES = 1024,
    parameter integer TIMEOUT_CYCLES = 5000000,
    // PREPARED waits for PS to program/calibrate/measure AD9528 before it
    // raises REFCLK_READY. Keep this independent from the short hardware
    // DRP/lock timeout used by the remaining states.
    parameter integer REFCLK_READY_TIMEOUT_CYCLES = 250000000
) (
    input wire clk, input wire rst,
    input wire start, input wire descriptor_valid,
    input wire [2047:0] active_words_flat,
    input wire refclk_ready_event, input wire abort_event,
    input wire rollback_ready_event,
    output reg resource_request, input wire resource_grant,
    input wire resource_reject, input wire resource_owned,
    output reg resource_release,
    input wire tx_idle, input wire cplllock_sync, input wire qplllock_sync,
    input wire qpllrefclklost_sync, input wire tx_mmcm_locked_sync,
    input wire txresetdone_sync, input wire gt_ready_ctrl,
    input wire txusrclk2_alive_axi,
    input wire [31:0] txusrclk2_freq_counter_axi,
    input wire current_qpll_selected,
    input wire current_refclk_north_selected,
    input wire laser_enable_request,
    output reg gt_reset, output reg txuserrdy_block,
    output reg mmcm_reset, output reg cpll_reset, output reg qpll_reset,
    output reg qpll_selected, output reg refclk_north_selected,
    output reg apply_blocked,
    output reg [8:0] gt_drp_addr, output reg [15:0] gt_drp_di,
    input wire [15:0] gt_drp_do, output reg gt_drp_en,
    output reg gt_drp_we, input wire gt_drp_rdy,
    output reg [6:0] mmcm_drp_addr, output reg [15:0] mmcm_drp_di,
    input wire [15:0] mmcm_drp_do, output reg mmcm_drp_en,
    output reg mmcm_drp_we, input wire mmcm_drp_rdy,
    output reg prepared_ack, output reg switch_done,
    output reg switch_error, output reg rollback_done,
    output reg verify_pass, output reg [7:0] failed_stage,
    output reg [7:0] dynamic_state
);
    localparam [1:0] PLL_CPLL=0, PLL_QPLL=1;
    localparam [7:0]
        S_IDLE=0,S_VALIDATE=1,S_QUIESCE=2,S_ASSERT=3,S_PREPARED=4,
        S_SNAP_CPLL=5,S_SNAP_CPLL_W=6,S_SNAP_OUT=7,S_SNAP_OUT_W=8,
        S_SNAP_MMCM=9,S_SNAP_MMCM_W=10,S_SELECT=11,
        S_WRITE_CPLL=12,S_WRITE_CPLL_W=13,S_CHECK_CPLL=14,S_CHECK_CPLL_W=15,
        S_WRITE_OUT=16,S_WRITE_OUT_W=17,S_CHECK_OUT=18,S_CHECK_OUT_W=19,
        S_WAIT_PLL=20,S_WRITE_MMCM=21,S_WRITE_MMCM_W=22,
        S_CHECK_MMCM=23,S_CHECK_MMCM_W=24,S_WAIT_MMCM=25,
        S_RELEASE_GT=26,S_WAIT_READY=27,S_VERIFY=28,S_DONE=29,
        S_ERROR=128,S_WAIT_ROLLBACK=129,S_RB_SELECT=130,
        S_RB_CPLL=131,S_RB_CPLL_W=132,S_RB_CPLL_R=133,S_RB_CPLL_RW=134,
        S_RB_OUT=135,S_RB_OUT_W=136,S_RB_OUT_R=137,S_RB_OUT_RW=138,
        S_RB_MMCM=139,S_RB_MMCM_W=140,S_RB_MMCM_R=141,S_RB_MMCM_RW=142,
        S_RB_WAIT_PLL=143,S_RB_WAIT_MMCM=144,S_RB_WAIT_READY=145,
        S_RB_VERIFY=146,S_ROLLBACK_FAILED=147;
    localparam [7:0] E_NONE=0,E_DESCRIPTOR=1,E_RESOURCE=2,E_TX_IDLE=3,
        E_REFCLK=4,E_GT_DRP=5,E_MMCM_DRP=6,E_PLL_LOCK=7,
        E_MMCM_LOCK=8,E_GT_READY=9,E_VERIFY=10,E_ABORT=11,
        E_SEQUENCE=12,E_ROLLBACK=13;

    wire [31:0] descriptor_sequence =
        active_words_flat[`LASER_DYN_WORD_SEQUENCE*32 +: 32];
    wire [31:0] descriptor_flags =
        active_words_flat[`LASER_DYN_WORD_FLAGS*32 +: 32];
    wire [31:0] w10 = active_words_flat[`LASER_DYN_WORD_GT_PLL*32 +: 32];
    wire [31:0] w11 = active_words_flat[`LASER_DYN_WORD_GT_TXOUT*32 +: 32];
    wire [31:0] verify_expected =
        active_words_flat[`LASER_DYN_WORD_VERIFY_EXPECTED*32 +: 32];
    wire [31:0] verify_tolerance =
        active_words_flat[`LASER_DYN_WORD_VERIFY_TOLERANCE*32 +: 32];
    wire [7:0] mmcm_count =
        active_words_flat[`LASER_DYN_WORD_MMCM_COUNT*32 +: 8];
    wire [1:0] target_pll = w10[1:0];
    // Descriptor v1 carries the already-confirmed DRP field image, not the
    // mathematical M/N tuple. Bits [17:2] are the 0x05E value; only [12:0]
    // are applied by the read/modify/write sequence.
    wire [15:0] target_cpll_drp_value = w10[17:2];
    wire [2:0] target_outdiv = w11[2:0];
    // Descriptor v1 flags[0] identifies the AD9528/GTNORTHREFCLK path.
    wire target_refclk_north = descriptor_flags[0];
    wire [31:0] freq_low = (verify_expected > verify_tolerance) ?
        verify_expected - verify_tolerance : 0;
    wire [31:0] freq_high = verify_expected + verify_tolerance;
    wire target_freq_ok = txusrclk2_alive_axi &&
        txusrclk2_freq_counter_axi >= freq_low &&
        txusrclk2_freq_counter_axi <= freq_high;

    function [6:0] mmcm_addr_at;
        input [7:0] item;
        begin mmcm_addr_at = active_words_flat[
            (`LASER_DYN_WORD_MMCM_BASE*32)+(item*64) +: 7]; end
    endfunction
    function [15:0] mmcm_value_at;
        input [7:0] item;
        begin mmcm_value_at = active_words_flat[
            (`LASER_DYN_WORD_MMCM_BASE*32)+(item*64)+32 +: 16]; end
    endfunction
    function previous_freq_ok;
        input [31:0] actual; input [31:0] expected; input [31:0] tolerance;
        reg [31:0] delta;
        begin
            delta = (actual >= expected) ? actual-expected : expected-actual;
            previous_freq_ok = txusrclk2_alive_axi && (delta <= tolerance);
        end
    endfunction

    reg [31:0] timer, latched_sequence;
    reg [31:0] active_verify_expected, active_verify_tolerance;
    reg [31:0] previous_verify_expected, previous_verify_tolerance;
    reg active_verify_valid;
    reg [7:0] index;
    reg [15:0] saved_cpll, saved_outdiv, saved_mmcm[0:15];
    reg previous_qpll, previous_refclk_north, previous_laser_enable;
    reg snapshot_complete;
    integer i;

    task enter_error;
        input [7:0] code;
        begin
            dynamic_state <= S_ERROR; switch_error <= 1'b1;
            failed_stage <= code; gt_reset <= 1'b1;
            txuserrdy_block <= 1'b1; mmcm_reset <= 1'b1;
            apply_blocked <= 1'b1; cpll_reset <= 1'b1;
            qpll_reset <= 1'b1; timer <= 0;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            dynamic_state<=S_IDLE; resource_request<=0; resource_release<=0;
            gt_reset<=0;txuserrdy_block<=0;mmcm_reset<=0;cpll_reset<=0;
            qpll_reset<=0;qpll_selected<=0;refclk_north_selected<=0;
            apply_blocked<=0;gt_drp_addr<=0;gt_drp_di<=0;gt_drp_en<=0;
            gt_drp_we<=0;mmcm_drp_addr<=0;mmcm_drp_di<=0;
            mmcm_drp_en<=0;mmcm_drp_we<=0;prepared_ack<=0;
            switch_done<=0;switch_error<=0;rollback_done<=0;
            verify_pass<=0;failed_stage<=E_NONE;timer<=0;index<=0;
            saved_cpll<=0;saved_outdiv<=0;previous_qpll<=0;
            previous_refclk_north<=0;latched_sequence<=0;
            previous_laser_enable<=0;
            active_verify_expected<=0;active_verify_tolerance<=0;
            previous_verify_expected<=0;previous_verify_tolerance<=0;
            active_verify_valid<=0;
            snapshot_complete<=0;
            for(i=0;i<16;i=i+1) saved_mmcm[i]<=0;
        end else begin
            resource_release<=0;gt_drp_en<=0;gt_drp_we<=0;
            mmcm_drp_en<=0;mmcm_drp_we<=0;

            if (abort_event && dynamic_state!=S_IDLE && dynamic_state!=S_DONE &&
                dynamic_state!=S_WAIT_ROLLBACK && dynamic_state!=S_ROLLBACK_FAILED)
                enter_error(E_ABORT);
            else case(dynamic_state)
            S_IDLE: if(start) begin
                resource_request<=1;prepared_ack<=0;switch_done<=0;
                switch_error<=0;rollback_done<=0;verify_pass<=0;
                failed_stage<=E_NONE;snapshot_complete<=0;timer<=0;
                latched_sequence<=descriptor_sequence;dynamic_state<=S_VALIDATE;
            end
            S_VALIDATE: if(!descriptor_valid || mmcm_count>16 ||
                (target_pll!=PLL_CPLL && target_pll!=PLL_QPLL))
                    enter_error(E_DESCRIPTOR);
                else if(descriptor_sequence!=latched_sequence) enter_error(E_SEQUENCE);
                else if(resource_reject) begin resource_request<=0;enter_error(E_RESOURCE);end
                else if(resource_grant) begin
                    previous_qpll<=current_qpll_selected;
                    previous_refclk_north<=current_refclk_north_selected;
                    previous_laser_enable<=laser_enable_request;
                    previous_verify_expected<=active_verify_valid ?
                        active_verify_expected : txusrclk2_freq_counter_axi;
                    previous_verify_tolerance<=active_verify_valid ?
                        active_verify_tolerance : 32'd1000;
                    qpll_selected<=current_qpll_selected;
                    refclk_north_selected<=current_refclk_north_selected;
                    apply_blocked<=1;timer<=0;dynamic_state<=S_QUIESCE;
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_RESOURCE);
                else timer<=timer+1;
            S_QUIESCE: if(tx_idle) begin timer<=0;dynamic_state<=S_ASSERT;end
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_TX_IDLE);
                else timer<=timer+1;
            S_ASSERT: begin
                gt_reset<=1;txuserrdy_block<=1;mmcm_reset<=1;
                cpll_reset<=1;qpll_reset<=1;
                if(timer>=RESET_HOLD_CYCLES && resource_owned) begin
                    prepared_ack<=1;timer<=0;dynamic_state<=S_PREPARED;
                end else timer<=timer+1;
            end
            S_PREPARED: if(descriptor_sequence!=latched_sequence) enter_error(E_SEQUENCE);
                else if(refclk_ready_event) begin timer<=0;dynamic_state<=S_SNAP_CPLL;end
                else if(timer>=REFCLK_READY_TIMEOUT_CYCLES) enter_error(E_REFCLK);
                else timer<=timer+1;
            S_SNAP_CPLL: begin gt_drp_addr<=9'h05e;gt_drp_en<=1;timer<=0;dynamic_state<=S_SNAP_CPLL_W;end
            S_SNAP_CPLL_W: if(gt_drp_rdy) begin saved_cpll<=gt_drp_do;dynamic_state<=S_SNAP_OUT;end
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_DRP);else timer<=timer+1;
            S_SNAP_OUT: begin gt_drp_addr<=9'h088;gt_drp_en<=1;timer<=0;dynamic_state<=S_SNAP_OUT_W;end
            S_SNAP_OUT_W: if(gt_drp_rdy) begin saved_outdiv<=gt_drp_do;index<=0;dynamic_state<=S_SNAP_MMCM;end
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_DRP);else timer<=timer+1;
            S_SNAP_MMCM: if(index<mmcm_count) begin
                    mmcm_drp_addr<=mmcm_addr_at(index);mmcm_drp_en<=1;
                    timer<=0;dynamic_state<=S_SNAP_MMCM_W;
                end else begin snapshot_complete<=1;dynamic_state<=S_SELECT;end
            S_SNAP_MMCM_W: if(mmcm_drp_rdy) begin
                    saved_mmcm[index]<=mmcm_drp_do;index<=index+1;dynamic_state<=S_SNAP_MMCM;
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_MMCM_DRP);else timer<=timer+1;
            S_SELECT: begin
                qpll_selected<=(target_pll==PLL_QPLL);
                refclk_north_selected<=target_refclk_north;
                dynamic_state<=S_WRITE_CPLL;
            end
            S_WRITE_CPLL: if(target_pll==PLL_CPLL) begin
                    gt_drp_addr<=9'h05e;gt_drp_di<=(saved_cpll&16'he000)|
                        (target_cpll_drp_value&16'h1fff);
                    gt_drp_en<=1;gt_drp_we<=1;timer<=0;dynamic_state<=S_WRITE_CPLL_W;
                end else dynamic_state<=S_WRITE_OUT;
            S_WRITE_CPLL_W: if(gt_drp_rdy) dynamic_state<=S_CHECK_CPLL;
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_DRP);else timer<=timer+1;
            S_CHECK_CPLL: begin gt_drp_addr<=9'h05e;gt_drp_en<=1;timer<=0;dynamic_state<=S_CHECK_CPLL_W;end
            S_CHECK_CPLL_W: if(gt_drp_rdy) begin
                    if((gt_drp_do&16'h1fff)!=(target_cpll_drp_value&16'h1fff))
                        enter_error(E_GT_DRP); else dynamic_state<=S_WRITE_OUT;
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_DRP);else timer<=timer+1;
            S_WRITE_OUT: begin
                gt_drp_addr<=9'h088;gt_drp_di<=(saved_outdiv&16'hff8f)|({13'd0,target_outdiv}<<4);
                gt_drp_en<=1;gt_drp_we<=1;timer<=0;dynamic_state<=S_WRITE_OUT_W;
            end
            S_WRITE_OUT_W: if(gt_drp_rdy) dynamic_state<=S_CHECK_OUT;
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_DRP);else timer<=timer+1;
            S_CHECK_OUT: begin gt_drp_addr<=9'h088;gt_drp_en<=1;timer<=0;dynamic_state<=S_CHECK_OUT_W;end
            S_CHECK_OUT_W: if(gt_drp_rdy) begin
                    if((gt_drp_do&16'h0070)!=({13'd0,target_outdiv}<<4)) enter_error(E_GT_DRP);
                    else begin cpll_reset<=(target_pll!=PLL_CPLL);qpll_reset<=(target_pll!=PLL_QPLL);timer<=0;dynamic_state<=S_WAIT_PLL;end
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_DRP);else timer<=timer+1;
            S_WAIT_PLL: if(((target_pll==PLL_CPLL)&&cplllock_sync)||
                ((target_pll==PLL_QPLL)&&qplllock_sync&&!qpllrefclklost_sync)) begin
                    index<=0;dynamic_state<=S_WRITE_MMCM;
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_PLL_LOCK);else timer<=timer+1;
            S_WRITE_MMCM: if(index<mmcm_count) begin
                    mmcm_drp_addr<=mmcm_addr_at(index);mmcm_drp_di<=mmcm_value_at(index);
                    mmcm_drp_en<=1;mmcm_drp_we<=1;timer<=0;dynamic_state<=S_WRITE_MMCM_W;
                end else begin mmcm_reset<=0;timer<=0;dynamic_state<=S_WAIT_MMCM;end
            S_WRITE_MMCM_W: if(mmcm_drp_rdy) dynamic_state<=S_CHECK_MMCM;
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_MMCM_DRP);else timer<=timer+1;
            S_CHECK_MMCM: begin mmcm_drp_addr<=mmcm_addr_at(index);mmcm_drp_en<=1;timer<=0;dynamic_state<=S_CHECK_MMCM_W;end
            S_CHECK_MMCM_W: if(mmcm_drp_rdy) begin
                    if(mmcm_drp_do!=mmcm_value_at(index)) enter_error(E_MMCM_DRP);
                    else begin index<=index+1;dynamic_state<=S_WRITE_MMCM;end
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_MMCM_DRP);else timer<=timer+1;
            S_WAIT_MMCM: if(tx_mmcm_locked_sync) begin gt_reset<=0;timer<=0;dynamic_state<=S_RELEASE_GT;end
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_MMCM_LOCK);else timer<=timer+1;
            S_RELEASE_GT: begin txuserrdy_block<=0;timer<=0;dynamic_state<=S_WAIT_READY;end
            S_WAIT_READY: if(txresetdone_sync&&gt_ready_ctrl) begin timer<=0;dynamic_state<=S_VERIFY;end
                else if(timer>=TIMEOUT_CYCLES) enter_error(E_GT_READY);else timer<=timer+1;
            S_VERIFY: if(target_freq_ok) begin
                    verify_pass<=1;switch_done<=1;apply_blocked<=0;prepared_ack<=0;
                    active_verify_expected<=verify_expected;
                    active_verify_tolerance<=verify_tolerance;
                    active_verify_valid<=1;
                    timer<=0;dynamic_state<=S_DONE;
                end else if(timer>=TIMEOUT_CYCLES) enter_error(E_VERIFY);else timer<=timer+1;
            S_DONE: begin resource_request<=0;resource_release<=1;dynamic_state<=S_IDLE;end
            S_ERROR: dynamic_state<=S_WAIT_ROLLBACK;
            S_WAIT_ROLLBACK: if(rollback_ready_event) begin
                    qpll_selected<=previous_qpll;refclk_north_selected<=previous_refclk_north;
                    index<=0;timer<=0;dynamic_state<=S_RB_SELECT;
                end
            S_RB_SELECT: if(snapshot_complete) dynamic_state<=S_RB_CPLL;
                else begin
                    cpll_reset<=previous_qpll;qpll_reset<=!previous_qpll;
                    timer<=0;dynamic_state<=S_RB_WAIT_PLL;
                end
            S_RB_CPLL: begin gt_drp_addr<=9'h05e;gt_drp_di<=saved_cpll;gt_drp_en<=1;gt_drp_we<=1;timer<=0;dynamic_state<=S_RB_CPLL_W;end
            S_RB_CPLL_W: if(gt_drp_rdy) dynamic_state<=S_RB_CPLL_R;else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_CPLL_R: begin gt_drp_addr<=9'h05e;gt_drp_en<=1;timer<=0;dynamic_state<=S_RB_CPLL_RW;end
            S_RB_CPLL_RW: if(gt_drp_rdy) begin if(gt_drp_do!=saved_cpll) dynamic_state<=S_ROLLBACK_FAILED;else dynamic_state<=S_RB_OUT;end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_OUT: begin gt_drp_addr<=9'h088;gt_drp_di<=saved_outdiv;gt_drp_en<=1;gt_drp_we<=1;timer<=0;dynamic_state<=S_RB_OUT_W;end
            S_RB_OUT_W: if(gt_drp_rdy) dynamic_state<=S_RB_OUT_R;else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_OUT_R: begin gt_drp_addr<=9'h088;gt_drp_en<=1;timer<=0;dynamic_state<=S_RB_OUT_RW;end
            S_RB_OUT_RW: if(gt_drp_rdy) begin if(gt_drp_do!=saved_outdiv) dynamic_state<=S_ROLLBACK_FAILED;else begin index<=0;dynamic_state<=S_RB_MMCM;end end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_MMCM: if(index<mmcm_count) begin mmcm_drp_addr<=mmcm_addr_at(index);mmcm_drp_di<=saved_mmcm[index];mmcm_drp_en<=1;mmcm_drp_we<=1;timer<=0;dynamic_state<=S_RB_MMCM_W;end
                else begin cpll_reset<=previous_qpll;qpll_reset<=!previous_qpll;timer<=0;dynamic_state<=S_RB_WAIT_PLL;end
            S_RB_MMCM_W: if(mmcm_drp_rdy) dynamic_state<=S_RB_MMCM_R;else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_MMCM_R: begin mmcm_drp_addr<=mmcm_addr_at(index);mmcm_drp_en<=1;timer<=0;dynamic_state<=S_RB_MMCM_RW;end
            S_RB_MMCM_RW: if(mmcm_drp_rdy) begin if(mmcm_drp_do!=saved_mmcm[index]) dynamic_state<=S_ROLLBACK_FAILED;else begin index<=index+1;dynamic_state<=S_RB_MMCM;end end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_WAIT_PLL: if((previous_qpll&&qplllock_sync&&!qpllrefclklost_sync)||(!previous_qpll&&cplllock_sync)) begin mmcm_reset<=0;timer<=0;dynamic_state<=S_RB_WAIT_MMCM;end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_WAIT_MMCM: if(tx_mmcm_locked_sync) begin gt_reset<=0;txuserrdy_block<=0;timer<=0;dynamic_state<=S_RB_WAIT_READY;end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_WAIT_READY: if(txresetdone_sync&&gt_ready_ctrl) begin timer<=0;dynamic_state<=S_RB_VERIFY;end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_RB_VERIFY: if(previous_freq_ok(txusrclk2_freq_counter_axi,
                    previous_verify_expected,previous_verify_tolerance)) begin
                    rollback_done<=1;switch_error<=0;apply_blocked<=0;prepared_ack<=0;
                    active_verify_expected<=previous_verify_expected;
                    active_verify_tolerance<=previous_verify_tolerance;
                    active_verify_valid<=1;
                    resource_request<=0;resource_release<=1;dynamic_state<=S_IDLE;
                end else if(timer>=TIMEOUT_CYCLES) dynamic_state<=S_ROLLBACK_FAILED;else timer<=timer+1;
            S_ROLLBACK_FAILED: begin switch_error<=1;failed_stage<=E_ROLLBACK;
                gt_reset<=1;txuserrdy_block<=1;mmcm_reset<=1;apply_blocked<=1;
            end
            default: enter_error(E_DESCRIPTOR);
            endcase
        end
    end
endmodule

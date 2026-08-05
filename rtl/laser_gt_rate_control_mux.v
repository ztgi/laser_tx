`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"
// Compatibility shell that keeps legacy status semantics while placing the
// legacy FSM and descriptor-driven executor behind one physical-resource mux.
module laser_gt_rate_control_mux (
    input wire clk,input wire rst,input wire [31:0] gpio_ctrl,input wire [31:0] gpio_status,
    input wire cplllock_sync,input wire qplllock_sync,input wire qpllrefclklost_sync,
    input wire txresetdone_sync,input wire tx_mmcm_locked_sync,input wire gt_ready_ctrl,
    input wire txusrclk2_alive_axi,input wire [31:0] txusrclk2_freq_counter_axi,
    input wire dynamic_start,input wire dynamic_descriptor_valid,
    input wire [2047:0] dynamic_words,input wire dynamic_refclk_ready,
    input wire dynamic_abort,input wire dynamic_rollback_ready,
    output wire dynamic_prepared,output wire dynamic_done,output wire dynamic_error,
    output wire dynamic_rollback_done,output wire dynamic_verify_pass,
    output wire [7:0] dynamic_failed_stage,output wire [7:0] dynamic_state,
    output wire rate_gt_tx_reset,output wire rate_txuserrdy_block,
    output wire rate_mmcm_reset,output wire rate_cpll_reset,output wire rate_qpll_reset,
    output wire qpll_selected,output wire refclk_north_selected,
    output wire apply_enable_blocked,
    output wire [8:0] gt_drp_addr,output wire [15:0] gt_drp_di,
    input wire [15:0] gt_drp_do,output wire gt_drp_en,output wire gt_drp_we,input wire gt_drp_rdy,
    output wire [6:0] mmcm_drp_addr,output wire [15:0] mmcm_drp_di,
    input wire [15:0] mmcm_drp_do,output wire mmcm_drp_en,output wire mmcm_drp_we,input wire mmcm_drp_rdy,
    output wire [7:0] rate_state,output wire [15:0] target_rate_mbps,
    output wire [15:0] current_rate_mbps,output wire [3:0] current_rate_id,
    output wire [1:0] target_pll_type_dbg,output wire [1:0] active_pll_type_dbg,
    output wire [1:0] programmed_pll_type_dbg,output wire rate_busy,output wire rate_done,
    output wire rate_error,output wire already_current_rate,output wire [7:0] rate_error_code,
    output wire gt_drp_busy,output wire gt_drp_done,output wire gt_drp_error,
    output wire gt_drp_write_attempted,output wire [15:0] gt_drp_readback_value,
    output wire mmcm_drp_busy,output wire mmcm_drp_done,output wire mmcm_drp_error,
    output wire mmcm_drp_write_attempted,output wire tx_quiesce_req,
    output wire tx_idle_seen,output wire [31:0] dbg_timeout_count,
    output reg [2:0] eom_subdiv_log2
);
    wire l_gt_reset,l_user_block,l_mmcm_reset,l_cpll_reset,l_qpll_reset,l_qpll_sel,l_apply;
    wire [8:0] l_ga;wire [15:0] l_gd;wire l_ge,l_gw;
    wire [6:0] l_ma;wire [15:0] l_md;wire l_me,l_mw;
    wire d_req,d_grant,d_reject,d_release,d_gt_reset,d_user_block,d_mmcm_reset,d_cpll_reset,d_qpll_reset,d_qpll_sel,d_refclk_north,d_apply;
    wire [8:0] d_ga;wire [15:0] d_gd;wire d_ge,d_gw;
    wire [6:0] d_ma;wire [15:0] d_md;wire d_me,d_mw;
    wire legacy_allowed, dynamic_owner;
    reg [2:0] previous_eom_subdiv_log2;
    wire [2:0] descriptor_eom_subdiv_log2 =
        dynamic_words[`LASER_DYN_WORD_EOM_CONFIG*32 +: 3];

    function [2:0] fixed_eom_subdiv_log2;
        input [3:0] rate_id;
        begin
            case (rate_id)
                4'd1, 4'd10: fixed_eom_subdiv_log2 = 3'd4;
                4'd2, 4'd4: fixed_eom_subdiv_log2 = 3'd3;
                4'd3, 4'd5, 4'd7: fixed_eom_subdiv_log2 = 3'd2;
                4'd6, 4'd8, 4'd11: fixed_eom_subdiv_log2 = 3'd1;
                4'd9: fixed_eom_subdiv_log2 = 3'd0;
                default: fixed_eom_subdiv_log2 = 3'd4;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            eom_subdiv_log2 <= 3'd4;
            previous_eom_subdiv_log2 <= 3'd4;
        end else begin
            if (dynamic_start && !dynamic_owner)
                previous_eom_subdiv_log2 <= eom_subdiv_log2;
            if (dynamic_done && dynamic_descriptor_valid)
                eom_subdiv_log2 <= descriptor_eom_subdiv_log2;
            else if (dynamic_rollback_done)
                eom_subdiv_log2 <= previous_eom_subdiv_log2;
            else if (!dynamic_owner && rate_done && !rate_error)
                eom_subdiv_log2 <= fixed_eom_subdiv_log2(current_rate_id);
        end
    end

    laser_gt_rate_switch_500m_1000m u_legacy(
        .clk(clk),.rst(rst),.request_enable(legacy_allowed),.gpio_ctrl(gpio_ctrl),.gpio_status(gpio_status),
        .cplllock_sync(cplllock_sync),.qplllock_sync(qplllock_sync),.qpllrefclklost_sync(qpllrefclklost_sync),
        .txresetdone_sync(txresetdone_sync),.tx_mmcm_locked_sync(tx_mmcm_locked_sync),.gt_ready_ctrl(gt_ready_ctrl),
        .txusrclk2_alive_axi(txusrclk2_alive_axi),.txusrclk2_freq_counter_axi(txusrclk2_freq_counter_axi),
        .rate_gt_tx_reset(l_gt_reset),.rate_txuserrdy_block(l_user_block),.rate_mmcm_reset(l_mmcm_reset),
        .rate_cpll_reset(l_cpll_reset),.rate_qpll_reset(l_qpll_reset),.qpll_selected(l_qpll_sel),
        .apply_enable_blocked(l_apply),.gt_drp_addr(l_ga),.gt_drp_di(l_gd),.gt_drp_do(gt_drp_do),
        .gt_drp_en(l_ge),.gt_drp_we(l_gw),.gt_drp_rdy(gt_drp_rdy),.mmcm_drp_addr(l_ma),
        .mmcm_drp_di(l_md),.mmcm_drp_do(mmcm_drp_do),.mmcm_drp_en(l_me),.mmcm_drp_we(l_mw),
        .mmcm_drp_rdy(mmcm_drp_rdy),.rate_state(rate_state),.target_rate_mbps(target_rate_mbps),
        .current_rate_mbps(current_rate_mbps),.current_rate_id(current_rate_id),
        .target_pll_type_dbg(target_pll_type_dbg),.active_pll_type_dbg(active_pll_type_dbg),
        .programmed_pll_type_dbg(programmed_pll_type_dbg),.rate_busy(rate_busy),.rate_done(rate_done),
        .rate_error(rate_error),.already_current_rate(already_current_rate),.rate_error_code(rate_error_code),
        .gt_drp_busy(gt_drp_busy),.gt_drp_done(gt_drp_done),.gt_drp_error(gt_drp_error),
        .gt_drp_write_attempted(gt_drp_write_attempted),.gt_drp_readback_value(gt_drp_readback_value),
        .mmcm_drp_busy(mmcm_drp_busy),.mmcm_drp_done(mmcm_drp_done),.mmcm_drp_error(mmcm_drp_error),
        .mmcm_drp_write_attempted(mmcm_drp_write_attempted),.tx_quiesce_req(tx_quiesce_req),
        .tx_idle_seen(tx_idle_seen),.dbg_timeout_count(dbg_timeout_count));

    laser_gt_dynamic_rate_executor u_dynamic(
        .clk(clk),.rst(rst),.start(dynamic_start),.descriptor_valid(dynamic_descriptor_valid),
        .active_words_flat(dynamic_words),.refclk_ready_event(dynamic_refclk_ready),.abort_event(dynamic_abort),
        .rollback_ready_event(dynamic_rollback_ready),.resource_request(d_req),.resource_grant(d_grant),
        .resource_reject(d_reject),
        .resource_owned(dynamic_owner),
        .resource_release(d_release),.tx_idle((!gpio_status[3])|gpio_status[4]),
        .cplllock_sync(cplllock_sync),.qplllock_sync(qplllock_sync),.qpllrefclklost_sync(qpllrefclklost_sync),
        .tx_mmcm_locked_sync(tx_mmcm_locked_sync),.txresetdone_sync(txresetdone_sync),.gt_ready_ctrl(gt_ready_ctrl),
        .txusrclk2_alive_axi(txusrclk2_alive_axi),.txusrclk2_freq_counter_axi(txusrclk2_freq_counter_axi),
        .current_qpll_selected(qpll_selected),.current_refclk_north_selected(refclk_north_selected),
        .laser_enable_request(gpio_ctrl[9]),
        .gt_reset(d_gt_reset),.txuserrdy_block(d_user_block),
        .mmcm_reset(d_mmcm_reset),.cpll_reset(d_cpll_reset),.qpll_reset(d_qpll_reset),
        .qpll_selected(d_qpll_sel),.refclk_north_selected(d_refclk_north),
        .apply_blocked(d_apply),.gt_drp_addr(d_ga),.gt_drp_di(d_gd),
        .gt_drp_do(gt_drp_do),.gt_drp_en(d_ge),.gt_drp_we(d_gw),.gt_drp_rdy(gt_drp_rdy),
        .mmcm_drp_addr(d_ma),.mmcm_drp_di(d_md),.mmcm_drp_do(mmcm_drp_do),
        .mmcm_drp_en(d_me),.mmcm_drp_we(d_mw),.mmcm_drp_rdy(mmcm_drp_rdy),
        .prepared_ack(dynamic_prepared),.switch_done(dynamic_done),.switch_error(dynamic_error),
        .rollback_done(dynamic_rollback_done),.verify_pass(dynamic_verify_pass),
        .failed_stage(dynamic_failed_stage),.dynamic_state(dynamic_state));

    laser_gt_rate_resource_arbiter u_arbiter(
        .clk(clk),.rst(rst),.legacy_busy(rate_busy),.dynamic_request(d_req),.dynamic_release(d_release),
        .dynamic_grant(d_grant),.dynamic_reject(d_reject),.legacy_request_allowed(legacy_allowed),.owner_dynamic(dynamic_owner),
        .legacy_gt_reset(l_gt_reset),.dynamic_gt_reset(d_gt_reset),
        .legacy_txuserrdy_block(l_user_block),.dynamic_txuserrdy_block(d_user_block),
        .legacy_mmcm_reset(l_mmcm_reset),.dynamic_mmcm_reset(d_mmcm_reset),
        .legacy_cpll_reset(l_cpll_reset),.dynamic_cpll_reset(d_cpll_reset),
        .legacy_qpll_reset(l_qpll_reset),.dynamic_qpll_reset(d_qpll_reset),
        .legacy_qpll_selected(l_qpll_sel),.dynamic_qpll_selected(d_qpll_sel),
        .legacy_refclk_north_selected(1'b0),.dynamic_refclk_north_selected(d_refclk_north),
        .legacy_apply_blocked(l_apply),.dynamic_apply_blocked(d_apply),
        .legacy_gt_drp_addr(l_ga),.dynamic_gt_drp_addr(d_ga),.legacy_gt_drp_di(l_gd),.dynamic_gt_drp_di(d_gd),
        .legacy_gt_drp_en(l_ge),.dynamic_gt_drp_en(d_ge),.legacy_gt_drp_we(l_gw),.dynamic_gt_drp_we(d_gw),
        .legacy_mmcm_drp_addr(l_ma),.dynamic_mmcm_drp_addr(d_ma),.legacy_mmcm_drp_di(l_md),.dynamic_mmcm_drp_di(d_md),
        .legacy_mmcm_drp_en(l_me),.dynamic_mmcm_drp_en(d_me),.legacy_mmcm_drp_we(l_mw),.dynamic_mmcm_drp_we(d_mw),
        .gt_reset(rate_gt_tx_reset),.txuserrdy_block(rate_txuserrdy_block),.mmcm_reset(rate_mmcm_reset),
        .cpll_reset(rate_cpll_reset),.qpll_reset(rate_qpll_reset),.qpll_selected(qpll_selected),
        .refclk_north_selected(refclk_north_selected),
        .apply_blocked(apply_enable_blocked),.gt_drp_addr(gt_drp_addr),.gt_drp_di(gt_drp_di),
        .gt_drp_en(gt_drp_en),.gt_drp_we(gt_drp_we),.mmcm_drp_addr(mmcm_drp_addr),
        .mmcm_drp_di(mmcm_drp_di),.mmcm_drp_en(mmcm_drp_en),.mmcm_drp_we(mmcm_drp_we));
endmodule

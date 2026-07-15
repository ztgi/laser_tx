`timescale 1ns/1ps

// The only mux allowed to drive shared GT/MMCM/reset resources. Legacy keeps
// ownership by default. A dynamic request first reserves the resources; the
// physical mux changes owner only after the requesting executor has asserted
// the safe reset/block controls. The last programmed owner remains selected
// after a transaction, so a successful runtime PLL/refclk selection cannot
// snap back when the reservation is released.
module laser_gt_rate_resource_arbiter (
    input  wire        clk,
    input  wire        rst,
    input  wire        legacy_busy,
    input  wire        dynamic_request,
    input  wire        dynamic_release,
    output reg         dynamic_grant,
    output reg         dynamic_reject,
    output wire        legacy_request_allowed,
    output wire        owner_dynamic,
    output wire [1:0]  owner,
    output wire        busy,
    output reg         conflict_error,

    input wire legacy_gt_reset, input wire dynamic_gt_reset,
    input wire legacy_txuserrdy_block, input wire dynamic_txuserrdy_block,
    input wire legacy_mmcm_reset, input wire dynamic_mmcm_reset,
    input wire legacy_cpll_reset, input wire dynamic_cpll_reset,
    input wire legacy_qpll_reset, input wire dynamic_qpll_reset,
    input wire legacy_qpll_selected, input wire dynamic_qpll_selected,
    input wire legacy_refclk_north_selected, input wire dynamic_refclk_north_selected,
    input wire legacy_apply_blocked, input wire dynamic_apply_blocked,
    input wire [8:0] legacy_gt_drp_addr, input wire [8:0] dynamic_gt_drp_addr,
    input wire [15:0] legacy_gt_drp_di, input wire [15:0] dynamic_gt_drp_di,
    input wire legacy_gt_drp_en, input wire dynamic_gt_drp_en,
    input wire legacy_gt_drp_we, input wire dynamic_gt_drp_we,
    input wire [6:0] legacy_mmcm_drp_addr, input wire [6:0] dynamic_mmcm_drp_addr,
    input wire [15:0] legacy_mmcm_drp_di, input wire [15:0] dynamic_mmcm_drp_di,
    input wire legacy_mmcm_drp_en, input wire dynamic_mmcm_drp_en,
    input wire legacy_mmcm_drp_we, input wire dynamic_mmcm_drp_we,

    output wire gt_reset,
    output wire txuserrdy_block,
    output wire mmcm_reset,
    output wire cpll_reset,
    output wire qpll_reset,
    output wire qpll_selected,
    output wire refclk_north_selected,
    output wire apply_blocked,
    output wire [8:0] gt_drp_addr,
    output wire [15:0] gt_drp_di,
    output wire gt_drp_en,
    output wire gt_drp_we,
    output wire [6:0] mmcm_drp_addr,
    output wire [15:0] mmcm_drp_di,
    output wire mmcm_drp_en,
    output wire mmcm_drp_we
);
    reg owner_dynamic_reg;
    wire dynamic_takeover_safe = dynamic_gt_reset &&
        dynamic_txuserrdy_block && dynamic_mmcm_reset;
    wire legacy_takeover_safe = legacy_gt_reset &&
        legacy_txuserrdy_block && legacy_mmcm_reset;

    assign owner_dynamic = owner_dynamic_reg;
    assign owner = owner_dynamic_reg ? 2'd1 : 2'd0;
    assign busy = legacy_busy | dynamic_grant | dynamic_request;
    // A legacy request may be decoded while the dynamic steady-state image is
    // selected. The physical owner changes only when the legacy FSM reaches
    // its safe-reset phase.
    assign legacy_request_allowed = !dynamic_grant && !dynamic_request;

    always @(posedge clk) begin
        if (rst) begin
            dynamic_grant <= 1'b0;
            dynamic_reject <= 1'b0;
            conflict_error <= 1'b0;
            owner_dynamic_reg <= 1'b0;
        end else begin
            dynamic_reject <= 1'b0;
            if (dynamic_grant && legacy_busy)
                conflict_error <= 1'b1;
            if (dynamic_grant) begin
            if (dynamic_release)
                dynamic_grant <= 1'b0;
            end else if (dynamic_request) begin
                if (legacy_busy) begin
                    dynamic_reject <= 1'b1;
                    conflict_error <= 1'b1;
                end else begin
                    dynamic_grant <= 1'b1;
                end
            end

            if (!owner_dynamic_reg && dynamic_grant && dynamic_takeover_safe)
                owner_dynamic_reg <= 1'b1;
            else if (owner_dynamic_reg && !dynamic_grant && legacy_busy &&
                     legacy_takeover_safe)
                owner_dynamic_reg <= 1'b0;
        end
    end

    // Reset/block controls are ORed during a pending handoff. Source selects
    // and DRP controls always come from the locked physical owner.
    assign gt_reset = owner_dynamic_reg ? dynamic_gt_reset :
        (legacy_gt_reset | (dynamic_grant && dynamic_gt_reset));
    assign txuserrdy_block = owner_dynamic_reg ? dynamic_txuserrdy_block :
        (legacy_txuserrdy_block | (dynamic_grant && dynamic_txuserrdy_block));
    assign mmcm_reset = owner_dynamic_reg ? dynamic_mmcm_reset :
        (legacy_mmcm_reset | (dynamic_grant && dynamic_mmcm_reset));
    assign cpll_reset = owner_dynamic_reg ? dynamic_cpll_reset :
        (legacy_cpll_reset | (dynamic_grant && dynamic_cpll_reset));
    assign qpll_reset = owner_dynamic_reg ? dynamic_qpll_reset :
        (legacy_qpll_reset | (dynamic_grant && dynamic_qpll_reset));
    assign qpll_selected = owner_dynamic_reg ? dynamic_qpll_selected : legacy_qpll_selected;
    assign refclk_north_selected = owner_dynamic_reg ? dynamic_refclk_north_selected : legacy_refclk_north_selected;
    assign apply_blocked = owner_dynamic_reg ? dynamic_apply_blocked :
        (legacy_apply_blocked | (dynamic_grant && dynamic_apply_blocked));
    assign gt_drp_addr = owner_dynamic_reg ? dynamic_gt_drp_addr : legacy_gt_drp_addr;
    assign gt_drp_di = owner_dynamic_reg ? dynamic_gt_drp_di : legacy_gt_drp_di;
    assign gt_drp_en = owner_dynamic_reg ? dynamic_gt_drp_en : legacy_gt_drp_en;
    assign gt_drp_we = owner_dynamic_reg ? dynamic_gt_drp_we : legacy_gt_drp_we;
    assign mmcm_drp_addr = owner_dynamic_reg ? dynamic_mmcm_drp_addr : legacy_mmcm_drp_addr;
    assign mmcm_drp_di = owner_dynamic_reg ? dynamic_mmcm_drp_di : legacy_mmcm_drp_di;
    assign mmcm_drp_en = owner_dynamic_reg ? dynamic_mmcm_drp_en : legacy_mmcm_drp_en;
    assign mmcm_drp_we = owner_dynamic_reg ? dynamic_mmcm_drp_we : legacy_mmcm_drp_we;
endmodule

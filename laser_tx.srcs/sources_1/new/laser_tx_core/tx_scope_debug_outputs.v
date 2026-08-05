`timescale 1ns/1ps

// Observation-only TX scope outputs. Neither output feeds back into the TX
// scheduler, GT reset path, user-clock network, or rate controller.
module tx_scope_debug_outputs #(
    parameter integer SYNC_WIDTH_CYCLES = 16
) (
    input  wire txusrclk2,
    input  wire reset_tx,
    input  wire sequence_word_fire,
    output wire gt_sequence_sync_out,
    output wire txusrclk2_monitor_out
);
    localparam integer SYNC_COUNT_WIDTH =
        (SYNC_WIDTH_CYCLES <= 1) ? 1 : $clog2(SYNC_WIDTH_CYCLES + 1);

    reg [SYNC_COUNT_WIDTH-1:0] sync_width_count;

    // reset_tx is already synchronized to TXUSRCLK2 by the caller. Keeping
    // this counter on a purely synchronous control path avoids a LUT-combined
    // asynchronous clear tree while preserving the pulse's first-edge timing.
    always @(posedge txusrclk2) begin
        if (reset_tx)
            sync_width_count <= {SYNC_COUNT_WIDTH{1'b0}};
        else if (sequence_word_fire)
            sync_width_count <= SYNC_WIDTH_CYCLES;
        else if (sync_width_count != 0)
            sync_width_count <= sync_width_count - 1'b1;
    end

    assign gt_sequence_sync_out = (sync_width_count != 0);

    // XC7Z100 is a 7-series device. Forward TXUSRCLK2 through a dedicated
    // output DDR register instead of using the clock as ordinary fabric data.
    // D1=1 and D2=0 produce one full-rate, nominal 50% duty-cycle output.
    (* IOB = "TRUE" *) ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_txusrclk2_monitor_oddr (
        .Q  (txusrclk2_monitor_out),
        .C  (txusrclk2),
        .CE (1'b1),
        .D1 (1'b1),
        .D2 (1'b0),
        .R  (reset_tx),
        .S  (1'b0)
    );
endmodule

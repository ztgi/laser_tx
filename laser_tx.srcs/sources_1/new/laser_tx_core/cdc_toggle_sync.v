`timescale 1ns/1ps

// Synchronize an event encoded as a toggle and recreate a one-cycle pulse.
module cdc_toggle_sync (
    input  wire dst_clk,
    input  wire dst_rst,
    input  wire src_toggle,
    output reg  dst_pulse,
    output reg  dst_toggle
);
    (* ASYNC_REG = "TRUE" *) reg sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg sync_ff2;

    always @(posedge dst_clk) begin
        if (dst_rst) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
            dst_toggle <= 1'b0;
            dst_pulse <= 1'b0;
        end else begin
            sync_ff1 <= src_toggle;
            sync_ff2 <= sync_ff1;
            dst_pulse <= sync_ff2 ^ dst_toggle;
            dst_toggle <= sync_ff2;
        end
    end
endmodule

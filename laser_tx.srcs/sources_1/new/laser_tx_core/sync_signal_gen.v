`timescale 1ns/1ps

module sync_signal_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire [63:0] valid_mask,
    input  wire        phase_active,
    input  wire        phase_start_pulse,
    output reg         eom_out,
    output reg         soa_gate_out,
    output reg         acq_trig_out,
    output reg         acq_gate_out
);
    // Combinational derivation keeps these pins aligned with the registered
    // TX word; no independent timing state is introduced here.
    always @* begin
        if (rst) begin
            eom_out <= 1'b0;
            soa_gate_out <= 1'b0;
            acq_trig_out <= 1'b0;
            acq_gate_out <= 1'b0;
        end else begin
            eom_out <= |valid_mask;
            soa_gate_out <= phase_active;
            acq_trig_out <= phase_start_pulse;
            acq_gate_out <= phase_active;
        end
    end
    wire unused_clk = clk;
endmodule

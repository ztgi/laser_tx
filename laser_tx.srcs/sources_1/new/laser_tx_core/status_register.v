`timescale 1ns/1ps

module status_register (
    input  wire         cfg_valid,
    input  wire         cfg_error,
    input  wire         pattern_valid,
    input  wire         busy,
    input  wire         done,
    input  wire         phase_active,
    input  wire         sequence_active,
    input  wire [7:0]   phase_offset,
    input  wire [7:0]   current_state,
    input  wire [7:0]   error_code,
    output wire [31:0]  gpio_status
);
    assign gpio_status = {
        error_code,
        current_state,
        phase_offset,
        1'b0,
        sequence_active,
        phase_active,
        done,
        busy,
        pattern_valid,
        cfg_error,
        cfg_valid
    };
endmodule

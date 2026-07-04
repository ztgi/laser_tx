`timescale 1ns/1ps

// Build one complete PRBS period, or pass through a direct pattern.
module pattern_source (
    input  wire         cfg_valid,
    input  wire         source_sel,
    input  wire [7:0]   prbs_order,
    input  wire [7:0]   pattern_len,
    input  wire [31:0]  seed,
    input  wire [126:0] pattern_in,
    output reg  [126:0] base_pattern,
    output reg          pattern_valid
);
    integer i;
    reg [5:0] lfsr6;
    reg [6:0] lfsr7;

    always @* begin
        base_pattern = 127'b0;
        pattern_valid = 1'b0;
        lfsr6 = (seed[5:0] == 6'b0) ? 6'h3f : seed[5:0];
        lfsr7 = (seed[6:0] == 7'b0) ? 7'h7f : seed[6:0];

        if (cfg_valid) begin
            if (source_sel) begin
                if ((pattern_len == 8'd63) || (pattern_len == 8'd127)) begin
                    base_pattern = pattern_in;
                    if (pattern_len == 8'd63)
                        base_pattern[126:63] = 64'b0;
                    pattern_valid = 1'b1;
                end
            end else if ((prbs_order == 8'd6) && (pattern_len == 8'd63)) begin
                for (i = 0; i < 63; i = i + 1) begin
                    base_pattern[i] = lfsr6[5];
                    lfsr6 = {lfsr6[4:0], lfsr6[5] ^ lfsr6[4]};
                end
                pattern_valid = 1'b1;
            end else if ((prbs_order == 8'd7) && (pattern_len == 8'd127)) begin
                for (i = 0; i < 127; i = i + 1) begin
                    base_pattern[i] = lfsr7[6];
                    lfsr7 = {lfsr7[5:0], lfsr7[6] ^ lfsr7[5]};
                end
                pattern_valid = 1'b1;
            end
        end
    end
endmodule

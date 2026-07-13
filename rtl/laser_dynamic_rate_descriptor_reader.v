`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"

// Copies the PS shadow descriptor into transaction-owned active storage and
// validates its header, bounds and CRC-32/ISO-HDLC. The source BRAM is not
// consulted again after done is asserted.
module laser_dynamic_rate_descriptor_reader (
    input  wire          clk,
    input  wire          rst,
    input  wire          start,
    output reg           bram_en,
    output reg  [7:0]    bram_word_addr,
    input  wire [31:0]   bram_rdata,
    output reg           busy,
    output reg           done,
    output reg           descriptor_valid,
    output reg  [7:0]    error_code,
    output wire [2047:0] active_words_flat
);
    localparam [7:0] ERR_NONE       = 8'd0;
    localparam [7:0] ERR_MAGIC      = 8'd1;
    localparam [7:0] ERR_VERSION    = 8'd2;
    localparam [7:0] ERR_WORD_COUNT = 8'd3;
    localparam [7:0] ERR_CRC        = 8'd4;
    localparam [7:0] ERR_MMCM_COUNT = 8'd5;

    reg [31:0] active_words [0:63];
    reg [7:0] request_index;
    reg [7:0] capture_index;
    reg capture_valid;
    reg [31:0] crc_state;
    integer k;

    genvar g;
    generate
        for (g = 0; g < 64; g = g + 1) begin : g_flat
            assign active_words_flat[g*32 +: 32] = active_words[g];
        end
    endgenerate

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data;
        integer b;
        reg [31:0] c;
        begin
            c = crc_in ^ data;
            for (b = 0; b < 8; b = b + 1)
                c = c[0] ? ((c >> 1) ^ `LASER_DYN_CRC32_POLY) : (c >> 1);
            crc32_byte = c;
        end
    endfunction

    function [31:0] crc32_word_le;
        input [31:0] crc_in;
        input [31:0] data;
        reg [31:0] c;
        begin
            c = crc32_byte(crc_in, data[7:0]);
            c = crc32_byte(c, data[15:8]);
            c = crc32_byte(c, data[23:16]);
            crc32_word_le = crc32_byte(c, data[31:24]);
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            bram_en <= 1'b0;
            bram_word_addr <= 8'd0;
            busy <= 1'b0;
            done <= 1'b0;
            descriptor_valid <= 1'b0;
            error_code <= ERR_NONE;
            request_index <= 8'd0;
            capture_index <= 8'd0;
            capture_valid <= 1'b0;
            crc_state <= `LASER_DYN_CRC32_INIT;
            for (k = 0; k < 64; k = k + 1)
                active_words[k] <= 32'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                descriptor_valid <= 1'b0;
                error_code <= ERR_NONE;
                request_index <= 8'd0;
                capture_valid <= 1'b0;
                crc_state <= `LASER_DYN_CRC32_INIT;
                bram_en <= 1'b1;
                bram_word_addr <= 8'd0;
            end else if (busy) begin
                if (capture_valid) begin
                    active_words[capture_index] <= bram_rdata;
                    if (capture_index != `LASER_DYN_WORD_CRC32)
                        crc_state <= crc32_word_le(crc_state, bram_rdata);
                end

                if (request_index < 8'd63) begin
                    request_index <= request_index + 1'b1;
                    bram_word_addr <= request_index + 1'b1;
                    capture_index <= request_index;
                    capture_valid <= 1'b1;
                end else if (!capture_valid || capture_index != 8'd63) begin
                    capture_index <= request_index;
                    capture_valid <= 1'b1;
                    bram_en <= 1'b0;
                end else begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    capture_valid <= 1'b0;
                    if (active_words[`LASER_DYN_WORD_MAGIC] != `LASER_DYN_DESC_MAGIC)
                        error_code <= ERR_MAGIC;
                    else if (active_words[`LASER_DYN_WORD_VERSION_COUNT][15:0] != `LASER_DYN_DESC_VERSION)
                        error_code <= ERR_VERSION;
                    else if (active_words[`LASER_DYN_WORD_VERSION_COUNT][31:16] != `LASER_DYN_DESC_WORDS)
                        error_code <= ERR_WORD_COUNT;
                    else if (active_words[`LASER_DYN_WORD_MMCM_COUNT][7:0] > `LASER_DYN_DESC_MAX_MMCM_WRITES)
                        error_code <= ERR_MMCM_COUNT;
                    else if (active_words[`LASER_DYN_WORD_CRC32] !=
                             (crc32_word_le(crc_state, bram_rdata) ^ `LASER_DYN_CRC32_XOROUT))
                        error_code <= ERR_CRC;
                    else begin
                        descriptor_valid <= 1'b1;
                        error_code <= ERR_NONE;
                    end
                end
            end else begin
                bram_en <= 1'b0;
            end
        end
    end
endmodule

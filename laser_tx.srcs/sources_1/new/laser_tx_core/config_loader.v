`timescale 1ns/1ps

// Atomic reader for the protocol-incompatible fixed 16-word TX sequence record.
module config_loader (
    input  wire        clk,
    input  wire        rstn,
    input  wire [7:0]  config_index,
    input  wire        apply_toggle,
    output reg         bram_en,
    output reg  [31:0] bram_addr,
    input  wire [31:0] bram_dout,
    output reg         cfg_valid,
    output reg         cfg_error,
    output reg  [7:0]  error_code,
    output reg         cfg_update_toggle,
    output reg  [4:0]  repeat_cycles,
    output reg  [7:0]  head_delay_bits,
    output reg  [119:0] gap_len_bits,
    output reg         eom_enable,
    output reg  [10:0] eom_global_pattern_index,
    output reg  [15:0] eom_lead_ticks,
    output reg  [15:0] eom_trail_ticks,
    output reg         phase_shift_en,
    output reg         loop_en,
    output reg  [7:0]  pattern_len,
    output reg  [126:0] configured_pattern
);
    localparam [2:0] S_IDLE=3'd0, S_WAIT=3'd1, S_CAPTURE=3'd2,
                     S_HEADER_WAIT=3'd3, S_HEADER_CHECK=3'd4;
    localparam [15:0] HEADER_MAGIC=16'h5458;
    localparam [3:0] FORMAT_VERSION=4'd2;
    localparam [7:0] RECORD_WORDS=8'd16;
    localparam [7:0] MAX_CONFIGS=8'd128;
    localparam [7:0] MAX_REPEAT=8'd16;
    localparam [7:0] GAP_WIDTH=8'd8;
    localparam [7:0] ERR_NONE=8'h00, ERR_INDEX=8'h10,
                     ERR_HEADER=8'h11, ERR_FORMAT=8'h12,
                     ERR_CRC=8'h13, ERR_ATOMIC=8'h14;

    reg [2:0] state;
    reg apply_seen;
    reg [4:0] word_index;
    reg [31:0] base_addr;
    reg [31:0] header_first;
    reg [31:0] crc_state;
    reg [31:0] words [1:14];
    integer i;

    function [31:0] crc32_word_le;
        input [31:0] crc_in;
        input [31:0] data;
        reg [31:0] crc;
        reg [31:0] value;
        integer bit_index;
        begin
            crc = crc_in;
            value = data;
            for (bit_index=0; bit_index<32; bit_index=bit_index+1) begin
                crc = (crc[0] ^ value[0]) ?
                      ((crc >> 1) ^ 32'hEDB88320) : (crc >> 1);
                value = value >> 1;
            end
            crc32_word_le = crc;
        end
    endfunction

    wire header_valid =
        (header_first[31:16] == HEADER_MAGIC) &&
        (header_first[15:12] == FORMAT_VERSION) &&
        header_first[11] && (header_first[10:8] == 3'b000);
    wire [4:0] record_repeat = words[2][4:0];
    // TX Sequence V2 keeps the original word positions for protocol/layout
    // compatibility, but word1 (seed), word2[12:5] (PRBS order) and
    // word2[15] (source select) are now reserved/ignored. The configured
    // pattern payload in words9..12 is the sole pattern source.
    wire [7:0] selected_len = words[2][16] ? 8'd127 : 8'd63;
    wire structure_valid =
        (record_repeat >= 5'd1) && (record_repeat <= 5'd16) &&
        (words[2][31:29] == 3'b000) &&
        (words[3][31:8] == 24'd0) &&
        (words[7][31:24] == 8'd0) &&
        (words[12][31] == 1'b0) &&
        (words[13][7:0] == header_first[7:0]) &&
        (words[13][15:8] == RECORD_WORDS) &&
        (words[13][23:16] == MAX_REPEAT) &&
        (words[13][31:24] == GAP_WIDTH) &&
        (words[14] == 32'd0);

    task finish_error;
        input [7:0] code;
        begin
            bram_en <= 1'b0;
            cfg_error <= 1'b1;
            error_code <= code;
            state <= S_IDLE;
        end
    endtask

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;
            apply_seen <= 1'b0;
            word_index <= 5'd0;
            base_addr <= 32'd0;
            header_first <= 32'd0;
            crc_state <= 32'hFFFFFFFF;
            bram_en <= 1'b0;
            bram_addr <= 32'd0;
            cfg_valid <= 1'b0;
            cfg_error <= 1'b0;
            error_code <= ERR_NONE;
            cfg_update_toggle <= 1'b0;
            repeat_cycles <= 5'd0;
            head_delay_bits <= 8'd0;
            gap_len_bits <= 120'd0;
            eom_enable <= 1'b0;
            eom_global_pattern_index <= 11'd0;
            eom_lead_ticks <= 16'd0;
            eom_trail_ticks <= 16'd0;
            phase_shift_en <= 1'b0;
            loop_en <= 1'b0;
            pattern_len <= 8'd0;
            configured_pattern <= 127'd0;
            for (i=1; i<=14; i=i+1)
                words[i] <= 32'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    bram_en <= 1'b0;
                    if (apply_toggle != apply_seen) begin
                        apply_seen <= apply_toggle;
                        cfg_error <= 1'b0;
                        error_code <= ERR_NONE;
                        if (config_index >= MAX_CONFIGS) begin
                            cfg_error <= 1'b1;
                            error_code <= ERR_INDEX;
                        end else begin
                            // 16 words * 4 bytes = 64 bytes per record.
                            base_addr <= ({24'd0, config_index} << 6);
                            bram_addr <= ({24'd0, config_index} << 6);
                            word_index <= 5'd0;
                            crc_state <= 32'hFFFFFFFF;
                            bram_en <= 1'b1;
                            state <= S_WAIT;
                        end
                    end
                end
                S_WAIT: begin
                    bram_en <= 1'b1;
                    state <= S_CAPTURE;
                end
                S_CAPTURE: begin
                    if (word_index == 5'd0) begin
                        header_first <= bram_dout;
                        if ((bram_dout[31:16] != HEADER_MAGIC) ||
                            (bram_dout[15:12] != FORMAT_VERSION) ||
                            !bram_dout[11] || (bram_dout[10:8] != 3'b000)) begin
                            finish_error(ERR_HEADER);
                        end else begin
                            word_index <= 5'd1;
                            bram_addr <= base_addr + 32'd4;
                            state <= S_WAIT;
                        end
                    end else if (word_index <= 5'd14) begin
                        words[word_index] <= bram_dout;
                        crc_state <= crc32_word_le(crc_state, bram_dout);
                        word_index <= word_index + 1'b1;
                        bram_addr <= base_addr + ((word_index + 1'b1) << 2);
                        state <= S_WAIT;
                    end else begin
                        // Word 15 is stored CRC; words 1..14 were accumulated.
                        if (bram_dout != (~crc_state)) begin
                            finish_error(ERR_CRC);
                        end else if (!header_valid || !structure_valid) begin
                            finish_error(ERR_FORMAT);
                        end else begin
                            bram_addr <= base_addr;
                            state <= S_HEADER_WAIT;
                        end
                    end
                end
                S_HEADER_WAIT: begin
                    bram_en <= 1'b1;
                    state <= S_HEADER_CHECK;
                end
                S_HEADER_CHECK: begin
                    bram_en <= 1'b0;
                    if ((bram_dout != header_first) || !header_valid) begin
                        finish_error(ERR_ATOMIC);
                    end else begin
                        // Atomic active-bundle update after both header reads,
                        // metadata validation and payload CRC all pass.
                        cfg_valid <= 1'b1;
                        cfg_error <= 1'b0;
                        error_code <= ERR_NONE;
                        repeat_cycles <= record_repeat;
                        phase_shift_en <= words[2][13];
                        loop_en <= words[2][14];
                        pattern_len <= selected_len;
                        head_delay_bits <= words[3][7:0];
                        gap_len_bits <= {words[7][23:0], words[6], words[5], words[4]};
                        eom_enable <= words[2][17];
                        eom_global_pattern_index <= words[2][28:18];
                        eom_lead_ticks <= words[8][15:0];
                        eom_trail_ticks <= words[8][31:16];
                        configured_pattern <= {words[12][30:0], words[11],
                                               words[10], words[9]};
                        cfg_update_toggle <= ~cfg_update_toggle;
                        state <= S_IDLE;
                    end
                end
                default: finish_error(ERR_FORMAT);
            endcase
        end
    end
endmodule

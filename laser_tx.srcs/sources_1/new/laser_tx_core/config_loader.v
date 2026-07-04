`timescale 1ns/1ps

// Read one 32-byte parameter record from the second BRAM port.
// BRAM address is byte based and bram_dout is assumed to have one-cycle latency.
module config_loader (
    input  wire         clk,
    input  wire         rstn,
    input  wire [7:0]   config_index,
    input  wire         apply_toggle,
    input  wire         source_sel,
    input  wire         direct_len_sel,
    output reg          bram_en,
    output reg  [31:0]  bram_addr,
    input  wire [31:0]  bram_dout,
    output reg          cfg_valid,
    output reg          cfg_error,
    output reg  [7:0]   error_code,
    output reg          cfg_update_toggle,
    output reg  [31:0]  seed,
    output reg  [31:0]  repeat_cycles,
    output reg  [7:0]   gap_len_bits,
    output reg  [15:0]  insert_after,
    output reg  [7:0]   prbs_order,
    output reg          phase_shift_en,
    output reg          loop_en,
    output reg          active_source_sel,
    output reg  [7:0]   pattern_len,
    output reg  [126:0] direct_pattern
);
    localparam ST_IDLE = 2'd0;
    localparam ST_WAIT = 2'd1;
    localparam ST_CAP  = 2'd2;

    reg [1:0] state;
    reg apply_seen;
    reg [2:0] word_index;
    reg [31:0] base_addr;
    reg latched_source_sel;
    reg latched_direct_len_sel;
    reg [31:0] words [0:6];
    reg [7:0] selected_len;
    reg invalid;
    reg [7:0] new_error_code;
    integer j;

    always @* begin
        selected_len = latched_source_sel ?
                       (latched_direct_len_sel ? 8'd127 : 8'd63) :
                       ((words[3][7:0] == 8'd6) ? 8'd63 : 8'd127);
        invalid = 1'b0;
        new_error_code = 8'h00;
        if (words[1] == 0) begin
            invalid = 1'b1;
            new_error_code = 8'h01;
        end else if ((words[3][7:0] != 8'd6) && (words[3][7:0] != 8'd7)) begin
            invalid = 1'b1;
            new_error_code = 8'h02;
        end else if (words[2][23:8] > words[1]) begin
            invalid = 1'b1;
            new_error_code = 8'h03;
        end else if ((selected_len != 8'd63) && (selected_len != 8'd127)) begin
            invalid = 1'b1;
            new_error_code = 8'h04;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            state <= ST_IDLE;
            apply_seen <= 1'b0;
            word_index <= 3'b0;
            base_addr <= 32'b0;
            latched_source_sel <= 1'b0;
            latched_direct_len_sel <= 1'b0;
            bram_en <= 1'b0;
            bram_addr <= 32'b0;
            cfg_valid <= 1'b0;
            cfg_error <= 1'b0;
            error_code <= 8'b0;
            cfg_update_toggle <= 1'b0;
            seed <= 32'b0;
            repeat_cycles <= 32'b0;
            gap_len_bits <= 8'b0;
            insert_after <= 16'b0;
            prbs_order <= 8'b0;
            phase_shift_en <= 1'b0;
            loop_en <= 1'b0;
            active_source_sel <= 1'b0;
            pattern_len <= 8'b0;
            direct_pattern <= 127'b0;
            for (j = 0; j < 7; j = j + 1)
                words[j] <= 32'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    bram_en <= 1'b0;
                    if (apply_toggle != apply_seen) begin
                        apply_seen <= apply_toggle;
                        base_addr <= {config_index, 5'b0};
                        latched_source_sel <= source_sel;
                        latched_direct_len_sel <= direct_len_sel;
                        word_index <= 3'b0;
                        bram_addr <= {config_index, 5'b0};
                        bram_en <= 1'b1;
                        state <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    // Keep address stable for a complete synchronous BRAM read.
                    bram_en <= 1'b1;
                    state <= ST_CAP;
                end

                ST_CAP: begin
                    if (word_index < 3'd7) begin
                        words[word_index] <= bram_dout;
                        word_index <= word_index + 1'b1;
                        bram_addr <= base_addr + {27'b0, (word_index + 1'b1), 2'b00};
                        state <= ST_WAIT;
                    end else begin
                        bram_en <= 1'b0;
                        cfg_valid <= !invalid;
                        cfg_error <= invalid;
                        error_code <= new_error_code;
                        seed <= (words[0] == 0) ?
                                ((words[3][7:0] == 8'd6) ? 32'h0000003f : 32'h0000007f) :
                                words[0];
                        repeat_cycles <= words[1];
                        gap_len_bits <= words[2][7:0];
                        insert_after <= words[2][23:8];
                        prbs_order <= words[3][7:0];
                        phase_shift_en <= words[3][8];
                        loop_en <= words[3][9];
                        active_source_sel <= latched_source_sel;
                        pattern_len <= selected_len;
                        direct_pattern <= {bram_dout[30:0], words[6], words[5], words[4]};
                        cfg_update_toggle <= ~cfg_update_toggle;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

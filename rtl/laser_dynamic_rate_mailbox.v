`timescale 1ns/1ps
`include "laser_dynamic_rate_descriptor.vh"

module laser_dynamic_rate_mailbox (
    input  wire          clk,
    input  wire          rst,
    input  wire [3:0]    control_toggles,
    output wire [31:0]   status_gpio,
    output wire          bram_en,
    output wire [7:0]    bram_word_addr,
    output wire [3:0]    bram_we,
    output wire [31:0]   bram_wdata,
    input  wire [31:0]   bram_rdata,
    output wire          active_descriptor_valid,
    output wire [2047:0] active_words_flat,
    output reg           refclk_ready_event,
    output reg           abort_event,
    output reg           rollback_ready_event
);
    reg [3:0] toggle_d;
    reg prepare_start;
    reg busy_latched;
    reg prepared_ack;
    reg switch_done;
    reg switch_error;
    reg rollback_done;
    reg verify_pass;
    reg sequence_error;
    reg [7:0] failed_stage;
    wire reader_busy;
    wire reader_done;
    wire [7:0] reader_error;
    wire reader_bram_en;
    wire [7:0] reader_bram_addr;
    wire [31:0] active_sequence = active_words_flat[`LASER_DYN_WORD_SEQUENCE*32 +: 32];
    reg status_write_active;
    reg [1:0] status_write_index;

    assign bram_en = status_write_active ? 1'b1 : reader_bram_en;
    assign bram_word_addr = status_write_active ?
        (`LASER_DYN_WORD_STATUS_SEQUENCE + status_write_index) : reader_bram_addr;
    assign bram_we = status_write_active ? 4'hF : 4'h0;
    assign bram_wdata = (status_write_index == 2'd0) ? active_sequence :
                        (status_write_index == 2'd1) ?
                            {8'd0, failed_stage, 8'd0, reader_error} :
                        (status_write_index == 2'd2) ? 32'd0 : status_gpio;

    laser_dynamic_rate_descriptor_reader u_reader (
        .clk(clk), .rst(rst), .start(prepare_start),
        .bram_en(reader_bram_en), .bram_word_addr(reader_bram_addr),
        .bram_rdata(bram_rdata), .busy(reader_busy), .done(reader_done),
        .descriptor_valid(active_descriptor_valid), .error_code(reader_error),
        .active_words_flat(active_words_flat)
    );

    assign status_gpio = {
        active_sequence[15:0], failed_stage, sequence_error, verify_pass,
        active_descriptor_valid, rollback_done, switch_error, switch_done,
        prepared_ack, (busy_latched | reader_busy)
    };

    always @(posedge clk) begin
        if (rst) begin
            toggle_d <= control_toggles;
            prepare_start <= 1'b0;
            busy_latched <= 1'b0;
            prepared_ack <= 1'b0;
            switch_done <= 1'b0;
            switch_error <= 1'b0;
            rollback_done <= 1'b0;
            verify_pass <= 1'b0;
            sequence_error <= 1'b0;
            failed_stage <= 8'd0;
            refclk_ready_event <= 1'b0;
            abort_event <= 1'b0;
            rollback_ready_event <= 1'b0;
            status_write_active <= 1'b0;
            status_write_index <= 2'd0;
        end else begin
            toggle_d <= control_toggles; // busy events are consumed, never replayed
            prepare_start <= 1'b0;
            refclk_ready_event <= 1'b0;
            abort_event <= 1'b0;
            rollback_ready_event <= 1'b0;

            if (status_write_active) begin
                if (status_write_index == 2'd3)
                    status_write_active <= 1'b0;
                else
                    status_write_index <= status_write_index + 1'b1;
            end

            if ((control_toggles[0] != toggle_d[0]) && !busy_latched &&
                !reader_busy && !status_write_active) begin
                prepare_start <= 1'b1;
                busy_latched <= 1'b1;
                prepared_ack <= 1'b0;
                switch_done <= 1'b0;
                switch_error <= 1'b0;
                rollback_done <= 1'b0;
                verify_pass <= 1'b0;
                sequence_error <= 1'b0;
                failed_stage <= 8'd0;
            end

            if (reader_done) begin
                status_write_active <= 1'b1;
                status_write_index <= 2'd0;
                if (active_descriptor_valid) begin
                    prepared_ack <= 1'b1;
                end else begin
                    busy_latched <= 1'b0;
                    switch_error <= 1'b1;
                    failed_stage <= reader_error;
                end
            end

            if (control_toggles[1] != toggle_d[1]) begin
                if (prepared_ack)
                    refclk_ready_event <= 1'b1;
                else
                    sequence_error <= 1'b1;
            end
            if (control_toggles[2] != toggle_d[2]) begin
                abort_event <= busy_latched;
                busy_latched <= 1'b0;
                prepared_ack <= 1'b0;
                rollback_done <= 1'b1;
            end
            if (control_toggles[3] != toggle_d[3]) begin
                rollback_ready_event <= switch_error;
                if (!switch_error)
                    sequence_error <= 1'b1;
            end
        end
    end
endmodule

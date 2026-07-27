`timescale 1ns/1ps

// TX Sequence V2 EOM controller.
//
// The TX-domain task bundle is held stable until a request/acknowledge toggle
// handshake completes. Geometry is calculated entirely in the related EOM
// clock domain. A second "armed seen" toggle closes the acknowledgement
// loop before the controller schedules a deterministic common TX/EOM boundary.
module tx_eom_window_generator (
    input  wire         tx_clk,
    input  wire         tx_abort,
    input  wire         task_request_pulse_tx,
    input  wire         eom_enable_tx,
    input  wire [10:0]  global_pattern_index_tx,
    input  wire [15:0]  lead_ticks_tx,
    input  wire [15:0]  trail_ticks_tx,
    input  wire [4:0]   repeat_cycles_tx,
    input  wire [7:0]   pattern_len_tx,
    input  wire         phase_shift_en_tx,
    input  wire [7:0]   head_delay_bits_tx,
    input  wire [119:0] gap_len_bits_tx,
    input  wire [2:0]   eom_subdiv_log2_tx,
    input  wire         eom_clk,
    input  wire         clock_safe,
    output reg          geometry_armed_tx,
    output wire         tx_start_level,
    output reg          request_valid_tx,
    output reg          request_busy_tx,
    output wire         eom_out,
    output reg          eom_active,
    output reg          eom_fired,
    output reg          done_toggle,
    // Simulation/debug observability; these do not feed production control.
    output reg          geometry_valid_eom,
    output reg          eom_armed,
    output reg          alignment_valid_eom,
    output reg          task_zero_pulse_eom,
    output reg  [23:0]  task_tick_counter_eom,
    output reg  [23:0]  start_tick_local_eom,
    output reg  [23:0]  end_tick_local_eom,
    output reg  [7:0]   selected_phase_eom,
    output reg  [3:0]   selected_repeat_eom
);
    localparam [3:0] E_IDLE           = 4'd0;
    localparam [3:0] E_WAIT_GEOMETRY_LOW = 4'd1;
    localparam [3:0] E_WAIT_GEOMETRY  = 4'd2;
    localparam [3:0] E_WAIT_ACK_SEEN  = 4'd3;
    localparam [3:0] E_WAIT_BOUNDARY  = 4'd4;
    localparam [3:0] E_WAIT_TX_ARM    = 4'd5;
    localparam [3:0] E_WAIT_TASK_ZERO = 4'd6;
    localparam [3:0] E_ACTIVE         = 4'd7;

    // TX-domain stable snapshot and request/acknowledge handshake.
    reg request_toggle_tx;
    reg armed_seen_toggle_tx;
    reg ack_seen_tx;
    reg         snapshot_eom_enable_tx;
    reg [10:0]  snapshot_global_pattern_index_tx;
    reg [15:0]  snapshot_lead_ticks_tx;
    reg [15:0]  snapshot_trail_ticks_tx;
    reg [4:0]   snapshot_repeat_cycles_tx;
    reg [7:0]   snapshot_pattern_len_tx;
    reg         snapshot_phase_shift_en_tx;
    reg [7:0]   snapshot_head_delay_bits_tx;
    reg [119:0] snapshot_gap_len_bits_tx;
    reg [2:0]   snapshot_eom_subdiv_log2_tx;

    reg ack_toggle_eom;
    reg request_valid_hold_eom;
    (* ASYNC_REG = "TRUE" *) reg ack_toggle_meta_tx;
    (* ASYNC_REG = "TRUE" *) reg ack_toggle_sync_tx;
    (* ASYNC_REG = "TRUE" *) reg [1:0] tx_reset_pipe;
    wire tx_reset_sync = tx_reset_pipe[1];

    // The raw ready/clock-safe abort may assert while tx_clk is stopped.
    // Restrict that asynchronous control to this local reset synchronizer;
    // all TX-side EOM snapshot/handshake state uses the synchronized reset.
    always @(posedge tx_clk or posedge tx_abort) begin
        if (tx_abort) begin
            tx_reset_pipe <= 2'b11;
        end else begin
            tx_reset_pipe <= {tx_reset_pipe[0], 1'b0};
        end
    end

    always @(posedge tx_clk) begin
        if (tx_reset_sync) begin
            request_toggle_tx                <= 1'b0;
            armed_seen_toggle_tx             <= 1'b0;
            ack_seen_tx                      <= 1'b0;
            geometry_armed_tx                <= 1'b0;
            request_valid_tx                 <= 1'b0;
            request_busy_tx                  <= 1'b0;
            ack_toggle_meta_tx               <= 1'b0;
            ack_toggle_sync_tx               <= 1'b0;
            snapshot_eom_enable_tx           <= 1'b0;
            snapshot_global_pattern_index_tx <= 11'd0;
            snapshot_lead_ticks_tx           <= 16'd0;
            snapshot_trail_ticks_tx          <= 16'd0;
            snapshot_repeat_cycles_tx        <= 5'd0;
            snapshot_pattern_len_tx          <= 8'd0;
            snapshot_phase_shift_en_tx       <= 1'b0;
            snapshot_head_delay_bits_tx      <= 8'd0;
            snapshot_gap_len_bits_tx         <= 120'd0;
            snapshot_eom_subdiv_log2_tx      <= 3'd0;
        end else begin
            ack_toggle_meta_tx <= ack_toggle_eom;
            ack_toggle_sync_tx <= ack_toggle_meta_tx;

            if (task_request_pulse_tx && !request_busy_tx) begin
                // The bundle is captured before the request toggle is visible
                // in EOM and held until the acknowledge returns.
                snapshot_eom_enable_tx           <= eom_enable_tx;
                snapshot_global_pattern_index_tx <= global_pattern_index_tx;
                snapshot_lead_ticks_tx           <= lead_ticks_tx;
                snapshot_trail_ticks_tx          <= trail_ticks_tx;
                snapshot_repeat_cycles_tx        <= repeat_cycles_tx;
                snapshot_pattern_len_tx          <= pattern_len_tx;
                snapshot_phase_shift_en_tx       <= phase_shift_en_tx;
                snapshot_head_delay_bits_tx      <= head_delay_bits_tx;
                snapshot_gap_len_bits_tx         <= gap_len_bits_tx;
                snapshot_eom_subdiv_log2_tx      <= eom_subdiv_log2_tx;
                request_toggle_tx                <= ~request_toggle_tx;
                request_busy_tx                  <= 1'b1;
                geometry_armed_tx                <= 1'b0;
                request_valid_tx                 <= 1'b0;
            end

            if (ack_toggle_sync_tx != ack_seen_tx) begin
                ack_seen_tx          <= ack_toggle_sync_tx;
                request_busy_tx      <= 1'b0;
                geometry_armed_tx    <= 1'b1;
                request_valid_tx     <= request_valid_hold_eom;
                armed_seen_toggle_tx <= ~armed_seen_toggle_tx;
            end
        end
    end

    // EOM-domain request capture. The stable-bundle handshake replaces
    // unsafe bit-by-bit synchronization of the multi-bit configuration.
    (* ASYNC_REG = "TRUE" *) reg request_toggle_meta_eom;
    (* ASYNC_REG = "TRUE" *) reg request_toggle_sync_eom;
    reg request_seen_eom;
    (* ASYNC_REG = "TRUE" *) reg armed_seen_toggle_meta_eom;
    (* ASYNC_REG = "TRUE" *) reg armed_seen_toggle_sync_eom;
    reg armed_seen_eom;

    reg         eom_enable_local;
    reg [10:0]  global_pattern_index_local;
    reg [15:0]  lead_ticks_local;
    reg [15:0]  trail_ticks_local;
    reg [4:0]   repeat_cycles_local;
    reg [7:0]   pattern_len_local;
    reg         phase_shift_en_local;
    reg [7:0]   head_delay_bits_local;
    reg [119:0] gap_len_bits_local;
    reg [2:0]   eom_subdiv_log2_local;

    reg geometry_start_eom;
    wire geometry_ready_eom;
    wire geometry_request_valid_eom;
    wire [23:0] geometry_start_tick_eom;
    wire [23:0] geometry_end_tick_eom;
    wire [7:0] geometry_selected_phase_eom;
    wire [3:0] geometry_selected_repeat_eom;
    (* ASYNC_REG = "TRUE" *) reg [1:0] clock_safe_pipe;
    wire eom_reset_sync = !clock_safe_pipe[1];

    tx_eom_geometry_precompute u_geometry_eom (
        .clk(eom_clk), .rst(eom_reset_sync), .start(geometry_start_eom),
        .eom_enable(eom_enable_local),
        .global_pattern_index(global_pattern_index_local),
        .lead_ticks(lead_ticks_local), .trail_ticks(trail_ticks_local),
        .repeat_cycles(repeat_cycles_local), .pattern_len(pattern_len_local),
        .phase_shift_en(phase_shift_en_local),
        .head_delay_bits(head_delay_bits_local),
        .gap_len_bits(gap_len_bits_local),
        .eom_subdiv_log2(eom_subdiv_log2_local),
        .ready(geometry_ready_eom),
        .request_valid(geometry_request_valid_eom),
        .start_tick(geometry_start_tick_eom),
        .end_tick(geometry_end_tick_eom),
        .selected_phase(geometry_selected_phase_eom),
        .selected_repeat(geometry_selected_repeat_eom)
    );

    // CLKOUT0/TXUSRCLK2 and CLKOUT2/EOM are zero-phase sibling outputs of the
    // same MMCM.  A local modulo-K phase counter therefore identifies the
    // deterministic common word boundary without sampling a clock as data.
    // Loading a new stable snapshot restarts alignment for K=16/8/4/1.
    reg [4:0] boundary_phase_eom;
    wire [4:0] boundary_terminal_eom =
        (5'd1 << eom_subdiv_log2_local) - 1'b1;
    // request_toggle_tx is launched on a TX word edge.  The two EOM-domain
    // synchronizer stages plus registered event observation place snapshot
    // acceptance four EOM ticks after that source boundary.  K is a power of
    // two, so masking implements 4 modulo K without a divider/modulo operator.
    wire [4:0] snapshot_boundary_seed_eom =
        5'd4 & ((5'd1 << snapshot_eom_subdiv_log2_tx) - 1'b1);
    wire tx_boundary_in_eom_domain =
        alignment_valid_eom && (boundary_phase_eom == 5'd0);

    // Change the persistent start level on EOM falling edges so it is stable
    // before every possible common rising boundary.
    reg tx_start_level_request_eom;
    reg tx_start_level_fall;
    assign tx_start_level = tx_start_level_fall;

    always @(negedge eom_clk) begin
        if (eom_reset_sync)
            tx_start_level_fall <= 1'b0;
        else
            tx_start_level_fall <= tx_start_level_request_eom;
    end

    reg [3:0] eom_state;
    reg eom_window;
    assign eom_out = eom_window & clock_safe & clock_safe_pipe[1];

    // Immediate assertion and two-edge synchronous recovery.
    always @(posedge eom_clk or negedge clock_safe) begin
        if (!clock_safe)
            clock_safe_pipe <= 2'b00;
        else
            clock_safe_pipe <= {clock_safe_pipe[0], 1'b1};
    end

    always @(posedge eom_clk) begin
        if (eom_reset_sync) begin
            request_toggle_meta_eom    <= 1'b0;
            request_toggle_sync_eom    <= 1'b0;
            request_seen_eom           <= 1'b0;
            armed_seen_toggle_meta_eom <= 1'b0;
            armed_seen_toggle_sync_eom <= 1'b0;
            armed_seen_eom             <= 1'b0;
            boundary_phase_eom         <= 5'd0;
            alignment_valid_eom        <= 1'b0;
            geometry_start_eom         <= 1'b0;
            geometry_valid_eom         <= 1'b0;
            eom_armed                  <= 1'b0;
            task_zero_pulse_eom        <= 1'b0;
            task_tick_counter_eom      <= 24'd0;
            start_tick_local_eom       <= 24'd0;
            end_tick_local_eom         <= 24'd0;
            selected_phase_eom         <= 8'd0;
            selected_repeat_eom        <= 4'd0;
            eom_enable_local           <= 1'b0;
            global_pattern_index_local <= 11'd0;
            lead_ticks_local           <= 16'd0;
            trail_ticks_local          <= 16'd0;
            repeat_cycles_local        <= 5'd0;
            pattern_len_local          <= 8'd0;
            phase_shift_en_local       <= 1'b0;
            head_delay_bits_local      <= 8'd0;
            gap_len_bits_local         <= 120'd0;
            eom_subdiv_log2_local      <= 3'd0;
            ack_toggle_eom             <= 1'b0;
            request_valid_hold_eom     <= 1'b0;
            tx_start_level_request_eom <= 1'b0;
            eom_window                 <= 1'b0;
            eom_active                 <= 1'b0;
            eom_fired                  <= 1'b0;
            done_toggle                <= 1'b0;
            eom_state                  <= E_IDLE;
        end else begin
            request_toggle_meta_eom    <= request_toggle_tx;
            request_toggle_sync_eom    <= request_toggle_meta_eom;
            armed_seen_toggle_meta_eom <= armed_seen_toggle_tx;
            armed_seen_toggle_sync_eom <= armed_seen_toggle_meta_eom;
            geometry_start_eom         <= 1'b0;
            task_zero_pulse_eom        <= 1'b0;

            if (alignment_valid_eom) begin
                if (boundary_phase_eom == boundary_terminal_eom)
                    boundary_phase_eom <= 5'd0;
                else
                    boundary_phase_eom <= boundary_phase_eom + 1'b1;
            end

            case (eom_state)
                E_IDLE: begin
                    eom_window <= 1'b0;
                    eom_active <= 1'b0;
                    eom_armed  <= 1'b0;
                    if (request_toggle_sync_eom != request_seen_eom) begin
                        request_seen_eom           <= request_toggle_sync_eom;
                        eom_enable_local           <= snapshot_eom_enable_tx;
                        global_pattern_index_local <=
                            snapshot_global_pattern_index_tx;
                        lead_ticks_local           <= snapshot_lead_ticks_tx;
                        trail_ticks_local          <= snapshot_trail_ticks_tx;
                        repeat_cycles_local        <= snapshot_repeat_cycles_tx;
                        pattern_len_local          <= snapshot_pattern_len_tx;
                        phase_shift_en_local       <=
                            snapshot_phase_shift_en_tx;
                        head_delay_bits_local      <=
                            snapshot_head_delay_bits_tx;
                        gap_len_bits_local         <= snapshot_gap_len_bits_tx;
                        eom_subdiv_log2_local      <=
                            snapshot_eom_subdiv_log2_tx;
                        geometry_valid_eom         <= 1'b0;
                        request_valid_hold_eom     <= 1'b0;
                        eom_fired                  <= 1'b0;
                        alignment_valid_eom        <= 1'b1;
                        boundary_phase_eom         <=
                            snapshot_boundary_seed_eom;
                        geometry_start_eom         <= 1'b1;
                        eom_state                  <= E_WAIT_GEOMETRY_LOW;
                    end
                end

                E_WAIT_GEOMETRY_LOW: begin
                    // ready is a held level. Consume only the new low-to-high
                    // completion after this transaction's start pulse.
                    if (!geometry_ready_eom)
                        eom_state <= E_WAIT_GEOMETRY;
                end

                E_WAIT_GEOMETRY: begin
                    if (geometry_ready_eom) begin
                        start_tick_local_eom   <= geometry_start_tick_eom;
                        end_tick_local_eom     <= geometry_end_tick_eom;
                        selected_phase_eom     <= geometry_selected_phase_eom;
                        selected_repeat_eom    <= geometry_selected_repeat_eom;
                        request_valid_hold_eom <= geometry_request_valid_eom;
                        geometry_valid_eom     <= 1'b1;
                        eom_armed              <= 1'b1;
                        ack_toggle_eom         <= ~ack_toggle_eom;
                        eom_state              <= E_WAIT_ACK_SEEN;
                    end
                end

                E_WAIT_ACK_SEEN: begin
                    if (armed_seen_toggle_sync_eom != armed_seen_eom) begin
                        armed_seen_eom <= armed_seen_toggle_sync_eom;
                        eom_state      <= E_WAIT_BOUNDARY;
                    end
                end

                E_WAIT_BOUNDARY: begin
                    if (tx_boundary_in_eom_domain) begin
                        // B0: raise the level after this common edge.
                        tx_start_level_request_eom <= 1'b1;
                        eom_state                  <= E_WAIT_TX_ARM;
                    end
                end

                E_WAIT_TX_ARM: begin
                    if (tx_boundary_in_eom_domain) begin
                        // B1: TX samples the level and arms its running state.
                        tx_start_level_request_eom <= 1'b0;
                        eom_state                  <= E_WAIT_TASK_ZERO;
                    end
                end

                E_WAIT_TASK_ZERO: begin
                    if (tx_boundary_in_eom_domain) begin
                        // B2 is the first TX word and EOM task tick zero.
                        task_zero_pulse_eom    <= 1'b1;
                        task_tick_counter_eom <= 24'd0;
                        eom_armed             <= 1'b0;
                        if (request_valid_hold_eom &&
                            (end_tick_local_eom > start_tick_local_eom)) begin
                            eom_active <= 1'b1;
                            eom_window <= (start_tick_local_eom == 24'd0);
                            eom_state  <= E_ACTIVE;
                        end else begin
                            eom_active <= 1'b0;
                            eom_window <= 1'b0;
                            eom_state  <= E_IDLE;
                        end
                    end
                end

                E_ACTIVE: begin
                    if (task_tick_counter_eom + 1'b1 >=
                        end_tick_local_eom) begin
                        task_tick_counter_eom <=
                            task_tick_counter_eom + 1'b1;
                        eom_window  <= 1'b0;
                        eom_active  <= 1'b0;
                        eom_fired   <= 1'b1;
                        done_toggle <= ~done_toggle;
                        eom_state   <= E_IDLE;
                    end else begin
                        task_tick_counter_eom <=
                            task_tick_counter_eom + 1'b1;
                        eom_window <=
                            (task_tick_counter_eom + 1'b1 >=
                             start_tick_local_eom);
                    end
                end

                default: begin
                    eom_window <= 1'b0;
                    eom_active <= 1'b0;
                    eom_armed  <= 1'b0;
                    eom_state  <= E_IDLE;
                end
            endcase
        end
    end
endmodule

`timescale 1ns/1ps

module laser_tx_core #(
    parameter integer CURRENT_STATIC_RATE_MBPS = 1000
) (
    input  wire        axi_clk,
    input  wire        axi_rstn,
    input  wire        txusrclk2,
    input  wire        eom_clk,
    input  wire [2:0]  eom_subdiv_log2,
    input  wire        eom_clock_safe,
    input  wire        tx_rst,
    // Asserted only after the GT user clock/PLL/reset sequence is stable.
    // This signal is already synchronous to txusrclk2 at the board wrapper.
    input  wire        gt_ready,
    input  wire [31:0] gpio_ctrl,
    // Rate executors assert this level while TX must be quiescent. It only
    // gates the effective enable; the PS-owned GPIO value is not modified.
    input  wire        rate_apply_enable_blocked,
    output wire [31:0] gpio_status,

    // Native read-only BRAM master interface. Vivado groups these scalar ports
    // as BRAM_PORTB so the module can connect directly to blk_mem_gen Port B.
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME BRAM_PORTB, MASTER_TYPE BRAM_CTRL, MEM_ECC NONE, MEM_SIZE 8192, MEM_WIDTH 32, READ_LATENCY 1" *)
    output wire        bram_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB RST" *)
    output wire        bram_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *)
    output wire        bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB WE" *)
    output wire [3:0]  bram_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *)
    output wire [31:0] bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB DIN" *)
    output wire [31:0] bram_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *)
    input  wire [31:0] bram_dout,

    output wire [63:0] txdata,
    output wire [63:0] valid_mask,
    output wire        eom_out,
    output wire        soa_gate_out,
    output wire        acq_trig_out,
    output wire        acq_gate_out,
    output wire        gt_sequence_sync_out,
    output wire        txusrclk2_monitor_out,
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *)
    output wire [9:0]  dbg_gpio9_tx_bus,

    // Debug-only mirrors. Native BRAM interface members are hidden inside a
    // bundled BD pin, so these mirrors make the read transaction observable
    // by an AXI-clocked ILA without changing the BRAM or data-path behavior.
    output wire        dbg_bram_en,
    output wire [31:0] dbg_bram_addr,
    output wire [31:0] dbg_bram_dout,
    output wire        dbg_bram_rst,

    // Raw txusrclk2-domain status for the TX ILA. Do not use gpio_status for
    // cycle-accurate TX observation because gpio_status belongs to axi_clk.
    output wire        dbg_busy_tx,
    output wire        dbg_done_tx,
    output wire        dbg_phase_active_tx,
    output wire        dbg_phase_start_pulse_tx,
    output wire [7:0]  dbg_phase_offset_tx,
    output wire [7:0]  dbg_current_state_tx,
    output wire        dbg_cfg_update_pulse_tx,
    output wire        dbg_pattern_valid_tx,
    output wire        dbg_engine_start_tx,
    output wire        dbg_gt_ready_tx
);
    // Port B is deliberately read-only. The BRAM clock/reset are tied to the
    // AXI domain because config_loader and the PS write path share that domain.
    assign bram_clk = axi_clk;
    assign bram_rst = ~axi_rstn;
    assign bram_we  = 4'b0000;
    assign bram_din = 32'd0;
    assign dbg_bram_en   = bram_en;
    assign dbg_bram_addr = bram_addr;
    assign dbg_bram_dout = bram_dout;
    assign dbg_bram_rst  = bram_rst;

    // Stable AXI-domain active configuration.
    wire cfg_valid_axi;
    wire cfg_error_axi;
    wire [7:0] error_code_axi;
    wire cfg_update_toggle_axi;
    wire [4:0] repeat_cycles_axi;
    wire [7:0] head_delay_bits_axi;
    wire [119:0] gap_len_bits_axi;
    wire eom_enable_axi;
    wire [10:0] eom_global_pattern_index_axi;
    wire [15:0] eom_lead_ticks_axi;
    wire [15:0] eom_trail_ticks_axi;
    wire phase_shift_en_axi;
    wire loop_en_axi;
    wire [7:0] pattern_len_axi;
    wire [126:0] configured_pattern_axi;

    config_loader u_config_loader (
        .clk(axi_clk), .rstn(axi_rstn),
        .config_index(gpio_ctrl[7:0]), .apply_toggle(gpio_ctrl[8]),
        .bram_en(bram_en), .bram_addr(bram_addr), .bram_dout(bram_dout),
        .cfg_valid(cfg_valid_axi), .cfg_error(cfg_error_axi),
        .error_code(error_code_axi), .cfg_update_toggle(cfg_update_toggle_axi),
        .repeat_cycles(repeat_cycles_axi),
        .head_delay_bits(head_delay_bits_axi),
        .gap_len_bits(gap_len_bits_axi),
        .eom_enable(eom_enable_axi),
        .eom_global_pattern_index(eom_global_pattern_index_axi),
        .eom_lead_ticks(eom_lead_ticks_axi),
        .eom_trail_ticks(eom_trail_ticks_axi),
        .phase_shift_en(phase_shift_en_axi),
        .loop_en(loop_en_axi), .pattern_len(pattern_len_axi),
        .configured_pattern(configured_pattern_axi)
    );

    // AXI-domain bring-up debug mirrors. These are debug-only internal nets
    // used by the static-1000M AXI-clocked ILA. They do not feed back into
    // control logic and therefore do not change software-visible behavior.
    (* mark_debug = "true" *) wire [31:0] dbg_axi_gpio_ctrl      = gpio_ctrl;
    (* mark_debug = "true" *) wire        dbg_axi_apply_toggle   = gpio_ctrl[8];
    (* mark_debug = "true" *) wire        dbg_axi_enable         = gpio_ctrl[9];
    (* mark_debug = "true" *) wire        dbg_axi_soft_reset     = gpio_ctrl[10];
    (* mark_debug = "true" *) wire        dbg_axi_cfg_valid      = cfg_valid_axi;
    (* mark_debug = "true" *) wire        dbg_axi_cfg_error      = cfg_error_axi;
    (* mark_debug = "true" *) reg         dbg_axi_cfg_update_seen;
    reg cfg_update_toggle_axi_d;
    always @(posedge axi_clk) begin
        if (!axi_rstn) begin
            cfg_update_toggle_axi_d   <= 1'b0;
            dbg_axi_cfg_update_seen   <= 1'b0;
        end else begin
            cfg_update_toggle_axi_d <= cfg_update_toggle_axi;
            if (cfg_update_toggle_axi ^ cfg_update_toggle_axi_d) begin
                dbg_axi_cfg_update_seen <= 1'b1;
            end
        end
    end

    wire cfg_update_pulse_tx;
    cdc_toggle_sync u_cfg_toggle_sync (
        .dst_clk(txusrclk2), .dst_rst(tx_rst),
        .src_toggle(cfg_update_toggle_axi),
        .dst_pulse(cfg_update_pulse_tx), .dst_toggle()
    );

    // Synchronize each independent AXI/control level before combining it in
    // the TX domain. This prevents combinational control logic from sitting
    // in front of a synchronizer and keeps the effective enable TX-local.
    (* ASYNC_REG = "TRUE" *) reg enable_gpio_meta, enable_gpio_tx;
    (* ASYNC_REG = "TRUE" *) reg soft_reset_meta, soft_reset_tx;
    (* ASYNC_REG = "TRUE" *) reg rate_block_meta, rate_block_tx;
    (* ASYNC_REG = "TRUE" *) reg eom_clock_safe_meta, eom_clock_safe_tx;
    (* ASYNC_REG = "TRUE" *) reg cfg_valid_meta_tx, cfg_valid_sync_tx;
    (* ASYNC_REG = "TRUE" *) reg [2:0] eom_subdiv_meta_tx;
    (* ASYNC_REG = "TRUE" *) reg [2:0] eom_subdiv_sync_tx;
    reg eom_operating_safe_tx;
    wire enable_tx =
        enable_gpio_tx & gt_ready & eom_clock_safe_tx & ~rate_block_tx;
    always @(posedge txusrclk2) begin
        if (tx_rst) begin
            enable_gpio_meta <= 1'b0;
            enable_gpio_tx <= 1'b0;
            soft_reset_meta <= 1'b0;
            soft_reset_tx <= 1'b0;
            rate_block_meta <= 1'b1;
            rate_block_tx <= 1'b1;
            eom_clock_safe_meta <= 1'b0;
            eom_clock_safe_tx <= 1'b0;
            cfg_valid_meta_tx <= 1'b0;
            cfg_valid_sync_tx <= 1'b0;
            eom_subdiv_meta_tx <= 3'd0;
            eom_subdiv_sync_tx <= 3'd0;
            eom_operating_safe_tx <= 1'b0;
        end else begin
            enable_gpio_meta <= gpio_ctrl[9];
            enable_gpio_tx <= enable_gpio_meta;
            soft_reset_meta <= gpio_ctrl[10];
            soft_reset_tx <= soft_reset_meta;
            rate_block_meta <= rate_apply_enable_blocked;
            rate_block_tx <= rate_block_meta;
            eom_clock_safe_meta <= eom_clock_safe;
            eom_clock_safe_tx <= eom_clock_safe_meta;
            cfg_valid_meta_tx <= cfg_valid_axi;
            cfg_valid_sync_tx <= cfg_valid_meta_tx;
            eom_subdiv_meta_tx <= eom_subdiv_log2;
            eom_subdiv_sync_tx <= eom_subdiv_meta_tx;
            eom_operating_safe_tx <=
                eom_clock_safe_tx & gt_ready & enable_gpio_tx &
                ~soft_reset_tx & ~rate_block_tx;
        end
    end

    // Multi-bit CDC: source bundle remains unchanged from one apply event until
    // the next. Capture it only after the synchronized update toggle arrives.
    reg cfg_valid_tx;
    reg [4:0] repeat_cycles_tx;
    reg [7:0] head_delay_bits_tx;
    reg [119:0] gap_len_bits_tx;
    reg eom_enable_tx;
    reg [10:0] eom_global_pattern_index_tx;
    reg [15:0] eom_lead_ticks_tx;
    reg [15:0] eom_trail_ticks_tx;
    reg phase_shift_en_tx;
    reg loop_en_tx;
    reg [7:0] pattern_len_tx;
    reg [126:0] configured_pattern_tx;
    reg pending_start;
    reg engine_start;
    reg engine_start_toggle_tx;

    always @(posedge txusrclk2) begin
        if (tx_rst) begin
            cfg_valid_tx <= 1'b0;
            repeat_cycles_tx <= 5'b0;
            head_delay_bits_tx <= 8'b0;
            gap_len_bits_tx <= 120'b0;
            eom_enable_tx <= 1'b0;
            eom_global_pattern_index_tx <= 11'b0;
            eom_lead_ticks_tx <= 16'b0;
            eom_trail_ticks_tx <= 16'b0;
            phase_shift_en_tx <= 1'b0;
            loop_en_tx <= 1'b0;
            pattern_len_tx <= 8'b0;
            configured_pattern_tx <= 127'b0;
            pending_start <= 1'b0;
            engine_start <= 1'b0;
            engine_start_toggle_tx <= 1'b0;
        end else if (soft_reset_tx || !eom_clock_safe) begin
            pending_start <= cfg_valid_tx;
            engine_start <= 1'b0;
        end else begin
            engine_start <= 1'b0;
            if (cfg_update_pulse_tx) begin
                cfg_valid_tx <= cfg_valid_sync_tx;
                repeat_cycles_tx <= repeat_cycles_axi;
                head_delay_bits_tx <= head_delay_bits_axi;
                gap_len_bits_tx <= gap_len_bits_axi;
                eom_enable_tx <= eom_enable_axi;
                eom_global_pattern_index_tx <= eom_global_pattern_index_axi;
                eom_lead_ticks_tx <= eom_lead_ticks_axi;
                eom_trail_ticks_tx <= eom_trail_ticks_axi;
                phase_shift_en_tx <= phase_shift_en_axi;
                loop_en_tx <= loop_en_axi;
                pattern_len_tx <= pattern_len_axi;
                configured_pattern_tx <= configured_pattern_axi;
                pending_start <= cfg_valid_sync_tx;
            end else if (!enable_tx) begin
                pending_start <= cfg_valid_tx;
            end else if (pending_start) begin
                engine_start <= 1'b1;
                engine_start_toggle_tx <= ~engine_start_toggle_tx;
                pending_start <= 1'b0;
            end
        end
    end

    wire dbg_axi_engine_start_pulse;
    wire dbg_axi_engine_start_toggle;
    (* mark_debug = "true" *) reg dbg_axi_engine_start_seen;
    cdc_toggle_sync u_engine_start_seen_sync (
        .dst_clk(axi_clk),
        .dst_rst(~axi_rstn),
        .src_toggle(engine_start_toggle_tx),
        .dst_pulse(dbg_axi_engine_start_pulse),
        .dst_toggle(dbg_axi_engine_start_toggle)
    );
    always @(posedge axi_clk) begin
        if (!axi_rstn) begin
            dbg_axi_engine_start_seen <= 1'b0;
        end else if (dbg_axi_engine_start_pulse) begin
            dbg_axi_engine_start_seen <= 1'b1;
        end
    end

    // The BRAM-configured 63/127-bit cyclic pattern is the only TX pattern
    // source. config_loader publishes a stable AXI-domain active bundle and
    // this TX-domain register captures it only on cfg_update_pulse_tx.
    // pattern_tx_engine takes its own task snapshot when start is accepted.
    wire [126:0] base_pattern = configured_pattern_tx;
    wire pattern_valid_tx =
        cfg_valid_tx &&
        ((pattern_len_tx == 8'd63) || (pattern_len_tx == 8'd127));

    wire phase_active_tx;
    wire phase_start_pulse_tx;
    wire sequence_active_tx;
    wire busy_tx;
    wire done_tx;
    wire [7:0] phase_offset_tx;
    wire [7:0] current_state_tx;
    wire engine_start_accept_pulse_tx;
    (* mark_debug = "true" *) wire first_sequence_word_fire_tx;
    wire eom_geometry_armed_tx;
    wire eom_tx_start_level;
    wire eom_request_valid_tx;
    wire eom_request_busy_tx;
    wire eom_active_raw;
    wire eom_fired_raw;
    wire eom_done_toggle_raw;
    wire eom_done_pulse_tx;
    wire eom_done_toggle_tx;
    wire eom_geometry_valid_raw;
    wire eom_armed_raw;
    wire eom_alignment_valid_raw;
    wire eom_task_zero_pulse_raw;
    wire [23:0] eom_task_tick_counter_raw;
    wire [23:0] eom_start_tick_local_raw;
    wire [23:0] eom_end_tick_local_raw;
    wire [7:0] eom_selected_phase_raw;
    wire [3:0] eom_selected_repeat_raw;

    // A TX-side abort invalidates any unfinished snapshot transaction.  The
    // physical EOM output has a stronger asynchronous-safe gate so rate
    // quiesce, MMCM/clock loss, GT unsafe state, disable, reset, or soft reset
    // cannot leave the output high while eom_clk is stopped.
    wire eom_task_abort_tx =
        tx_rst | soft_reset_tx | ~enable_tx | ~gt_ready |
        rate_block_tx | ~eom_clock_safe_tx;
    wire tx_sequence_reset =
        tx_rst | soft_reset_tx | ~eom_clock_safe_tx;
    wire eom_operating_safe_async =
        eom_clock_safe & gt_ready & gpio_ctrl[9] & ~gpio_ctrl[10] &
        ~rate_apply_enable_blocked & ~tx_rst;

    // The controller captures one stable TX-domain task snapshot, calculates
    // all geometry in eom_clk, acknowledges ARMED back to TX, then uses the
    // related zero-phase MMCM clocks to choose one deterministic common word
    // boundary. No TX-domain start/end tick enters the EOM live comparator.
    tx_eom_window_generator u_tx_eom_window_generator (
        .tx_clk(txusrclk2), .tx_abort(eom_task_abort_tx),
        .task_request_pulse_tx(engine_start_accept_pulse_tx),
        .eom_enable_tx(eom_enable_tx),
        .global_pattern_index_tx(eom_global_pattern_index_tx),
        .lead_ticks_tx(eom_lead_ticks_tx),
        .trail_ticks_tx(eom_trail_ticks_tx),
        .repeat_cycles_tx(repeat_cycles_tx),
        .pattern_len_tx(pattern_len_tx),
        .phase_shift_en_tx(phase_shift_en_tx),
        .head_delay_bits_tx(head_delay_bits_tx),
        .gap_len_bits_tx(gap_len_bits_tx),
        .eom_subdiv_log2_tx(eom_subdiv_sync_tx),
        .eom_clk(eom_clk),
        .clock_safe(eom_operating_safe_tx),
        .async_output_safe(eom_operating_safe_async),
        .geometry_armed_tx(eom_geometry_armed_tx),
        .tx_start_level(eom_tx_start_level),
        .request_valid_tx(eom_request_valid_tx),
        .request_busy_tx(eom_request_busy_tx),
        .eom_out(eom_out), .soa_gate_out(soa_gate_out),
        .eom_active(eom_active_raw),
        .eom_fired(eom_fired_raw), .done_toggle(eom_done_toggle_raw),
        .geometry_valid_eom(eom_geometry_valid_raw),
        .eom_armed(eom_armed_raw),
        .alignment_valid_eom(eom_alignment_valid_raw),
        .task_zero_pulse_eom(eom_task_zero_pulse_raw),
        .task_tick_counter_eom(eom_task_tick_counter_raw),
        .start_tick_local_eom(eom_start_tick_local_raw),
        .end_tick_local_eom(eom_end_tick_local_raw),
        .selected_phase_eom(eom_selected_phase_raw),
        .selected_repeat_eom(eom_selected_repeat_raw)
    );

    cdc_toggle_sync u_eom_done_sync (
        .dst_clk(txusrclk2), .dst_rst(eom_task_abort_tx),
        .src_toggle(eom_done_toggle_raw),
        .dst_pulse(eom_done_pulse_tx), .dst_toggle(eom_done_toggle_tx)
    );

    pattern_tx_engine u_pattern_tx_engine (
        .clk(txusrclk2), .rst(tx_sequence_reset),
        .start(engine_start), .enable(enable_tx),
        .pattern_valid(pattern_valid_tx), .base_pattern(base_pattern),
        .pattern_len(pattern_len_tx), .repeat_cycles(repeat_cycles_tx),
        .head_delay_bits(head_delay_bits_tx), .gap_len_bits(gap_len_bits_tx),
        .phase_shift_en(phase_shift_en_tx), .loop_en(loop_en_tx),
        .eom_geometry_armed(eom_geometry_armed_tx),
        .eom_tx_start_level(eom_tx_start_level),
        .eom_request_valid(eom_request_valid_tx),
        .eom_done_pulse(eom_done_pulse_tx),
        .engine_start_accept_pulse(engine_start_accept_pulse_tx),
        .first_sequence_word_fire(first_sequence_word_fire_tx),
        .txdata(txdata), .valid_mask(valid_mask),
        .phase_active(phase_active_tx), .phase_start_pulse(phase_start_pulse_tx),
        .sequence_active(sequence_active_tx), .busy(busy_tx), .done(done_tx),
        .phase_offset(phase_offset_tx), .current_state(current_state_tx)
    );

    // Scope-only observability. The raw event is already registered on the
    // same TXUSRCLK2 edge as txdata/valid_mask. The widened GPIO pulse retains
    // that rising edge and is forced low on reset, disable, abort, or GT clock
    // safety loss. The monitor ODDR is not gated by sequence enable so it can
    // show the real working TXUSRCLK2 whenever the GT clock path is ready.
    (* MARK_DEBUG = "TRUE", KEEP = "TRUE" *)
    wire scope_sync_reset_tx =
        tx_rst | soft_reset_tx | ~enable_tx | ~gt_ready |
        rate_block_tx | ~eom_clock_safe_tx;

    // GPIO9 monitor diagnosis, sampled by the existing TXUSRCLK2-domain ILA.
    // Every member is the exact TX-domain signal used by the ODDR reset path;
    // this bus is observation-only and has no functional fanout.
    assign dbg_gpio9_tx_bus = {
        enable_gpio_meta,      // [9]
        eom_clock_safe_meta,   // [8]
        scope_sync_reset_tx,   // [7]
        enable_tx,             // [6]
        eom_clock_safe_tx,     // [5]
        rate_block_tx,         // [4]
        gt_ready,              // [3]
        enable_gpio_tx,        // [2]
        soft_reset_tx,         // [1]
        tx_rst                 // [0]
    };

    tx_scope_debug_outputs #(
        .SYNC_WIDTH_CYCLES(16)
    ) u_tx_scope_debug_outputs (
        .txusrclk2(txusrclk2),
        .reset_tx(scope_sync_reset_tx),
        .sequence_word_fire(first_sequence_word_fire_tx),
        .gt_sequence_sync_out(gt_sequence_sync_out),
        .txusrclk2_monitor_out(txusrclk2_monitor_out)
    );
    sync_signal_gen u_sync_signal_gen (
        .clk(txusrclk2), .rst(tx_sequence_reset),
        .phase_active(phase_active_tx),
        .phase_start_pulse(phase_start_pulse_tx),
        .acq_trig_out(acq_trig_out), .acq_gate_out(acq_gate_out)
    );

    assign dbg_busy_tx              = busy_tx;
    assign dbg_done_tx              = done_tx;
    assign dbg_phase_active_tx      = phase_active_tx;
    assign dbg_phase_start_pulse_tx = phase_start_pulse_tx;
    assign dbg_phase_offset_tx      = phase_offset_tx;
    assign dbg_current_state_tx     = current_state_tx;
    assign dbg_cfg_update_pulse_tx  = cfg_update_pulse_tx;
    assign dbg_pattern_valid_tx     = pattern_valid_tx;
    assign dbg_engine_start_tx      = engine_start;
    assign dbg_gt_ready_tx          = gt_ready;

    // Register the complete diagnostic word in the TX domain before crossing
    // it. This removes combinational status packing from the synchronizer
    // inputs and gives each TX status source one local registered load.
    reg [23:0] status_snapshot_tx;
    (* ASYNC_REG = "TRUE" *) reg [23:0] status_meta_axi;
    (* ASYNC_REG = "TRUE" *) reg [23:0] status_sync_axi;
    wire [23:0] status_tx_bus = {
        current_state_tx, phase_offset_tx, 1'b0, sequence_active_tx,
        phase_active_tx, done_tx, busy_tx, pattern_valid_tx, 2'b0
    };
    always @(posedge txusrclk2) begin
        if (tx_rst)
            status_snapshot_tx <= 24'b0;
        else
            status_snapshot_tx <= status_tx_bus;
    end

    always @(posedge axi_clk) begin
        if (!axi_rstn) begin
            status_meta_axi <= 24'b0;
            status_sync_axi <= 24'b0;
        end else begin
            status_meta_axi <= status_snapshot_tx;
            status_sync_axi <= status_meta_axi;
        end
    end

    (* mark_debug = "true" *) wire dbg_axi_pattern_valid = status_sync_axi[2];
    (* mark_debug = "true" *) wire dbg_axi_busy_tx       = status_sync_axi[3];
    (* mark_debug = "true" *) wire dbg_axi_done_tx       = status_sync_axi[4];

    status_register u_status_register (
        .cfg_valid(cfg_valid_axi), .cfg_error(cfg_error_axi),
        .pattern_valid(status_sync_axi[2]), .busy(status_sync_axi[3]),
        .done(status_sync_axi[4]), .phase_active(status_sync_axi[5]),
        .sequence_active(status_sync_axi[6]),
        .phase_offset(status_sync_axi[15:8]),
        .current_state(status_sync_axi[23:16]),
        .error_code(error_code_axi), .gpio_status(gpio_status)
    );

endmodule

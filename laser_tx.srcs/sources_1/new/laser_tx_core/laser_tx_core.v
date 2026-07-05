`timescale 1ns/1ps

module laser_tx_core #(
    parameter integer CURRENT_STATIC_RATE_MBPS = 1000
) (
    input  wire        axi_clk,
    input  wire        axi_rstn,
    input  wire        txusrclk2,
    input  wire        tx_rst,
    // Asserted only after the GT user clock/PLL/reset sequence is stable.
    // This signal is already synchronous to txusrclk2 at the board wrapper.
    input  wire        gt_ready,
    input  wire [31:0] gpio_ctrl,
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
    wire [31:0] seed_axi;
    wire [31:0] repeat_cycles_axi;
    wire [7:0] gap_len_bits_axi;
    wire [15:0] insert_after_axi;
    wire [7:0] prbs_order_axi;
    wire phase_shift_en_axi;
    wire loop_en_axi;
    wire source_sel_axi;
    wire [7:0] pattern_len_axi;
    wire [126:0] direct_pattern_axi;

    config_loader u_config_loader (
        .clk(axi_clk), .rstn(axi_rstn),
        .config_index(gpio_ctrl[7:0]), .apply_toggle(gpio_ctrl[8]),
        .source_sel(gpio_ctrl[11]), .direct_len_sel(gpio_ctrl[12]),
        .bram_en(bram_en), .bram_addr(bram_addr), .bram_dout(bram_dout),
        .cfg_valid(cfg_valid_axi), .cfg_error(cfg_error_axi),
        .error_code(error_code_axi), .cfg_update_toggle(cfg_update_toggle_axi),
        .seed(seed_axi), .repeat_cycles(repeat_cycles_axi),
        .gap_len_bits(gap_len_bits_axi), .insert_after(insert_after_axi),
        .prbs_order(prbs_order_axi), .phase_shift_en(phase_shift_en_axi),
        .loop_en(loop_en_axi), .active_source_sel(source_sel_axi),
        .pattern_len(pattern_len_axi), .direct_pattern(direct_pattern_axi)
    );

    // AXI-domain bring-up debug mirrors. These are debug-only internal nets
    // used by the static-1000M AXI-clocked ILA. They do not feed back into
    // control logic and therefore do not change software-visible behavior.
    (* mark_debug = "true" *) wire [31:0] dbg_axi_gpio_ctrl      = gpio_ctrl;
    (* mark_debug = "true" *) wire        dbg_axi_apply_toggle   = gpio_ctrl[8];
    (* mark_debug = "true" *) wire        dbg_axi_enable         = gpio_ctrl[9];
    (* mark_debug = "true" *) wire        dbg_axi_soft_reset     = gpio_ctrl[10];
    (* mark_debug = "true" *) wire        dbg_axi_rate_req_toggle = gpio_ctrl[17];
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
    wire cfg_update_toggle_tx;
    cdc_toggle_sync u_cfg_toggle_sync (
        .dst_clk(txusrclk2), .dst_rst(tx_rst),
        .src_toggle(cfg_update_toggle_axi),
        .dst_pulse(cfg_update_pulse_tx), .dst_toggle(cfg_update_toggle_tx)
    );

    // GPIO levels use two-flop synchronizers. Configuration selection bits are
    // captured by config_loader and cross only as part of the stable bundle.
    (* ASYNC_REG = "TRUE" *) reg enable_meta, enable_tx;
    (* ASYNC_REG = "TRUE" *) reg soft_reset_meta, soft_reset_tx;
    always @(posedge txusrclk2) begin
        if (tx_rst) begin
            enable_meta <= 1'b0;
            enable_tx <= 1'b0;
            soft_reset_meta <= 1'b0;
            soft_reset_tx <= 1'b0;
        end else begin
            enable_meta <= gpio_ctrl[9] & gt_ready;
            enable_tx <= enable_meta;
            soft_reset_meta <= gpio_ctrl[10];
            soft_reset_tx <= soft_reset_meta;
        end
    end

    // Multi-bit CDC: source bundle remains unchanged from one apply event until
    // the next. Capture it only after the synchronized update toggle arrives.
    reg cfg_valid_tx;
    reg [31:0] seed_tx;
    reg [31:0] repeat_cycles_tx;
    reg [7:0] gap_len_bits_tx;
    reg [15:0] insert_after_tx;
    reg [7:0] prbs_order_tx;
    reg phase_shift_en_tx;
    reg loop_en_tx;
    reg source_sel_tx;
    reg [7:0] pattern_len_tx;
    reg [126:0] direct_pattern_tx;
    reg pending_start;
    reg engine_start;
    reg engine_start_toggle_tx;

    always @(posedge txusrclk2) begin
        if (tx_rst) begin
            cfg_valid_tx <= 1'b0;
            seed_tx <= 32'b0;
            repeat_cycles_tx <= 32'b0;
            gap_len_bits_tx <= 8'b0;
            insert_after_tx <= 16'b0;
            prbs_order_tx <= 8'b0;
            phase_shift_en_tx <= 1'b0;
            loop_en_tx <= 1'b0;
            source_sel_tx <= 1'b0;
            pattern_len_tx <= 8'b0;
            direct_pattern_tx <= 127'b0;
            pending_start <= 1'b0;
            engine_start <= 1'b0;
            engine_start_toggle_tx <= 1'b0;
        end else if (soft_reset_tx) begin
            pending_start <= cfg_valid_tx;
            engine_start <= 1'b0;
        end else begin
            engine_start <= 1'b0;
            if (cfg_update_pulse_tx) begin
                cfg_valid_tx <= cfg_valid_axi;
                seed_tx <= seed_axi;
                repeat_cycles_tx <= repeat_cycles_axi;
                gap_len_bits_tx <= gap_len_bits_axi;
                insert_after_tx <= insert_after_axi;
                prbs_order_tx <= prbs_order_axi;
                phase_shift_en_tx <= phase_shift_en_axi;
                loop_en_tx <= loop_en_axi;
                source_sel_tx <= source_sel_axi;
                pattern_len_tx <= pattern_len_axi;
                direct_pattern_tx <= direct_pattern_axi;
                pending_start <= cfg_valid_axi;
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

    wire [126:0] base_pattern;
    wire pattern_valid_tx;
    pattern_source u_pattern_source (
        .cfg_valid(cfg_valid_tx), .source_sel(source_sel_tx),
        .prbs_order(prbs_order_tx), .pattern_len(pattern_len_tx),
        .seed(seed_tx), .pattern_in(direct_pattern_tx),
        .base_pattern(base_pattern), .pattern_valid(pattern_valid_tx)
    );

    wire phase_active_tx;
    wire phase_start_pulse_tx;
    wire sequence_active_tx;
    wire busy_tx;
    wire done_tx;
    wire [7:0] phase_offset_tx;
    wire [7:0] current_state_tx;
    pattern_tx_engine u_pattern_tx_engine (
        .clk(txusrclk2), .rst(tx_rst | soft_reset_tx),
        .start(engine_start), .enable(enable_tx),
        .pattern_valid(pattern_valid_tx), .base_pattern(base_pattern),
        .pattern_len(pattern_len_tx), .repeat_cycles(repeat_cycles_tx),
        .insert_after(insert_after_tx), .gap_len_bits(gap_len_bits_tx),
        .phase_shift_en(phase_shift_en_tx), .loop_en(loop_en_tx),
        .txdata(txdata), .valid_mask(valid_mask),
        .phase_active(phase_active_tx), .phase_start_pulse(phase_start_pulse_tx),
        .sequence_active(sequence_active_tx), .busy(busy_tx), .done(done_tx),
        .phase_offset(phase_offset_tx), .current_state(current_state_tx)
    );

    sync_signal_gen u_sync_signal_gen (
        .clk(txusrclk2), .rst(tx_rst | soft_reset_tx),
        .valid_mask(valid_mask), .phase_active(phase_active_tx),
        .phase_start_pulse(phase_start_pulse_tx),
        .eom_out(eom_out), .soa_gate_out(soa_gate_out),
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

    // Synchronize diagnostic status back to the AXI clock domain. These fields
    // are observability data; bit-to-bit atomicity is not required by control.
    reg [23:0] status_meta_axi;
    reg [23:0] status_sync_axi;
    wire [23:0] status_tx_bus = {
        current_state_tx, phase_offset_tx, 1'b0, sequence_active_tx,
        phase_active_tx, done_tx, busy_tx, pattern_valid_tx, 2'b0
    };
    always @(posedge axi_clk) begin
        if (!axi_rstn) begin
            status_meta_axi <= 24'b0;
            status_sync_axi <= 24'b0;
        end else begin
            status_meta_axi <= status_tx_bus;
            status_sync_axi <= status_meta_axi;
        end
    end

    (* mark_debug = "true" *) wire dbg_axi_pattern_valid = status_sync_axi[2];
    (* mark_debug = "true" *) wire dbg_axi_busy_tx       = status_sync_axi[3];
    (* mark_debug = "true" *) wire dbg_axi_done_tx       = status_sync_axi[4];

    // Phase-A dry-run rate controller. This AXI-clocked FSM intentionally does
    // not drive GTX/MMCM DRP and does not modify any TX clocking. It only makes
    // rate command/status flow observable before the real DRP phase.
    localparam [7:0] RATE_IDLE                 = 8'h00;
    localparam [7:0] RATE_REQUEST              = 8'h01;
    localparam [7:0] RATE_VALIDATE             = 8'h02;
    localparam [7:0] RATE_QUIESCE_TX           = 8'h03;
    localparam [7:0] RATE_DRYRUN_SKIP_GT_DRP   = 8'h04;
    localparam [7:0] RATE_DRYRUN_SKIP_MMCM_DRP = 8'h05;
    localparam [7:0] RATE_VERIFY_STATIC_STATUS = 8'h06;
    localparam [7:0] RATE_DONE                 = 8'h07;
    localparam [7:0] RATE_ERROR                = 8'h80;

    localparam [7:0] RATE_ERR_NONE             = 8'h00;
    localparam [7:0] RATE_ERR_UNSUPPORTED      = 8'h01;
    localparam [7:0] RATE_ERR_TX_QUIESCE_TO    = 8'h02;
    localparam [7:0] RATE_ERR_GT_NOT_READY     = 8'h03;

    localparam [3:0] RATE_ID_NONE              = 4'd0;
    localparam [3:0] RATE_ID_500M              = 4'd1;
    localparam [3:0] RATE_ID_1000M             = 4'd2;
    localparam [3:0] RATE_ID_2000M             = 4'd3;
    localparam [3:0] RATE_ID_1250M             = 4'd4;
    localparam [3:0] RATE_ID_2500M             = 4'd5;
    localparam [3:0] RATE_ID_5000M             = 4'd6;

    localparam [15:0] CURRENT_STATIC_RATE_MHZ =
        (CURRENT_STATIC_RATE_MBPS == 500) ? 16'd500 : 16'd1000;

    (* mark_debug = "true" *) reg [7:0]  dbg_axi_rate_state;
    (* mark_debug = "true" *) reg [3:0]  dbg_axi_target_rate_id;
    (* mark_debug = "true" *) reg [15:0] dbg_axi_target_rate_mbps;
    (* mark_debug = "true" *) reg [15:0] dbg_axi_current_rate_mbps;
    (* mark_debug = "true" *) reg        dbg_axi_dry_run_active;
    (* mark_debug = "true" *) reg        dbg_axi_dry_run_done;
    (* mark_debug = "true" *) reg        dbg_axi_rate_error;
    (* mark_debug = "true" *) reg [7:0]  dbg_axi_rate_error_code;
    (* mark_debug = "true" *) wire       dbg_axi_gt_drp_write_attempted   = 1'b0;
    (* mark_debug = "true" *) wire       dbg_axi_mmcm_drp_write_attempted = 1'b0;
    (* mark_debug = "true" *) reg        dbg_axi_tx_quiesce_req;
    (* mark_debug = "true" *) reg        dbg_axi_tx_idle_seen;

    reg rate_req_toggle_d_axi;
    reg [15:0] rate_quiesce_timeout_axi;
    wire rate_request_event_axi = dbg_axi_rate_req_toggle ^ rate_req_toggle_d_axi;
    wire [3:0] requested_rate_id_axi = gpio_ctrl[16:13];
    wire tx_idle_axi = !dbg_axi_busy_tx || dbg_axi_done_tx;

    always @(posedge axi_clk) begin
        if (!axi_rstn) begin
            rate_req_toggle_d_axi           <= 1'b0;
            rate_quiesce_timeout_axi        <= 16'd0;
            dbg_axi_rate_state              <= RATE_IDLE;
            dbg_axi_target_rate_id          <= RATE_ID_NONE;
            dbg_axi_target_rate_mbps        <= 16'd0;
            dbg_axi_current_rate_mbps       <= CURRENT_STATIC_RATE_MHZ;
            dbg_axi_dry_run_active          <= 1'b0;
            dbg_axi_dry_run_done            <= 1'b0;
            dbg_axi_rate_error              <= 1'b0;
            dbg_axi_rate_error_code         <= RATE_ERR_NONE;
            dbg_axi_tx_quiesce_req          <= 1'b0;
            dbg_axi_tx_idle_seen            <= 1'b0;
        end else begin
            rate_req_toggle_d_axi <= dbg_axi_rate_req_toggle;

            if (rate_request_event_axi) begin
                dbg_axi_rate_state        <= RATE_REQUEST;
                dbg_axi_target_rate_id    <= requested_rate_id_axi;
                dbg_axi_dry_run_active    <= 1'b1;
                dbg_axi_dry_run_done      <= 1'b0;
                dbg_axi_rate_error        <= 1'b0;
                dbg_axi_rate_error_code   <= RATE_ERR_NONE;
                dbg_axi_tx_quiesce_req    <= 1'b0;
                dbg_axi_tx_idle_seen      <= 1'b0;
                rate_quiesce_timeout_axi  <= 16'd0;
                case (requested_rate_id_axi)
                    RATE_ID_500M:  dbg_axi_target_rate_mbps <= 16'd500;
                    RATE_ID_1000M: dbg_axi_target_rate_mbps <= 16'd1000;
                    RATE_ID_2000M: dbg_axi_target_rate_mbps <= 16'd2000;
                    RATE_ID_1250M: dbg_axi_target_rate_mbps <= 16'd1250;
                    RATE_ID_2500M: dbg_axi_target_rate_mbps <= 16'd2500;
                    RATE_ID_5000M: dbg_axi_target_rate_mbps <= 16'd5000;
                    default:       dbg_axi_target_rate_mbps <= 16'd0;
                endcase
            end else begin
                case (dbg_axi_rate_state)
                    RATE_IDLE: begin
                        dbg_axi_dry_run_active <= 1'b0;
                        dbg_axi_tx_quiesce_req <= 1'b0;
                    end

                    RATE_REQUEST: begin
                        dbg_axi_rate_state <= RATE_VALIDATE;
                    end

                    RATE_VALIDATE: begin
                        if (dbg_axi_target_rate_id == RATE_ID_500M ||
                            dbg_axi_target_rate_id == RATE_ID_1000M ||
                            dbg_axi_target_rate_id == RATE_ID_2000M ||
                            dbg_axi_target_rate_id == RATE_ID_1250M ||
                            dbg_axi_target_rate_id == RATE_ID_2500M ||
                            dbg_axi_target_rate_id == RATE_ID_5000M) begin
                            dbg_axi_rate_state <= RATE_QUIESCE_TX;
                        end else begin
                            dbg_axi_rate_state      <= RATE_ERROR;
                            dbg_axi_rate_error      <= 1'b1;
                            dbg_axi_rate_error_code <= RATE_ERR_UNSUPPORTED;
                        end
                    end

                    RATE_QUIESCE_TX: begin
                        dbg_axi_tx_quiesce_req <= 1'b1;
                        if (tx_idle_axi) begin
                            dbg_axi_tx_idle_seen <= 1'b1;
                            dbg_axi_rate_state   <= RATE_DRYRUN_SKIP_GT_DRP;
                        end else if (rate_quiesce_timeout_axi == 16'hffff) begin
                            dbg_axi_rate_state      <= RATE_ERROR;
                            dbg_axi_rate_error      <= 1'b1;
                            dbg_axi_rate_error_code <= RATE_ERR_TX_QUIESCE_TO;
                        end else begin
                            rate_quiesce_timeout_axi <= rate_quiesce_timeout_axi + 1'b1;
                        end
                    end

                    RATE_DRYRUN_SKIP_GT_DRP: begin
                        dbg_axi_rate_state <= RATE_DRYRUN_SKIP_MMCM_DRP;
                    end

                    RATE_DRYRUN_SKIP_MMCM_DRP: begin
                        dbg_axi_rate_state <= RATE_VERIFY_STATIC_STATUS;
                    end

                    RATE_VERIFY_STATIC_STATUS: begin
                        if (gt_ready) begin
                            dbg_axi_rate_state <= RATE_DONE;
                        end else begin
                            dbg_axi_rate_state      <= RATE_ERROR;
                            dbg_axi_rate_error      <= 1'b1;
                            dbg_axi_rate_error_code <= RATE_ERR_GT_NOT_READY;
                        end
                    end

                    RATE_DONE: begin
                        dbg_axi_dry_run_active    <= 1'b0;
                        dbg_axi_dry_run_done      <= 1'b1;
                        dbg_axi_tx_quiesce_req    <= 1'b0;
                        dbg_axi_current_rate_mbps <= CURRENT_STATIC_RATE_MHZ;
                    end

                    RATE_ERROR: begin
                        dbg_axi_dry_run_active <= 1'b0;
                        dbg_axi_dry_run_done   <= 1'b0;
                        dbg_axi_tx_quiesce_req <= 1'b0;
                    end

                    default: begin
                        dbg_axi_rate_state      <= RATE_ERROR;
                        dbg_axi_rate_error      <= 1'b1;
                        dbg_axi_rate_error_code <= RATE_ERR_UNSUPPORTED;
                    end
                endcase
            end
        end
    end

    status_register u_status_register (
        .cfg_valid(cfg_valid_axi), .cfg_error(cfg_error_axi),
        .pattern_valid(status_sync_axi[2]), .busy(status_sync_axi[3]),
        .done(status_sync_axi[4]), .phase_active(status_sync_axi[5]),
        .sequence_active(status_sync_axi[6]),
        .phase_offset(status_sync_axi[15:8]),
        .current_state(status_sync_axi[23:16]),
        .error_code(error_code_axi), .gpio_status(gpio_status)
    );

    wire unused_cfg_toggle = cfg_update_toggle_tx;
endmodule

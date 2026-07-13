//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Tue Jul 14 00:25:32 2026
//Host        : LAPTOP-ITN6KOP9 running 64-bit major release  (build 9200)
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    SPI_1_0_io0_io,
    SPI_1_0_io1_io,
    SPI_1_0_sck_io,
    SPI_1_0_ss1_o,
    SPI_1_0_ss2_o,
    SPI_1_0_ss_io,
    acq_gate_out_0,
    acq_trig_out_0,
    ad9528_measure_count_in,
    ad9528_measure_status_in,
    dbg_apply_enable_blocked,
    dbg_current_rate_mbps,
    dbg_gt0_gttxreset_effective,
    dbg_gt0_txuserrdy_effective,
    dbg_gt_drp_addr,
    dbg_gt_drp_busy,
    dbg_gt_drp_di,
    dbg_gt_drp_do,
    dbg_gt_drp_done,
    dbg_gt_drp_en,
    dbg_gt_drp_error,
    dbg_gt_drp_rdy,
    dbg_gt_drp_readback_value,
    dbg_gt_drp_we,
    dbg_gt_drp_write_attempted,
    dbg_gt_ready,
    dbg_mmcm_drp_addr,
    dbg_mmcm_drp_busy,
    dbg_mmcm_drp_di,
    dbg_mmcm_drp_do,
    dbg_mmcm_drp_done,
    dbg_mmcm_drp_en,
    dbg_mmcm_drp_error,
    dbg_mmcm_drp_rdy,
    dbg_mmcm_drp_we,
    dbg_mmcm_drp_write_attempted,
    dbg_rate_error,
    dbg_rate_error_code,
    dbg_rate_gt_tx_reset,
    dbg_rate_state,
    dbg_rate_txuserrdy_block,
    dbg_target_rate_mbps,
    dbg_timeout_count,
    dbg_tx_idle_seen,
    dbg_tx_mmcm_locked_raw,
    dbg_tx_mmcm_locked_sync,
    dbg_tx_mmcm_reset,
    dbg_tx_mmcm_reset_rate,
    dbg_tx_mmcm_reset_wizard,
    dbg_tx_quiesce_req,
    dbg_txoutclk_alive_axi,
    dbg_txresetdone_sync,
    dbg_txusrclk2_alive_axi,
    dbg_txusrclk2_freq_counter_axi,
    dynamic_descriptor_bram_portb_addr,
    dynamic_descriptor_bram_portb_clk,
    dynamic_descriptor_bram_portb_din,
    dynamic_descriptor_bram_portb_dout,
    dynamic_descriptor_bram_portb_en,
    dynamic_descriptor_bram_portb_rst,
    dynamic_descriptor_bram_portb_we,
    dynamic_mailbox_control_out,
    dynamic_mailbox_status_in,
    eom_out_0,
    gpio_ctrl_to_gt,
    gpio_status_to_gt,
    gt_ctrl_clk,
    gt_ctrl_rst,
    gt_ready,
    gt_status_in,
    soa_gate_out_0,
    tx_rst,
    txdata,
    txusrclk2,
    valid_mask);
  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;
  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;
  inout SPI_1_0_io0_io;
  inout SPI_1_0_io1_io;
  inout SPI_1_0_sck_io;
  output SPI_1_0_ss1_o;
  output SPI_1_0_ss2_o;
  inout SPI_1_0_ss_io;
  output acq_gate_out_0;
  output acq_trig_out_0;
  input [31:0]ad9528_measure_count_in;
  input [31:0]ad9528_measure_status_in;
  input dbg_apply_enable_blocked;
  input [15:0]dbg_current_rate_mbps;
  input dbg_gt0_gttxreset_effective;
  input dbg_gt0_txuserrdy_effective;
  input [8:0]dbg_gt_drp_addr;
  input dbg_gt_drp_busy;
  input [15:0]dbg_gt_drp_di;
  input [15:0]dbg_gt_drp_do;
  input dbg_gt_drp_done;
  input dbg_gt_drp_en;
  input dbg_gt_drp_error;
  input dbg_gt_drp_rdy;
  input [15:0]dbg_gt_drp_readback_value;
  input dbg_gt_drp_we;
  input dbg_gt_drp_write_attempted;
  input dbg_gt_ready;
  input [6:0]dbg_mmcm_drp_addr;
  input dbg_mmcm_drp_busy;
  input [15:0]dbg_mmcm_drp_di;
  input [15:0]dbg_mmcm_drp_do;
  input dbg_mmcm_drp_done;
  input dbg_mmcm_drp_en;
  input dbg_mmcm_drp_error;
  input dbg_mmcm_drp_rdy;
  input dbg_mmcm_drp_we;
  input dbg_mmcm_drp_write_attempted;
  input dbg_rate_error;
  input [7:0]dbg_rate_error_code;
  input dbg_rate_gt_tx_reset;
  input [7:0]dbg_rate_state;
  input dbg_rate_txuserrdy_block;
  input [15:0]dbg_target_rate_mbps;
  input [31:0]dbg_timeout_count;
  input dbg_tx_idle_seen;
  input dbg_tx_mmcm_locked_raw;
  input dbg_tx_mmcm_locked_sync;
  input dbg_tx_mmcm_reset;
  input dbg_tx_mmcm_reset_rate;
  input dbg_tx_mmcm_reset_wizard;
  input dbg_tx_quiesce_req;
  input dbg_txoutclk_alive_axi;
  input dbg_txresetdone_sync;
  input dbg_txusrclk2_alive_axi;
  input [31:0]dbg_txusrclk2_freq_counter_axi;
  input [31:0]dynamic_descriptor_bram_portb_addr;
  input dynamic_descriptor_bram_portb_clk;
  input [31:0]dynamic_descriptor_bram_portb_din;
  output [31:0]dynamic_descriptor_bram_portb_dout;
  input dynamic_descriptor_bram_portb_en;
  input dynamic_descriptor_bram_portb_rst;
  input [3:0]dynamic_descriptor_bram_portb_we;
  output [3:0]dynamic_mailbox_control_out;
  input [31:0]dynamic_mailbox_status_in;
  output eom_out_0;
  output [31:0]gpio_ctrl_to_gt;
  output [31:0]gpio_status_to_gt;
  output gt_ctrl_clk;
  output [0:0]gt_ctrl_rst;
  input gt_ready;
  input [31:0]gt_status_in;
  output soa_gate_out_0;
  input tx_rst;
  output [63:0]txdata;
  input txusrclk2;
  output [63:0]valid_mask;

  wire [14:0]DDR_addr;
  wire [2:0]DDR_ba;
  wire DDR_cas_n;
  wire DDR_ck_n;
  wire DDR_ck_p;
  wire DDR_cke;
  wire DDR_cs_n;
  wire [3:0]DDR_dm;
  wire [31:0]DDR_dq;
  wire [3:0]DDR_dqs_n;
  wire [3:0]DDR_dqs_p;
  wire DDR_odt;
  wire DDR_ras_n;
  wire DDR_reset_n;
  wire DDR_we_n;
  wire FIXED_IO_ddr_vrn;
  wire FIXED_IO_ddr_vrp;
  wire [53:0]FIXED_IO_mio;
  wire FIXED_IO_ps_clk;
  wire FIXED_IO_ps_porb;
  wire FIXED_IO_ps_srstb;
  wire SPI_1_0_io0_i;
  wire SPI_1_0_io0_io;
  wire SPI_1_0_io0_o;
  wire SPI_1_0_io0_t;
  wire SPI_1_0_io1_i;
  wire SPI_1_0_io1_io;
  wire SPI_1_0_io1_o;
  wire SPI_1_0_io1_t;
  wire SPI_1_0_sck_i;
  wire SPI_1_0_sck_io;
  wire SPI_1_0_sck_o;
  wire SPI_1_0_sck_t;
  wire SPI_1_0_ss1_o;
  wire SPI_1_0_ss2_o;
  wire SPI_1_0_ss_i;
  wire SPI_1_0_ss_io;
  wire SPI_1_0_ss_o;
  wire SPI_1_0_ss_t;
  wire acq_gate_out_0;
  wire acq_trig_out_0;
  wire [31:0]ad9528_measure_count_in;
  wire [31:0]ad9528_measure_status_in;
  wire dbg_apply_enable_blocked;
  wire [15:0]dbg_current_rate_mbps;
  wire dbg_gt0_gttxreset_effective;
  wire dbg_gt0_txuserrdy_effective;
  wire [8:0]dbg_gt_drp_addr;
  wire dbg_gt_drp_busy;
  wire [15:0]dbg_gt_drp_di;
  wire [15:0]dbg_gt_drp_do;
  wire dbg_gt_drp_done;
  wire dbg_gt_drp_en;
  wire dbg_gt_drp_error;
  wire dbg_gt_drp_rdy;
  wire [15:0]dbg_gt_drp_readback_value;
  wire dbg_gt_drp_we;
  wire dbg_gt_drp_write_attempted;
  wire dbg_gt_ready;
  wire [6:0]dbg_mmcm_drp_addr;
  wire dbg_mmcm_drp_busy;
  wire [15:0]dbg_mmcm_drp_di;
  wire [15:0]dbg_mmcm_drp_do;
  wire dbg_mmcm_drp_done;
  wire dbg_mmcm_drp_en;
  wire dbg_mmcm_drp_error;
  wire dbg_mmcm_drp_rdy;
  wire dbg_mmcm_drp_we;
  wire dbg_mmcm_drp_write_attempted;
  wire dbg_rate_error;
  wire [7:0]dbg_rate_error_code;
  wire dbg_rate_gt_tx_reset;
  wire [7:0]dbg_rate_state;
  wire dbg_rate_txuserrdy_block;
  wire [15:0]dbg_target_rate_mbps;
  wire [31:0]dbg_timeout_count;
  wire dbg_tx_idle_seen;
  wire dbg_tx_mmcm_locked_raw;
  wire dbg_tx_mmcm_locked_sync;
  wire dbg_tx_mmcm_reset;
  wire dbg_tx_mmcm_reset_rate;
  wire dbg_tx_mmcm_reset_wizard;
  wire dbg_tx_quiesce_req;
  wire dbg_txoutclk_alive_axi;
  wire dbg_txresetdone_sync;
  wire dbg_txusrclk2_alive_axi;
  wire [31:0]dbg_txusrclk2_freq_counter_axi;
  wire [31:0]dynamic_descriptor_bram_portb_addr;
  wire dynamic_descriptor_bram_portb_clk;
  wire [31:0]dynamic_descriptor_bram_portb_din;
  wire [31:0]dynamic_descriptor_bram_portb_dout;
  wire dynamic_descriptor_bram_portb_en;
  wire dynamic_descriptor_bram_portb_rst;
  wire [3:0]dynamic_descriptor_bram_portb_we;
  wire [3:0]dynamic_mailbox_control_out;
  wire [31:0]dynamic_mailbox_status_in;
  wire eom_out_0;
  wire [31:0]gpio_ctrl_to_gt;
  wire [31:0]gpio_status_to_gt;
  wire gt_ctrl_clk;
  wire [0:0]gt_ctrl_rst;
  wire gt_ready;
  wire [31:0]gt_status_in;
  wire soa_gate_out_0;
  wire tx_rst;
  wire [63:0]txdata;
  wire txusrclk2;
  wire [63:0]valid_mask;

  IOBUF SPI_1_0_io0_iobuf
       (.I(SPI_1_0_io0_o),
        .IO(SPI_1_0_io0_io),
        .O(SPI_1_0_io0_i),
        .T(SPI_1_0_io0_t));
  IOBUF SPI_1_0_io1_iobuf
       (.I(SPI_1_0_io1_o),
        .IO(SPI_1_0_io1_io),
        .O(SPI_1_0_io1_i),
        .T(SPI_1_0_io1_t));
  IOBUF SPI_1_0_sck_iobuf
       (.I(SPI_1_0_sck_o),
        .IO(SPI_1_0_sck_io),
        .O(SPI_1_0_sck_i),
        .T(SPI_1_0_sck_t));
  IOBUF SPI_1_0_ss_iobuf
       (.I(SPI_1_0_ss_o),
        .IO(SPI_1_0_ss_io),
        .O(SPI_1_0_ss_i),
        .T(SPI_1_0_ss_t));
  system system_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .SPI_1_0_io0_i(SPI_1_0_io0_i),
        .SPI_1_0_io0_o(SPI_1_0_io0_o),
        .SPI_1_0_io0_t(SPI_1_0_io0_t),
        .SPI_1_0_io1_i(SPI_1_0_io1_i),
        .SPI_1_0_io1_o(SPI_1_0_io1_o),
        .SPI_1_0_io1_t(SPI_1_0_io1_t),
        .SPI_1_0_sck_i(SPI_1_0_sck_i),
        .SPI_1_0_sck_o(SPI_1_0_sck_o),
        .SPI_1_0_sck_t(SPI_1_0_sck_t),
        .SPI_1_0_ss1_o(SPI_1_0_ss1_o),
        .SPI_1_0_ss2_o(SPI_1_0_ss2_o),
        .SPI_1_0_ss_i(SPI_1_0_ss_i),
        .SPI_1_0_ss_o(SPI_1_0_ss_o),
        .SPI_1_0_ss_t(SPI_1_0_ss_t),
        .acq_gate_out_0(acq_gate_out_0),
        .acq_trig_out_0(acq_trig_out_0),
        .ad9528_measure_count_in(ad9528_measure_count_in),
        .ad9528_measure_status_in(ad9528_measure_status_in),
        .dbg_apply_enable_blocked(dbg_apply_enable_blocked),
        .dbg_current_rate_mbps(dbg_current_rate_mbps),
        .dbg_gt0_gttxreset_effective(dbg_gt0_gttxreset_effective),
        .dbg_gt0_txuserrdy_effective(dbg_gt0_txuserrdy_effective),
        .dbg_gt_drp_addr(dbg_gt_drp_addr),
        .dbg_gt_drp_busy(dbg_gt_drp_busy),
        .dbg_gt_drp_di(dbg_gt_drp_di),
        .dbg_gt_drp_do(dbg_gt_drp_do),
        .dbg_gt_drp_done(dbg_gt_drp_done),
        .dbg_gt_drp_en(dbg_gt_drp_en),
        .dbg_gt_drp_error(dbg_gt_drp_error),
        .dbg_gt_drp_rdy(dbg_gt_drp_rdy),
        .dbg_gt_drp_readback_value(dbg_gt_drp_readback_value),
        .dbg_gt_drp_we(dbg_gt_drp_we),
        .dbg_gt_drp_write_attempted(dbg_gt_drp_write_attempted),
        .dbg_gt_ready(dbg_gt_ready),
        .dbg_mmcm_drp_addr(dbg_mmcm_drp_addr),
        .dbg_mmcm_drp_busy(dbg_mmcm_drp_busy),
        .dbg_mmcm_drp_di(dbg_mmcm_drp_di),
        .dbg_mmcm_drp_do(dbg_mmcm_drp_do),
        .dbg_mmcm_drp_done(dbg_mmcm_drp_done),
        .dbg_mmcm_drp_en(dbg_mmcm_drp_en),
        .dbg_mmcm_drp_error(dbg_mmcm_drp_error),
        .dbg_mmcm_drp_rdy(dbg_mmcm_drp_rdy),
        .dbg_mmcm_drp_we(dbg_mmcm_drp_we),
        .dbg_mmcm_drp_write_attempted(dbg_mmcm_drp_write_attempted),
        .dbg_rate_error(dbg_rate_error),
        .dbg_rate_error_code(dbg_rate_error_code),
        .dbg_rate_gt_tx_reset(dbg_rate_gt_tx_reset),
        .dbg_rate_state(dbg_rate_state),
        .dbg_rate_txuserrdy_block(dbg_rate_txuserrdy_block),
        .dbg_target_rate_mbps(dbg_target_rate_mbps),
        .dbg_timeout_count(dbg_timeout_count),
        .dbg_tx_idle_seen(dbg_tx_idle_seen),
        .dbg_tx_mmcm_locked_raw(dbg_tx_mmcm_locked_raw),
        .dbg_tx_mmcm_locked_sync(dbg_tx_mmcm_locked_sync),
        .dbg_tx_mmcm_reset(dbg_tx_mmcm_reset),
        .dbg_tx_mmcm_reset_rate(dbg_tx_mmcm_reset_rate),
        .dbg_tx_mmcm_reset_wizard(dbg_tx_mmcm_reset_wizard),
        .dbg_tx_quiesce_req(dbg_tx_quiesce_req),
        .dbg_txoutclk_alive_axi(dbg_txoutclk_alive_axi),
        .dbg_txresetdone_sync(dbg_txresetdone_sync),
        .dbg_txusrclk2_alive_axi(dbg_txusrclk2_alive_axi),
        .dbg_txusrclk2_freq_counter_axi(dbg_txusrclk2_freq_counter_axi),
        .dynamic_descriptor_bram_portb_addr(dynamic_descriptor_bram_portb_addr),
        .dynamic_descriptor_bram_portb_clk(dynamic_descriptor_bram_portb_clk),
        .dynamic_descriptor_bram_portb_din(dynamic_descriptor_bram_portb_din),
        .dynamic_descriptor_bram_portb_dout(dynamic_descriptor_bram_portb_dout),
        .dynamic_descriptor_bram_portb_en(dynamic_descriptor_bram_portb_en),
        .dynamic_descriptor_bram_portb_rst(dynamic_descriptor_bram_portb_rst),
        .dynamic_descriptor_bram_portb_we(dynamic_descriptor_bram_portb_we),
        .dynamic_mailbox_control_out(dynamic_mailbox_control_out),
        .dynamic_mailbox_status_in(dynamic_mailbox_status_in),
        .eom_out_0(eom_out_0),
        .gpio_ctrl_to_gt(gpio_ctrl_to_gt),
        .gpio_status_to_gt(gpio_status_to_gt),
        .gt_ctrl_clk(gt_ctrl_clk),
        .gt_ctrl_rst(gt_ctrl_rst),
        .gt_ready(gt_ready),
        .gt_status_in(gt_status_in),
        .soa_gate_out_0(soa_gate_out_0),
        .tx_rst(tx_rst),
        .txdata(txdata),
        .txusrclk2(txusrclk2),
        .valid_mask(valid_mask));
endmodule

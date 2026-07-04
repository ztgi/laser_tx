//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Fri Jul  3 13:45:22 2026
//Host        : LAPTOP-ITN6KOP9 running 64-bit major release  (build 9200)
//Command     : generate_target system.bd
//Design      : system
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "system,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=system,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=10,numReposBlks=10,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=1,numPkgbdBlks=0,bdsource=USER,da_axi4_cnt=2,da_board_cnt=2,da_bram_cntlr_cnt=1,da_clkrst_cnt=1,da_ps7_cnt=1,synth_mode=OOC_per_IP}" *) (* HW_HANDOFF = "system.hwdef" *) 
module system
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
    SPI_1_0_io0_i,
    SPI_1_0_io0_o,
    SPI_1_0_io0_t,
    SPI_1_0_io1_i,
    SPI_1_0_io1_o,
    SPI_1_0_io1_t,
    SPI_1_0_sck_i,
    SPI_1_0_sck_o,
    SPI_1_0_sck_t,
    SPI_1_0_ss1_o,
    SPI_1_0_ss2_o,
    SPI_1_0_ss_i,
    SPI_1_0_ss_o,
    SPI_1_0_ss_t,
    acq_gate_out_0,
    acq_trig_out_0,
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
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR ADDR" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME DDR, AXI_ARBITRATION_SCHEME TDM, BURST_LENGTH 8, CAN_DEBUG false, CAS_LATENCY 11, CAS_WRITE_LATENCY 11, CS_ENABLED true, DATA_MASK_ENABLED true, DATA_WIDTH 8, MEMORY_TYPE COMPONENTS, MEM_ADDR_MAP ROW_COLUMN_BANK, SLOT Single, TIMEPERIOD_PS 1250" *) inout [14:0]DDR_addr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR BA" *) inout [2:0]DDR_ba;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR CAS_N" *) inout DDR_cas_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR CK_N" *) inout DDR_ck_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR CK_P" *) inout DDR_ck_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR CKE" *) inout DDR_cke;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR CS_N" *) inout DDR_cs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR DM" *) inout [3:0]DDR_dm;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR DQ" *) inout [31:0]DDR_dq;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR DQS_N" *) inout [3:0]DDR_dqs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR DQS_P" *) inout [3:0]DDR_dqs_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR ODT" *) inout DDR_odt;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR RAS_N" *) inout DDR_ras_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR RESET_N" *) inout DDR_reset_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddrx:1.0 DDR WE_N" *) inout DDR_we_n;
  (* X_INTERFACE_INFO = "xilinx.com:display_processing_system7:fixedio:1.0 FIXED_IO DDR_VRN" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME FIXED_IO, CAN_DEBUG false" *) inout FIXED_IO_ddr_vrn;
  (* X_INTERFACE_INFO = "xilinx.com:display_processing_system7:fixedio:1.0 FIXED_IO DDR_VRP" *) inout FIXED_IO_ddr_vrp;
  (* X_INTERFACE_INFO = "xilinx.com:display_processing_system7:fixedio:1.0 FIXED_IO MIO" *) inout [53:0]FIXED_IO_mio;
  (* X_INTERFACE_INFO = "xilinx.com:display_processing_system7:fixedio:1.0 FIXED_IO PS_CLK" *) inout FIXED_IO_ps_clk;
  (* X_INTERFACE_INFO = "xilinx.com:display_processing_system7:fixedio:1.0 FIXED_IO PS_PORB" *) inout FIXED_IO_ps_porb;
  (* X_INTERFACE_INFO = "xilinx.com:display_processing_system7:fixedio:1.0 FIXED_IO PS_SRSTB" *) inout FIXED_IO_ps_srstb;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 IO0_I" *) input SPI_1_0_io0_i;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 IO0_O" *) output SPI_1_0_io0_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 IO0_T" *) output SPI_1_0_io0_t;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 IO1_I" *) input SPI_1_0_io1_i;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 IO1_O" *) output SPI_1_0_io1_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 IO1_T" *) output SPI_1_0_io1_t;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SCK_I" *) input SPI_1_0_sck_i;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SCK_O" *) output SPI_1_0_sck_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SCK_T" *) output SPI_1_0_sck_t;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SS1_O" *) output SPI_1_0_ss1_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SS2_O" *) output SPI_1_0_ss2_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SS_I" *) input SPI_1_0_ss_i;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SS_O" *) output SPI_1_0_ss_o;
  (* X_INTERFACE_INFO = "xilinx.com:interface:spi:1.0 SPI_1_0 SS_T" *) output SPI_1_0_ss_t;
  output acq_gate_out_0;
  output acq_trig_out_0;
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

  wire [12:0]axi_bram_ctrl_0_BRAM_PORTA_ADDR;
  wire axi_bram_ctrl_0_BRAM_PORTA_CLK;
  wire [31:0]axi_bram_ctrl_0_BRAM_PORTA_DIN;
  wire [31:0]axi_bram_ctrl_0_BRAM_PORTA_DOUT;
  wire axi_bram_ctrl_0_BRAM_PORTA_EN;
  wire axi_bram_ctrl_0_BRAM_PORTA_RST;
  wire [3:0]axi_bram_ctrl_0_BRAM_PORTA_WE;
  wire [31:0]axi_gpio_0_gpio_io_o;
  wire [12:0]axi_smc_M00_AXI_ARADDR;
  wire [1:0]axi_smc_M00_AXI_ARBURST;
  wire [3:0]axi_smc_M00_AXI_ARCACHE;
  wire [7:0]axi_smc_M00_AXI_ARLEN;
  wire [0:0]axi_smc_M00_AXI_ARLOCK;
  wire [2:0]axi_smc_M00_AXI_ARPROT;
  wire axi_smc_M00_AXI_ARREADY;
  wire [2:0]axi_smc_M00_AXI_ARSIZE;
  wire axi_smc_M00_AXI_ARVALID;
  wire [12:0]axi_smc_M00_AXI_AWADDR;
  wire [1:0]axi_smc_M00_AXI_AWBURST;
  wire [3:0]axi_smc_M00_AXI_AWCACHE;
  wire [7:0]axi_smc_M00_AXI_AWLEN;
  wire [0:0]axi_smc_M00_AXI_AWLOCK;
  wire [2:0]axi_smc_M00_AXI_AWPROT;
  wire axi_smc_M00_AXI_AWREADY;
  wire [2:0]axi_smc_M00_AXI_AWSIZE;
  wire axi_smc_M00_AXI_AWVALID;
  wire axi_smc_M00_AXI_BREADY;
  wire [1:0]axi_smc_M00_AXI_BRESP;
  wire axi_smc_M00_AXI_BVALID;
  wire [31:0]axi_smc_M00_AXI_RDATA;
  wire axi_smc_M00_AXI_RLAST;
  wire axi_smc_M00_AXI_RREADY;
  wire [1:0]axi_smc_M00_AXI_RRESP;
  wire axi_smc_M00_AXI_RVALID;
  wire [31:0]axi_smc_M00_AXI_WDATA;
  wire axi_smc_M00_AXI_WLAST;
  wire axi_smc_M00_AXI_WREADY;
  wire [3:0]axi_smc_M00_AXI_WSTRB;
  wire axi_smc_M00_AXI_WVALID;
  wire [8:0]axi_smc_M01_AXI_ARADDR;
  wire axi_smc_M01_AXI_ARREADY;
  wire axi_smc_M01_AXI_ARVALID;
  wire [8:0]axi_smc_M01_AXI_AWADDR;
  wire axi_smc_M01_AXI_AWREADY;
  wire axi_smc_M01_AXI_AWVALID;
  wire axi_smc_M01_AXI_BREADY;
  wire [1:0]axi_smc_M01_AXI_BRESP;
  wire axi_smc_M01_AXI_BVALID;
  wire [31:0]axi_smc_M01_AXI_RDATA;
  wire axi_smc_M01_AXI_RREADY;
  wire [1:0]axi_smc_M01_AXI_RRESP;
  wire axi_smc_M01_AXI_RVALID;
  wire [31:0]axi_smc_M01_AXI_WDATA;
  wire axi_smc_M01_AXI_WREADY;
  wire [3:0]axi_smc_M01_AXI_WSTRB;
  wire axi_smc_M01_AXI_WVALID;
  wire [8:0]axi_smc_M02_AXI_ARADDR;
  wire axi_smc_M02_AXI_ARREADY;
  wire axi_smc_M02_AXI_ARVALID;
  wire [8:0]axi_smc_M02_AXI_AWADDR;
  wire axi_smc_M02_AXI_AWREADY;
  wire axi_smc_M02_AXI_AWVALID;
  wire axi_smc_M02_AXI_BREADY;
  wire [1:0]axi_smc_M02_AXI_BRESP;
  wire axi_smc_M02_AXI_BVALID;
  wire [31:0]axi_smc_M02_AXI_RDATA;
  wire axi_smc_M02_AXI_RREADY;
  wire [1:0]axi_smc_M02_AXI_RRESP;
  wire axi_smc_M02_AXI_RVALID;
  wire [31:0]axi_smc_M02_AXI_WDATA;
  wire axi_smc_M02_AXI_WREADY;
  wire [3:0]axi_smc_M02_AXI_WSTRB;
  wire axi_smc_M02_AXI_WVALID;
  wire dbg_apply_enable_blocked_1;
  wire [15:0]dbg_current_rate_mbps_1;
  wire dbg_gt0_gttxreset_effective_1;
  wire dbg_gt0_txuserrdy_effective_1;
  wire [8:0]dbg_gt_drp_addr_1;
  wire dbg_gt_drp_busy_1;
  wire [15:0]dbg_gt_drp_di_1;
  wire [15:0]dbg_gt_drp_do_1;
  wire dbg_gt_drp_done_1;
  wire dbg_gt_drp_en_1;
  wire dbg_gt_drp_error_1;
  wire dbg_gt_drp_rdy_1;
  wire [15:0]dbg_gt_drp_readback_value_1;
  wire dbg_gt_drp_we_1;
  wire dbg_gt_drp_write_attempted_1;
  wire dbg_gt_ready_1;
  wire [6:0]dbg_mmcm_drp_addr_1;
  wire dbg_mmcm_drp_busy_1;
  wire [15:0]dbg_mmcm_drp_di_1;
  wire [15:0]dbg_mmcm_drp_do_1;
  wire dbg_mmcm_drp_done_1;
  wire dbg_mmcm_drp_en_1;
  wire dbg_mmcm_drp_error_1;
  wire dbg_mmcm_drp_rdy_1;
  wire dbg_mmcm_drp_we_1;
  wire dbg_mmcm_drp_write_attempted_1;
  wire dbg_rate_error_1;
  wire [7:0]dbg_rate_error_code_1;
  wire dbg_rate_gt_tx_reset_1;
  wire [7:0]dbg_rate_state_1;
  wire dbg_rate_txuserrdy_block_1;
  wire [15:0]dbg_target_rate_mbps_1;
  wire [31:0]dbg_timeout_count_1;
  wire dbg_tx_idle_seen_1;
  wire dbg_tx_mmcm_locked_raw_1;
  wire dbg_tx_mmcm_locked_sync_1;
  wire dbg_tx_mmcm_reset_1;
  wire dbg_tx_mmcm_reset_rate_1;
  wire dbg_tx_mmcm_reset_wizard_1;
  wire dbg_tx_quiesce_req_1;
  wire dbg_txoutclk_alive_axi_1;
  wire dbg_txresetdone_sync_1;
  wire dbg_txusrclk2_alive_axi_1;
  wire [31:0]dbg_txusrclk2_freq_counter_axi_1;
  wire gt_ready_1;
  wire [31:0]gt_status_in_1;
  wire [31:0]laser_tx_core_0_BRAM_PORTB_ADDR;
  wire laser_tx_core_0_BRAM_PORTB_CLK;
  wire [31:0]laser_tx_core_0_BRAM_PORTB_DIN;
  wire [31:0]laser_tx_core_0_BRAM_PORTB_DOUT;
  wire laser_tx_core_0_BRAM_PORTB_EN;
  wire laser_tx_core_0_BRAM_PORTB_RST;
  wire [3:0]laser_tx_core_0_BRAM_PORTB_WE;
  wire laser_tx_core_0_acq_gate_out;
  wire laser_tx_core_0_acq_trig_out;
  wire [31:0]laser_tx_core_0_dbg_bram_addr;
  wire [31:0]laser_tx_core_0_dbg_bram_dout;
  wire laser_tx_core_0_dbg_bram_en;
  wire laser_tx_core_0_dbg_bram_rst;
  wire laser_tx_core_0_dbg_busy_tx;
  wire laser_tx_core_0_dbg_cfg_update_pulse_tx;
  wire [7:0]laser_tx_core_0_dbg_current_state_tx;
  wire laser_tx_core_0_dbg_done_tx;
  wire laser_tx_core_0_dbg_engine_start_tx;
  wire laser_tx_core_0_dbg_pattern_valid_tx;
  wire laser_tx_core_0_dbg_phase_active_tx;
  wire [7:0]laser_tx_core_0_dbg_phase_offset_tx;
  wire laser_tx_core_0_dbg_phase_start_pulse_tx;
  wire laser_tx_core_0_eom_out;
  wire [31:0]laser_tx_core_0_gpio_status;
  wire laser_tx_core_0_soa_gate_out;
  wire [63:0]laser_tx_core_0_txdata;
  wire [63:0]laser_tx_core_0_valid_mask;
  wire [14:0]processing_system7_0_DDR_ADDR;
  wire [2:0]processing_system7_0_DDR_BA;
  wire processing_system7_0_DDR_CAS_N;
  wire processing_system7_0_DDR_CKE;
  wire processing_system7_0_DDR_CK_N;
  wire processing_system7_0_DDR_CK_P;
  wire processing_system7_0_DDR_CS_N;
  wire [3:0]processing_system7_0_DDR_DM;
  wire [31:0]processing_system7_0_DDR_DQ;
  wire [3:0]processing_system7_0_DDR_DQS_N;
  wire [3:0]processing_system7_0_DDR_DQS_P;
  wire processing_system7_0_DDR_ODT;
  wire processing_system7_0_DDR_RAS_N;
  wire processing_system7_0_DDR_RESET_N;
  wire processing_system7_0_DDR_WE_N;
  wire processing_system7_0_FCLK_CLK0;
  wire processing_system7_0_FCLK_RESET0_N;
  wire processing_system7_0_FIXED_IO_DDR_VRN;
  wire processing_system7_0_FIXED_IO_DDR_VRP;
  wire [53:0]processing_system7_0_FIXED_IO_MIO;
  wire processing_system7_0_FIXED_IO_PS_CLK;
  wire processing_system7_0_FIXED_IO_PS_PORB;
  wire processing_system7_0_FIXED_IO_PS_SRSTB;
  wire [31:0]processing_system7_0_M_AXI_GP0_ARADDR;
  wire [1:0]processing_system7_0_M_AXI_GP0_ARBURST;
  wire [3:0]processing_system7_0_M_AXI_GP0_ARCACHE;
  wire [11:0]processing_system7_0_M_AXI_GP0_ARID;
  wire [3:0]processing_system7_0_M_AXI_GP0_ARLEN;
  wire [1:0]processing_system7_0_M_AXI_GP0_ARLOCK;
  wire [2:0]processing_system7_0_M_AXI_GP0_ARPROT;
  wire [3:0]processing_system7_0_M_AXI_GP0_ARQOS;
  wire processing_system7_0_M_AXI_GP0_ARREADY;
  wire [2:0]processing_system7_0_M_AXI_GP0_ARSIZE;
  wire processing_system7_0_M_AXI_GP0_ARVALID;
  wire [31:0]processing_system7_0_M_AXI_GP0_AWADDR;
  wire [1:0]processing_system7_0_M_AXI_GP0_AWBURST;
  wire [3:0]processing_system7_0_M_AXI_GP0_AWCACHE;
  wire [11:0]processing_system7_0_M_AXI_GP0_AWID;
  wire [3:0]processing_system7_0_M_AXI_GP0_AWLEN;
  wire [1:0]processing_system7_0_M_AXI_GP0_AWLOCK;
  wire [2:0]processing_system7_0_M_AXI_GP0_AWPROT;
  wire [3:0]processing_system7_0_M_AXI_GP0_AWQOS;
  wire processing_system7_0_M_AXI_GP0_AWREADY;
  wire [2:0]processing_system7_0_M_AXI_GP0_AWSIZE;
  wire processing_system7_0_M_AXI_GP0_AWVALID;
  wire [11:0]processing_system7_0_M_AXI_GP0_BID;
  wire processing_system7_0_M_AXI_GP0_BREADY;
  wire [1:0]processing_system7_0_M_AXI_GP0_BRESP;
  wire processing_system7_0_M_AXI_GP0_BVALID;
  wire [31:0]processing_system7_0_M_AXI_GP0_RDATA;
  wire [11:0]processing_system7_0_M_AXI_GP0_RID;
  wire processing_system7_0_M_AXI_GP0_RLAST;
  wire processing_system7_0_M_AXI_GP0_RREADY;
  wire [1:0]processing_system7_0_M_AXI_GP0_RRESP;
  wire processing_system7_0_M_AXI_GP0_RVALID;
  wire [31:0]processing_system7_0_M_AXI_GP0_WDATA;
  wire [11:0]processing_system7_0_M_AXI_GP0_WID;
  wire processing_system7_0_M_AXI_GP0_WLAST;
  wire processing_system7_0_M_AXI_GP0_WREADY;
  wire [3:0]processing_system7_0_M_AXI_GP0_WSTRB;
  wire processing_system7_0_M_AXI_GP0_WVALID;
  wire processing_system7_0_SPI_1_IO0_I;
  wire processing_system7_0_SPI_1_IO0_O;
  wire processing_system7_0_SPI_1_IO0_T;
  wire processing_system7_0_SPI_1_IO1_I;
  wire processing_system7_0_SPI_1_IO1_O;
  wire processing_system7_0_SPI_1_IO1_T;
  wire processing_system7_0_SPI_1_SCK_I;
  wire processing_system7_0_SPI_1_SCK_O;
  wire processing_system7_0_SPI_1_SCK_T;
  wire processing_system7_0_SPI_1_SS1_O;
  wire processing_system7_0_SPI_1_SS2_O;
  wire processing_system7_0_SPI_1_SS_I;
  wire processing_system7_0_SPI_1_SS_O;
  wire processing_system7_0_SPI_1_SS_T;
  wire [0:0]rst_ps7_0_50M_peripheral_aresetn;
  wire [0:0]rst_ps7_0_50M_peripheral_reset;
  wire tx_rst_1;
  wire txusrclk2_1;

  assign SPI_1_0_io0_o = processing_system7_0_SPI_1_IO0_O;
  assign SPI_1_0_io0_t = processing_system7_0_SPI_1_IO0_T;
  assign SPI_1_0_io1_o = processing_system7_0_SPI_1_IO1_O;
  assign SPI_1_0_io1_t = processing_system7_0_SPI_1_IO1_T;
  assign SPI_1_0_sck_o = processing_system7_0_SPI_1_SCK_O;
  assign SPI_1_0_sck_t = processing_system7_0_SPI_1_SCK_T;
  assign SPI_1_0_ss1_o = processing_system7_0_SPI_1_SS1_O;
  assign SPI_1_0_ss2_o = processing_system7_0_SPI_1_SS2_O;
  assign SPI_1_0_ss_o = processing_system7_0_SPI_1_SS_O;
  assign SPI_1_0_ss_t = processing_system7_0_SPI_1_SS_T;
  assign acq_gate_out_0 = laser_tx_core_0_acq_gate_out;
  assign acq_trig_out_0 = laser_tx_core_0_acq_trig_out;
  assign dbg_apply_enable_blocked_1 = dbg_apply_enable_blocked;
  assign dbg_current_rate_mbps_1 = dbg_current_rate_mbps[15:0];
  assign dbg_gt0_gttxreset_effective_1 = dbg_gt0_gttxreset_effective;
  assign dbg_gt0_txuserrdy_effective_1 = dbg_gt0_txuserrdy_effective;
  assign dbg_gt_drp_addr_1 = dbg_gt_drp_addr[8:0];
  assign dbg_gt_drp_busy_1 = dbg_gt_drp_busy;
  assign dbg_gt_drp_di_1 = dbg_gt_drp_di[15:0];
  assign dbg_gt_drp_do_1 = dbg_gt_drp_do[15:0];
  assign dbg_gt_drp_done_1 = dbg_gt_drp_done;
  assign dbg_gt_drp_en_1 = dbg_gt_drp_en;
  assign dbg_gt_drp_error_1 = dbg_gt_drp_error;
  assign dbg_gt_drp_rdy_1 = dbg_gt_drp_rdy;
  assign dbg_gt_drp_readback_value_1 = dbg_gt_drp_readback_value[15:0];
  assign dbg_gt_drp_we_1 = dbg_gt_drp_we;
  assign dbg_gt_drp_write_attempted_1 = dbg_gt_drp_write_attempted;
  assign dbg_gt_ready_1 = dbg_gt_ready;
  assign dbg_mmcm_drp_addr_1 = dbg_mmcm_drp_addr[6:0];
  assign dbg_mmcm_drp_busy_1 = dbg_mmcm_drp_busy;
  assign dbg_mmcm_drp_di_1 = dbg_mmcm_drp_di[15:0];
  assign dbg_mmcm_drp_do_1 = dbg_mmcm_drp_do[15:0];
  assign dbg_mmcm_drp_done_1 = dbg_mmcm_drp_done;
  assign dbg_mmcm_drp_en_1 = dbg_mmcm_drp_en;
  assign dbg_mmcm_drp_error_1 = dbg_mmcm_drp_error;
  assign dbg_mmcm_drp_rdy_1 = dbg_mmcm_drp_rdy;
  assign dbg_mmcm_drp_we_1 = dbg_mmcm_drp_we;
  assign dbg_mmcm_drp_write_attempted_1 = dbg_mmcm_drp_write_attempted;
  assign dbg_rate_error_1 = dbg_rate_error;
  assign dbg_rate_error_code_1 = dbg_rate_error_code[7:0];
  assign dbg_rate_gt_tx_reset_1 = dbg_rate_gt_tx_reset;
  assign dbg_rate_state_1 = dbg_rate_state[7:0];
  assign dbg_rate_txuserrdy_block_1 = dbg_rate_txuserrdy_block;
  assign dbg_target_rate_mbps_1 = dbg_target_rate_mbps[15:0];
  assign dbg_timeout_count_1 = dbg_timeout_count[31:0];
  assign dbg_tx_idle_seen_1 = dbg_tx_idle_seen;
  assign dbg_tx_mmcm_locked_raw_1 = dbg_tx_mmcm_locked_raw;
  assign dbg_tx_mmcm_locked_sync_1 = dbg_tx_mmcm_locked_sync;
  assign dbg_tx_mmcm_reset_1 = dbg_tx_mmcm_reset;
  assign dbg_tx_mmcm_reset_rate_1 = dbg_tx_mmcm_reset_rate;
  assign dbg_tx_mmcm_reset_wizard_1 = dbg_tx_mmcm_reset_wizard;
  assign dbg_tx_quiesce_req_1 = dbg_tx_quiesce_req;
  assign dbg_txoutclk_alive_axi_1 = dbg_txoutclk_alive_axi;
  assign dbg_txresetdone_sync_1 = dbg_txresetdone_sync;
  assign dbg_txusrclk2_alive_axi_1 = dbg_txusrclk2_alive_axi;
  assign dbg_txusrclk2_freq_counter_axi_1 = dbg_txusrclk2_freq_counter_axi[31:0];
  assign eom_out_0 = laser_tx_core_0_eom_out;
  assign gpio_ctrl_to_gt[31:0] = axi_gpio_0_gpio_io_o;
  assign gpio_status_to_gt[31:0] = laser_tx_core_0_gpio_status;
  assign gt_ctrl_clk = processing_system7_0_FCLK_CLK0;
  assign gt_ctrl_rst[0] = rst_ps7_0_50M_peripheral_reset;
  assign gt_ready_1 = gt_ready;
  assign gt_status_in_1 = gt_status_in[31:0];
  assign processing_system7_0_SPI_1_IO0_I = SPI_1_0_io0_i;
  assign processing_system7_0_SPI_1_IO1_I = SPI_1_0_io1_i;
  assign processing_system7_0_SPI_1_SCK_I = SPI_1_0_sck_i;
  assign processing_system7_0_SPI_1_SS_I = SPI_1_0_ss_i;
  assign soa_gate_out_0 = laser_tx_core_0_soa_gate_out;
  assign tx_rst_1 = tx_rst;
  assign txdata[63:0] = laser_tx_core_0_txdata;
  assign txusrclk2_1 = txusrclk2;
  assign valid_mask[63:0] = laser_tx_core_0_valid_mask;
  (* BMM_INFO_ADDRESS_SPACE = "byte  0x40000000 32 > system blk_mem_gen_0" *) 
  (* KEEP_HIERARCHY = "yes" *) 
  system_axi_bram_ctrl_0_0 axi_bram_ctrl_0
       (.bram_addr_a(axi_bram_ctrl_0_BRAM_PORTA_ADDR),
        .bram_clk_a(axi_bram_ctrl_0_BRAM_PORTA_CLK),
        .bram_en_a(axi_bram_ctrl_0_BRAM_PORTA_EN),
        .bram_rddata_a(axi_bram_ctrl_0_BRAM_PORTA_DOUT),
        .bram_rst_a(axi_bram_ctrl_0_BRAM_PORTA_RST),
        .bram_we_a(axi_bram_ctrl_0_BRAM_PORTA_WE),
        .bram_wrdata_a(axi_bram_ctrl_0_BRAM_PORTA_DIN),
        .s_axi_aclk(processing_system7_0_FCLK_CLK0),
        .s_axi_araddr(axi_smc_M00_AXI_ARADDR),
        .s_axi_arburst(axi_smc_M00_AXI_ARBURST),
        .s_axi_arcache(axi_smc_M00_AXI_ARCACHE),
        .s_axi_aresetn(rst_ps7_0_50M_peripheral_aresetn),
        .s_axi_arlen(axi_smc_M00_AXI_ARLEN),
        .s_axi_arlock(axi_smc_M00_AXI_ARLOCK),
        .s_axi_arprot(axi_smc_M00_AXI_ARPROT),
        .s_axi_arready(axi_smc_M00_AXI_ARREADY),
        .s_axi_arsize(axi_smc_M00_AXI_ARSIZE),
        .s_axi_arvalid(axi_smc_M00_AXI_ARVALID),
        .s_axi_awaddr(axi_smc_M00_AXI_AWADDR),
        .s_axi_awburst(axi_smc_M00_AXI_AWBURST),
        .s_axi_awcache(axi_smc_M00_AXI_AWCACHE),
        .s_axi_awlen(axi_smc_M00_AXI_AWLEN),
        .s_axi_awlock(axi_smc_M00_AXI_AWLOCK),
        .s_axi_awprot(axi_smc_M00_AXI_AWPROT),
        .s_axi_awready(axi_smc_M00_AXI_AWREADY),
        .s_axi_awsize(axi_smc_M00_AXI_AWSIZE),
        .s_axi_awvalid(axi_smc_M00_AXI_AWVALID),
        .s_axi_bready(axi_smc_M00_AXI_BREADY),
        .s_axi_bresp(axi_smc_M00_AXI_BRESP),
        .s_axi_bvalid(axi_smc_M00_AXI_BVALID),
        .s_axi_rdata(axi_smc_M00_AXI_RDATA),
        .s_axi_rlast(axi_smc_M00_AXI_RLAST),
        .s_axi_rready(axi_smc_M00_AXI_RREADY),
        .s_axi_rresp(axi_smc_M00_AXI_RRESP),
        .s_axi_rvalid(axi_smc_M00_AXI_RVALID),
        .s_axi_wdata(axi_smc_M00_AXI_WDATA),
        .s_axi_wlast(axi_smc_M00_AXI_WLAST),
        .s_axi_wready(axi_smc_M00_AXI_WREADY),
        .s_axi_wstrb(axi_smc_M00_AXI_WSTRB),
        .s_axi_wvalid(axi_smc_M00_AXI_WVALID));
  system_axi_gpio_0_0 axi_gpio_0
       (.gpio2_io_i(laser_tx_core_0_gpio_status),
        .gpio_io_o(axi_gpio_0_gpio_io_o),
        .s_axi_aclk(processing_system7_0_FCLK_CLK0),
        .s_axi_araddr(axi_smc_M01_AXI_ARADDR),
        .s_axi_aresetn(rst_ps7_0_50M_peripheral_aresetn),
        .s_axi_arready(axi_smc_M01_AXI_ARREADY),
        .s_axi_arvalid(axi_smc_M01_AXI_ARVALID),
        .s_axi_awaddr(axi_smc_M01_AXI_AWADDR),
        .s_axi_awready(axi_smc_M01_AXI_AWREADY),
        .s_axi_awvalid(axi_smc_M01_AXI_AWVALID),
        .s_axi_bready(axi_smc_M01_AXI_BREADY),
        .s_axi_bresp(axi_smc_M01_AXI_BRESP),
        .s_axi_bvalid(axi_smc_M01_AXI_BVALID),
        .s_axi_rdata(axi_smc_M01_AXI_RDATA),
        .s_axi_rready(axi_smc_M01_AXI_RREADY),
        .s_axi_rresp(axi_smc_M01_AXI_RRESP),
        .s_axi_rvalid(axi_smc_M01_AXI_RVALID),
        .s_axi_wdata(axi_smc_M01_AXI_WDATA),
        .s_axi_wready(axi_smc_M01_AXI_WREADY),
        .s_axi_wstrb(axi_smc_M01_AXI_WSTRB),
        .s_axi_wvalid(axi_smc_M01_AXI_WVALID));
  system_axi_gpio_gt_status_0 axi_gpio_gt_status
       (.gpio_io_i(gt_status_in_1),
        .s_axi_aclk(processing_system7_0_FCLK_CLK0),
        .s_axi_araddr(axi_smc_M02_AXI_ARADDR),
        .s_axi_aresetn(rst_ps7_0_50M_peripheral_aresetn),
        .s_axi_arready(axi_smc_M02_AXI_ARREADY),
        .s_axi_arvalid(axi_smc_M02_AXI_ARVALID),
        .s_axi_awaddr(axi_smc_M02_AXI_AWADDR),
        .s_axi_awready(axi_smc_M02_AXI_AWREADY),
        .s_axi_awvalid(axi_smc_M02_AXI_AWVALID),
        .s_axi_bready(axi_smc_M02_AXI_BREADY),
        .s_axi_bresp(axi_smc_M02_AXI_BRESP),
        .s_axi_bvalid(axi_smc_M02_AXI_BVALID),
        .s_axi_rdata(axi_smc_M02_AXI_RDATA),
        .s_axi_rready(axi_smc_M02_AXI_RREADY),
        .s_axi_rresp(axi_smc_M02_AXI_RRESP),
        .s_axi_rvalid(axi_smc_M02_AXI_RVALID),
        .s_axi_wdata(axi_smc_M02_AXI_WDATA),
        .s_axi_wready(axi_smc_M02_AXI_WREADY),
        .s_axi_wstrb(axi_smc_M02_AXI_WSTRB),
        .s_axi_wvalid(axi_smc_M02_AXI_WVALID));
  system_axi_smc_0 axi_smc
       (.M00_AXI_araddr(axi_smc_M00_AXI_ARADDR),
        .M00_AXI_arburst(axi_smc_M00_AXI_ARBURST),
        .M00_AXI_arcache(axi_smc_M00_AXI_ARCACHE),
        .M00_AXI_arlen(axi_smc_M00_AXI_ARLEN),
        .M00_AXI_arlock(axi_smc_M00_AXI_ARLOCK),
        .M00_AXI_arprot(axi_smc_M00_AXI_ARPROT),
        .M00_AXI_arready(axi_smc_M00_AXI_ARREADY),
        .M00_AXI_arsize(axi_smc_M00_AXI_ARSIZE),
        .M00_AXI_arvalid(axi_smc_M00_AXI_ARVALID),
        .M00_AXI_awaddr(axi_smc_M00_AXI_AWADDR),
        .M00_AXI_awburst(axi_smc_M00_AXI_AWBURST),
        .M00_AXI_awcache(axi_smc_M00_AXI_AWCACHE),
        .M00_AXI_awlen(axi_smc_M00_AXI_AWLEN),
        .M00_AXI_awlock(axi_smc_M00_AXI_AWLOCK),
        .M00_AXI_awprot(axi_smc_M00_AXI_AWPROT),
        .M00_AXI_awready(axi_smc_M00_AXI_AWREADY),
        .M00_AXI_awsize(axi_smc_M00_AXI_AWSIZE),
        .M00_AXI_awvalid(axi_smc_M00_AXI_AWVALID),
        .M00_AXI_bready(axi_smc_M00_AXI_BREADY),
        .M00_AXI_bresp(axi_smc_M00_AXI_BRESP),
        .M00_AXI_bvalid(axi_smc_M00_AXI_BVALID),
        .M00_AXI_rdata(axi_smc_M00_AXI_RDATA),
        .M00_AXI_rlast(axi_smc_M00_AXI_RLAST),
        .M00_AXI_rready(axi_smc_M00_AXI_RREADY),
        .M00_AXI_rresp(axi_smc_M00_AXI_RRESP),
        .M00_AXI_rvalid(axi_smc_M00_AXI_RVALID),
        .M00_AXI_wdata(axi_smc_M00_AXI_WDATA),
        .M00_AXI_wlast(axi_smc_M00_AXI_WLAST),
        .M00_AXI_wready(axi_smc_M00_AXI_WREADY),
        .M00_AXI_wstrb(axi_smc_M00_AXI_WSTRB),
        .M00_AXI_wvalid(axi_smc_M00_AXI_WVALID),
        .M01_AXI_araddr(axi_smc_M01_AXI_ARADDR),
        .M01_AXI_arready(axi_smc_M01_AXI_ARREADY),
        .M01_AXI_arvalid(axi_smc_M01_AXI_ARVALID),
        .M01_AXI_awaddr(axi_smc_M01_AXI_AWADDR),
        .M01_AXI_awready(axi_smc_M01_AXI_AWREADY),
        .M01_AXI_awvalid(axi_smc_M01_AXI_AWVALID),
        .M01_AXI_bready(axi_smc_M01_AXI_BREADY),
        .M01_AXI_bresp(axi_smc_M01_AXI_BRESP),
        .M01_AXI_bvalid(axi_smc_M01_AXI_BVALID),
        .M01_AXI_rdata(axi_smc_M01_AXI_RDATA),
        .M01_AXI_rready(axi_smc_M01_AXI_RREADY),
        .M01_AXI_rresp(axi_smc_M01_AXI_RRESP),
        .M01_AXI_rvalid(axi_smc_M01_AXI_RVALID),
        .M01_AXI_wdata(axi_smc_M01_AXI_WDATA),
        .M01_AXI_wready(axi_smc_M01_AXI_WREADY),
        .M01_AXI_wstrb(axi_smc_M01_AXI_WSTRB),
        .M01_AXI_wvalid(axi_smc_M01_AXI_WVALID),
        .M02_AXI_araddr(axi_smc_M02_AXI_ARADDR),
        .M02_AXI_arready(axi_smc_M02_AXI_ARREADY),
        .M02_AXI_arvalid(axi_smc_M02_AXI_ARVALID),
        .M02_AXI_awaddr(axi_smc_M02_AXI_AWADDR),
        .M02_AXI_awready(axi_smc_M02_AXI_AWREADY),
        .M02_AXI_awvalid(axi_smc_M02_AXI_AWVALID),
        .M02_AXI_bready(axi_smc_M02_AXI_BREADY),
        .M02_AXI_bresp(axi_smc_M02_AXI_BRESP),
        .M02_AXI_bvalid(axi_smc_M02_AXI_BVALID),
        .M02_AXI_rdata(axi_smc_M02_AXI_RDATA),
        .M02_AXI_rready(axi_smc_M02_AXI_RREADY),
        .M02_AXI_rresp(axi_smc_M02_AXI_RRESP),
        .M02_AXI_rvalid(axi_smc_M02_AXI_RVALID),
        .M02_AXI_wdata(axi_smc_M02_AXI_WDATA),
        .M02_AXI_wready(axi_smc_M02_AXI_WREADY),
        .M02_AXI_wstrb(axi_smc_M02_AXI_WSTRB),
        .M02_AXI_wvalid(axi_smc_M02_AXI_WVALID),
        .S00_AXI_araddr(processing_system7_0_M_AXI_GP0_ARADDR),
        .S00_AXI_arburst(processing_system7_0_M_AXI_GP0_ARBURST),
        .S00_AXI_arcache(processing_system7_0_M_AXI_GP0_ARCACHE),
        .S00_AXI_arid(processing_system7_0_M_AXI_GP0_ARID),
        .S00_AXI_arlen(processing_system7_0_M_AXI_GP0_ARLEN),
        .S00_AXI_arlock(processing_system7_0_M_AXI_GP0_ARLOCK),
        .S00_AXI_arprot(processing_system7_0_M_AXI_GP0_ARPROT),
        .S00_AXI_arqos(processing_system7_0_M_AXI_GP0_ARQOS),
        .S00_AXI_arready(processing_system7_0_M_AXI_GP0_ARREADY),
        .S00_AXI_arsize(processing_system7_0_M_AXI_GP0_ARSIZE),
        .S00_AXI_arvalid(processing_system7_0_M_AXI_GP0_ARVALID),
        .S00_AXI_awaddr(processing_system7_0_M_AXI_GP0_AWADDR),
        .S00_AXI_awburst(processing_system7_0_M_AXI_GP0_AWBURST),
        .S00_AXI_awcache(processing_system7_0_M_AXI_GP0_AWCACHE),
        .S00_AXI_awid(processing_system7_0_M_AXI_GP0_AWID),
        .S00_AXI_awlen(processing_system7_0_M_AXI_GP0_AWLEN),
        .S00_AXI_awlock(processing_system7_0_M_AXI_GP0_AWLOCK),
        .S00_AXI_awprot(processing_system7_0_M_AXI_GP0_AWPROT),
        .S00_AXI_awqos(processing_system7_0_M_AXI_GP0_AWQOS),
        .S00_AXI_awready(processing_system7_0_M_AXI_GP0_AWREADY),
        .S00_AXI_awsize(processing_system7_0_M_AXI_GP0_AWSIZE),
        .S00_AXI_awvalid(processing_system7_0_M_AXI_GP0_AWVALID),
        .S00_AXI_bid(processing_system7_0_M_AXI_GP0_BID),
        .S00_AXI_bready(processing_system7_0_M_AXI_GP0_BREADY),
        .S00_AXI_bresp(processing_system7_0_M_AXI_GP0_BRESP),
        .S00_AXI_bvalid(processing_system7_0_M_AXI_GP0_BVALID),
        .S00_AXI_rdata(processing_system7_0_M_AXI_GP0_RDATA),
        .S00_AXI_rid(processing_system7_0_M_AXI_GP0_RID),
        .S00_AXI_rlast(processing_system7_0_M_AXI_GP0_RLAST),
        .S00_AXI_rready(processing_system7_0_M_AXI_GP0_RREADY),
        .S00_AXI_rresp(processing_system7_0_M_AXI_GP0_RRESP),
        .S00_AXI_rvalid(processing_system7_0_M_AXI_GP0_RVALID),
        .S00_AXI_wdata(processing_system7_0_M_AXI_GP0_WDATA),
        .S00_AXI_wid(processing_system7_0_M_AXI_GP0_WID),
        .S00_AXI_wlast(processing_system7_0_M_AXI_GP0_WLAST),
        .S00_AXI_wready(processing_system7_0_M_AXI_GP0_WREADY),
        .S00_AXI_wstrb(processing_system7_0_M_AXI_GP0_WSTRB),
        .S00_AXI_wvalid(processing_system7_0_M_AXI_GP0_WVALID),
        .aclk(processing_system7_0_FCLK_CLK0),
        .aresetn(rst_ps7_0_50M_peripheral_aresetn));
  system_blk_mem_gen_0_0 blk_mem_gen_0
       (.addra({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,axi_bram_ctrl_0_BRAM_PORTA_ADDR}),
        .addrb(laser_tx_core_0_BRAM_PORTB_ADDR),
        .clka(axi_bram_ctrl_0_BRAM_PORTA_CLK),
        .clkb(laser_tx_core_0_BRAM_PORTB_CLK),
        .dina(axi_bram_ctrl_0_BRAM_PORTA_DIN),
        .dinb(laser_tx_core_0_BRAM_PORTB_DIN),
        .douta(axi_bram_ctrl_0_BRAM_PORTA_DOUT),
        .doutb(laser_tx_core_0_BRAM_PORTB_DOUT),
        .ena(axi_bram_ctrl_0_BRAM_PORTA_EN),
        .enb(laser_tx_core_0_BRAM_PORTB_EN),
        .rsta(axi_bram_ctrl_0_BRAM_PORTA_RST),
        .rstb(laser_tx_core_0_BRAM_PORTB_RST),
        .wea(axi_bram_ctrl_0_BRAM_PORTA_WE),
        .web(laser_tx_core_0_BRAM_PORTB_WE));
  system_ila_laser_axi_cfg_0 ila_laser_axi_cfg
       (.clk(processing_system7_0_FCLK_CLK0),
        .probe0(axi_gpio_0_gpio_io_o),
        .probe1(laser_tx_core_0_gpio_status),
        .probe10(dbg_rate_error_code_1),
        .probe11(dbg_gt_drp_write_attempted_1),
        .probe12(dbg_mmcm_drp_write_attempted_1),
        .probe13(dbg_gt_drp_busy_1),
        .probe14(dbg_gt_drp_done_1),
        .probe15(dbg_gt_drp_error_1),
        .probe16(dbg_mmcm_drp_busy_1),
        .probe17(dbg_mmcm_drp_done_1),
        .probe18(dbg_mmcm_drp_error_1),
        .probe19(dbg_txusrclk2_alive_axi_1),
        .probe2(laser_tx_core_0_dbg_bram_en),
        .probe20(dbg_txusrclk2_freq_counter_axi_1),
        .probe21(dbg_tx_quiesce_req_1),
        .probe22(dbg_tx_idle_seen_1),
        .probe23(dbg_apply_enable_blocked_1),
        .probe24(dbg_tx_mmcm_reset_wizard_1),
        .probe25(dbg_tx_mmcm_reset_rate_1),
        .probe26(dbg_tx_mmcm_reset_1),
        .probe27(dbg_tx_mmcm_locked_raw_1),
        .probe28(dbg_tx_mmcm_locked_sync_1),
        .probe29(dbg_rate_gt_tx_reset_1),
        .probe3(laser_tx_core_0_dbg_bram_addr),
        .probe30(dbg_gt0_gttxreset_effective_1),
        .probe31(dbg_rate_txuserrdy_block_1),
        .probe32(dbg_gt0_txuserrdy_effective_1),
        .probe33(dbg_txresetdone_sync_1),
        .probe34(dbg_gt_ready_1),
        .probe35(dbg_mmcm_drp_addr_1),
        .probe36(dbg_mmcm_drp_di_1),
        .probe37(dbg_mmcm_drp_do_1),
        .probe38(dbg_mmcm_drp_en_1),
        .probe39(dbg_mmcm_drp_we_1),
        .probe4(laser_tx_core_0_dbg_bram_dout),
        .probe40(dbg_mmcm_drp_rdy_1),
        .probe41(dbg_gt_drp_addr_1),
        .probe42(dbg_gt_drp_di_1),
        .probe43(dbg_gt_drp_do_1),
        .probe44(dbg_gt_drp_en_1),
        .probe45(dbg_gt_drp_we_1),
        .probe46(dbg_gt_drp_rdy_1),
        .probe47(dbg_gt_drp_readback_value_1),
        .probe48(dbg_txoutclk_alive_axi_1),
        .probe49(dbg_timeout_count_1),
        .probe5(laser_tx_core_0_dbg_bram_rst),
        .probe6(dbg_rate_state_1),
        .probe7(dbg_target_rate_mbps_1),
        .probe8(dbg_current_rate_mbps_1),
        .probe9(dbg_rate_error_1));
  system_ila_laser_tx_0 ila_laser_tx
       (.clk(txusrclk2_1),
        .probe0(laser_tx_core_0_txdata),
        .probe1(laser_tx_core_0_valid_mask),
        .probe10(laser_tx_core_0_dbg_phase_offset_tx),
        .probe11(laser_tx_core_0_dbg_current_state_tx),
        .probe12(laser_tx_core_0_dbg_cfg_update_pulse_tx),
        .probe13(laser_tx_core_0_dbg_pattern_valid_tx),
        .probe14(laser_tx_core_0_dbg_engine_start_tx),
        .probe2(laser_tx_core_0_eom_out),
        .probe3(laser_tx_core_0_soa_gate_out),
        .probe4(laser_tx_core_0_acq_trig_out),
        .probe5(laser_tx_core_0_acq_gate_out),
        .probe6(laser_tx_core_0_dbg_busy_tx),
        .probe7(laser_tx_core_0_dbg_done_tx),
        .probe8(laser_tx_core_0_dbg_phase_active_tx),
        .probe9(laser_tx_core_0_dbg_phase_start_pulse_tx));
  system_laser_tx_core_0_0 laser_tx_core_0
       (.acq_gate_out(laser_tx_core_0_acq_gate_out),
        .acq_trig_out(laser_tx_core_0_acq_trig_out),
        .axi_clk(processing_system7_0_FCLK_CLK0),
        .axi_rstn(rst_ps7_0_50M_peripheral_aresetn),
        .bram_addr(laser_tx_core_0_BRAM_PORTB_ADDR),
        .bram_clk(laser_tx_core_0_BRAM_PORTB_CLK),
        .bram_din(laser_tx_core_0_BRAM_PORTB_DIN),
        .bram_dout(laser_tx_core_0_BRAM_PORTB_DOUT),
        .bram_en(laser_tx_core_0_BRAM_PORTB_EN),
        .bram_rst(laser_tx_core_0_BRAM_PORTB_RST),
        .bram_we(laser_tx_core_0_BRAM_PORTB_WE),
        .dbg_bram_addr(laser_tx_core_0_dbg_bram_addr),
        .dbg_bram_dout(laser_tx_core_0_dbg_bram_dout),
        .dbg_bram_en(laser_tx_core_0_dbg_bram_en),
        .dbg_bram_rst(laser_tx_core_0_dbg_bram_rst),
        .dbg_busy_tx(laser_tx_core_0_dbg_busy_tx),
        .dbg_cfg_update_pulse_tx(laser_tx_core_0_dbg_cfg_update_pulse_tx),
        .dbg_current_state_tx(laser_tx_core_0_dbg_current_state_tx),
        .dbg_done_tx(laser_tx_core_0_dbg_done_tx),
        .dbg_engine_start_tx(laser_tx_core_0_dbg_engine_start_tx),
        .dbg_pattern_valid_tx(laser_tx_core_0_dbg_pattern_valid_tx),
        .dbg_phase_active_tx(laser_tx_core_0_dbg_phase_active_tx),
        .dbg_phase_offset_tx(laser_tx_core_0_dbg_phase_offset_tx),
        .dbg_phase_start_pulse_tx(laser_tx_core_0_dbg_phase_start_pulse_tx),
        .eom_out(laser_tx_core_0_eom_out),
        .gpio_ctrl(axi_gpio_0_gpio_io_o),
        .gpio_status(laser_tx_core_0_gpio_status),
        .gt_ready(gt_ready_1),
        .soa_gate_out(laser_tx_core_0_soa_gate_out),
        .tx_rst(tx_rst_1),
        .txdata(laser_tx_core_0_txdata),
        .txusrclk2(txusrclk2_1),
        .valid_mask(laser_tx_core_0_valid_mask));
  (* BMM_INFO_PROCESSOR = "arm > system axi_bram_ctrl_0" *) 
  (* KEEP_HIERARCHY = "yes" *) 
  system_processing_system7_0_0 processing_system7_0
       (.DDR_Addr(DDR_addr[14:0]),
        .DDR_BankAddr(DDR_ba[2:0]),
        .DDR_CAS_n(DDR_cas_n),
        .DDR_CKE(DDR_cke),
        .DDR_CS_n(DDR_cs_n),
        .DDR_Clk(DDR_ck_p),
        .DDR_Clk_n(DDR_ck_n),
        .DDR_DM(DDR_dm[3:0]),
        .DDR_DQ(DDR_dq[31:0]),
        .DDR_DQS(DDR_dqs_p[3:0]),
        .DDR_DQS_n(DDR_dqs_n[3:0]),
        .DDR_DRSTB(DDR_reset_n),
        .DDR_ODT(DDR_odt),
        .DDR_RAS_n(DDR_ras_n),
        .DDR_VRN(FIXED_IO_ddr_vrn),
        .DDR_VRP(FIXED_IO_ddr_vrp),
        .DDR_WEB(DDR_we_n),
        .FCLK_CLK0(processing_system7_0_FCLK_CLK0),
        .FCLK_RESET0_N(processing_system7_0_FCLK_RESET0_N),
        .MIO(FIXED_IO_mio[53:0]),
        .M_AXI_GP0_ACLK(processing_system7_0_FCLK_CLK0),
        .M_AXI_GP0_ARADDR(processing_system7_0_M_AXI_GP0_ARADDR),
        .M_AXI_GP0_ARBURST(processing_system7_0_M_AXI_GP0_ARBURST),
        .M_AXI_GP0_ARCACHE(processing_system7_0_M_AXI_GP0_ARCACHE),
        .M_AXI_GP0_ARID(processing_system7_0_M_AXI_GP0_ARID),
        .M_AXI_GP0_ARLEN(processing_system7_0_M_AXI_GP0_ARLEN),
        .M_AXI_GP0_ARLOCK(processing_system7_0_M_AXI_GP0_ARLOCK),
        .M_AXI_GP0_ARPROT(processing_system7_0_M_AXI_GP0_ARPROT),
        .M_AXI_GP0_ARQOS(processing_system7_0_M_AXI_GP0_ARQOS),
        .M_AXI_GP0_ARREADY(processing_system7_0_M_AXI_GP0_ARREADY),
        .M_AXI_GP0_ARSIZE(processing_system7_0_M_AXI_GP0_ARSIZE),
        .M_AXI_GP0_ARVALID(processing_system7_0_M_AXI_GP0_ARVALID),
        .M_AXI_GP0_AWADDR(processing_system7_0_M_AXI_GP0_AWADDR),
        .M_AXI_GP0_AWBURST(processing_system7_0_M_AXI_GP0_AWBURST),
        .M_AXI_GP0_AWCACHE(processing_system7_0_M_AXI_GP0_AWCACHE),
        .M_AXI_GP0_AWID(processing_system7_0_M_AXI_GP0_AWID),
        .M_AXI_GP0_AWLEN(processing_system7_0_M_AXI_GP0_AWLEN),
        .M_AXI_GP0_AWLOCK(processing_system7_0_M_AXI_GP0_AWLOCK),
        .M_AXI_GP0_AWPROT(processing_system7_0_M_AXI_GP0_AWPROT),
        .M_AXI_GP0_AWQOS(processing_system7_0_M_AXI_GP0_AWQOS),
        .M_AXI_GP0_AWREADY(processing_system7_0_M_AXI_GP0_AWREADY),
        .M_AXI_GP0_AWSIZE(processing_system7_0_M_AXI_GP0_AWSIZE),
        .M_AXI_GP0_AWVALID(processing_system7_0_M_AXI_GP0_AWVALID),
        .M_AXI_GP0_BID(processing_system7_0_M_AXI_GP0_BID),
        .M_AXI_GP0_BREADY(processing_system7_0_M_AXI_GP0_BREADY),
        .M_AXI_GP0_BRESP(processing_system7_0_M_AXI_GP0_BRESP),
        .M_AXI_GP0_BVALID(processing_system7_0_M_AXI_GP0_BVALID),
        .M_AXI_GP0_RDATA(processing_system7_0_M_AXI_GP0_RDATA),
        .M_AXI_GP0_RID(processing_system7_0_M_AXI_GP0_RID),
        .M_AXI_GP0_RLAST(processing_system7_0_M_AXI_GP0_RLAST),
        .M_AXI_GP0_RREADY(processing_system7_0_M_AXI_GP0_RREADY),
        .M_AXI_GP0_RRESP(processing_system7_0_M_AXI_GP0_RRESP),
        .M_AXI_GP0_RVALID(processing_system7_0_M_AXI_GP0_RVALID),
        .M_AXI_GP0_WDATA(processing_system7_0_M_AXI_GP0_WDATA),
        .M_AXI_GP0_WID(processing_system7_0_M_AXI_GP0_WID),
        .M_AXI_GP0_WLAST(processing_system7_0_M_AXI_GP0_WLAST),
        .M_AXI_GP0_WREADY(processing_system7_0_M_AXI_GP0_WREADY),
        .M_AXI_GP0_WSTRB(processing_system7_0_M_AXI_GP0_WSTRB),
        .M_AXI_GP0_WVALID(processing_system7_0_M_AXI_GP0_WVALID),
        .PS_CLK(FIXED_IO_ps_clk),
        .PS_PORB(FIXED_IO_ps_porb),
        .PS_SRSTB(FIXED_IO_ps_srstb),
        .SPI1_MISO_I(processing_system7_0_SPI_1_IO1_I),
        .SPI1_MISO_O(processing_system7_0_SPI_1_IO1_O),
        .SPI1_MISO_T(processing_system7_0_SPI_1_IO1_T),
        .SPI1_MOSI_I(processing_system7_0_SPI_1_IO0_I),
        .SPI1_MOSI_O(processing_system7_0_SPI_1_IO0_O),
        .SPI1_MOSI_T(processing_system7_0_SPI_1_IO0_T),
        .SPI1_SCLK_I(processing_system7_0_SPI_1_SCK_I),
        .SPI1_SCLK_O(processing_system7_0_SPI_1_SCK_O),
        .SPI1_SCLK_T(processing_system7_0_SPI_1_SCK_T),
        .SPI1_SS1_O(processing_system7_0_SPI_1_SS1_O),
        .SPI1_SS2_O(processing_system7_0_SPI_1_SS2_O),
        .SPI1_SS_I(processing_system7_0_SPI_1_SS_I),
        .SPI1_SS_O(processing_system7_0_SPI_1_SS_O),
        .SPI1_SS_T(processing_system7_0_SPI_1_SS_T),
        .USB0_VBUS_PWRFAULT(1'b0));
  system_rst_ps7_0_50M_0 rst_ps7_0_50M
       (.aux_reset_in(1'b1),
        .dcm_locked(1'b1),
        .ext_reset_in(processing_system7_0_FCLK_RESET0_N),
        .mb_debug_sys_rst(1'b0),
        .peripheral_aresetn(rst_ps7_0_50M_peripheral_aresetn),
        .peripheral_reset(rst_ps7_0_50M_peripheral_reset),
        .slowest_sync_clk(processing_system7_0_FCLK_CLK0));
endmodule

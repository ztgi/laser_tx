# 当前 impl_1 ILA probe 信号清单

## 1. 导出来源

本报告只基于当前 Vivado implemented design `impl_1` 的 debug core 报告整理，不修改 RTL、BD、XDC、Vitis，也不重新综合/实现。

执行的 Vivado Tcl 流程：

```tcl
open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
open_run impl_1
get_debug_cores
report_debug_core -file D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_core_probe_list.rpt
```

原始报告路径：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_core_probe_list.rpt
```

## 2. 当前 debug core 总览

当前 `impl_1` 中 `get_debug_cores` 对应的 debug core 为：

```text
dbg_hub
u_system_wrapper/system_i/ila_laser_axi_cfg
u_system_wrapper/system_i/ila_laser_tx
```

因此当前 bit 中存在：

```text
1 个 debug hub
2 个 ILA
```

需要特别注意：

```text
dbg_hub/clk = gt_txusrclk2
```

也就是说，当前 debug hub 仍然依赖 `gt_txusrclk2`。如果 GT/MMCM/txusrclk2 不稳定，Hardware Manager 可能出现 debug hub 检测失败或 waveform upload 异常。

## 3. 是否删除了内部信号和控制链路 ILA

结论：

```text
没有看到“基础控制链路 ILA 被全部删除”的证据。
```

当前仍然存在：

```text
ila_laser_axi_cfg：AXI/FCLK/gt_ctrl_clk 域配置侧 ILA
ila_laser_tx：txusrclk2 域发送侧 ILA
```

其中 `ila_laser_tx` 仍包含：

```text
txdata[63:0]
valid_mask[63:0]
eom_out
soa_gate_out
acq_trig_out
acq_gate_out
dbg_busy_tx
dbg_done_tx
dbg_phase_active_tx
dbg_phase_start_pulse_tx
dbg_phase_offset_tx[7:0]
dbg_current_state_tx[7:0]
dbg_cfg_update_pulse_tx
dbg_pattern_valid_tx
dbg_engine_start_tx
```

但是，如果期望看到前期 1000M bring-up / dynamic rate controller 的 AXI debug 信号，例如：

```text
rate_state
target_rate
current_rate
rate_error_code
gt_drp_write_attempted
mmcm_drp_write_attempted
txusrclk2_freq_counter_axi
ila_1000m_bringup_axi
```

当前 `impl_1` 的 `report_debug_core` 中没有独立的 `ila_1000m_bringup_axi` debug core；这些信号没有作为当前 implemented bit 的独立 AXI bring-up ILA probe 出现在报告中。Vivado GUI 的 Set Up Debug 页面中显示的 nets 是“候选可加入 debug 的 nets”，不等于当前 bit/LTX 中已经存在的 ILA probe。

## 4. ILA probe 表

| ILA 名称 | ILA clock | probe 编号 | probe 信号名 | 位宽 | 所属时钟域 | 用途说明 |
|---|---|---:|---|---:|---|---|
| `dbg_hub` | `gt_txusrclk2` | N/A | debug hub clock | 1 | `txusrclk2` / GT TX user clock | Vivado debug hub 时钟。当前依赖 GT TX user clock，不是稳定 PS/FCLK。 |
| `ila_laser_axi_cfg` | `gt_ctrl_clk` | `probe0` | `axi_gpio_0_gpio_io_o[31:0]` | 32 | AXI/FCLK / `gt_ctrl_clk` | 观察 PS/AXI GPIO 输出控制字，包括 APPLY/ENABLE/RESET/control bit。 |
| `ila_laser_axi_cfg` | `gt_ctrl_clk` | `probe1` | `laser_tx_core_0_gpio_status[31:0]` | 32 | AXI/FCLK / `gt_ctrl_clk` | 观察 PL 返回给 AXI GPIO status 的状态字。 |
| `ila_laser_axi_cfg` | `gt_ctrl_clk` | `probe2` | `laser_tx_core_0_dbg_bram_en` | 1 | AXI/FCLK / `gt_ctrl_clk` | 观察 PL 侧 BRAM 读取使能。 |
| `ila_laser_axi_cfg` | `gt_ctrl_clk` | `probe3` | `laser_tx_core_0_dbg_bram_addr[31:0]` | 32 | AXI/FCLK / `gt_ctrl_clk` | 观察 PL 侧 BRAM 读取地址。 |
| `ila_laser_axi_cfg` | `gt_ctrl_clk` | `probe4` | `laser_tx_core_0_dbg_bram_dout[31:0]` | 32 | AXI/FCLK / `gt_ctrl_clk` | 观察从 BRAM 读出的配置数据。 |
| `ila_laser_axi_cfg` | `gt_ctrl_clk` | `probe5` | `laser_tx_core_0_dbg_bram_rst` | 1 | AXI/FCLK / `gt_ctrl_clk` | 观察 BRAM/debug 侧复位状态。 |
| `ila_laser_tx` | `txusrclk2` | `probe0` | `laser_tx_core_0_txdata[63:0]` | 64 | `txusrclk2` | 观察发送到 GT TXDATA 的 64-bit 数据。 |
| `ila_laser_tx` | `txusrclk2` | `probe1` | `laser_tx_core_0_valid_mask[63:0]` | 64 | `txusrclk2` | 观察每个 TX word 中有效 bit mask。 |
| `ila_laser_tx` | `txusrclk2` | `probe2` | `laser_tx_core_0_eom_out` | 1 | `txusrclk2` | 观察 EOM 外部同步输出。 |
| `ila_laser_tx` | `txusrclk2` | `probe3` | `laser_tx_core_0_soa_gate_out` | 1 | `txusrclk2` | 观察 SOA gate 外部同步输出。 |
| `ila_laser_tx` | `txusrclk2` | `probe4` | `laser_tx_core_0_acq_trig_out` | 1 | `txusrclk2` | 观察采集触发输出。 |
| `ila_laser_tx` | `txusrclk2` | `probe5` | `laser_tx_core_0_acq_gate_out` | 1 | `txusrclk2` | 观察采集 gate 输出。 |
| `ila_laser_tx` | `txusrclk2` | `probe6` | `laser_tx_core_0_dbg_busy_tx` | 1 | `txusrclk2` | 观察发送引擎 busy 状态。 |
| `ila_laser_tx` | `txusrclk2` | `probe7` | `laser_tx_core_0_dbg_done_tx` | 1 | `txusrclk2` | 观察发送序列完成状态。 |
| `ila_laser_tx` | `txusrclk2` | `probe8` | `laser_tx_core_0_dbg_phase_active_tx` | 1 | `txusrclk2` | 观察 phase/gap/pattern 调度活动状态。 |
| `ila_laser_tx` | `txusrclk2` | `probe9` | `laser_tx_core_0_dbg_phase_start_pulse_tx` | 1 | `txusrclk2` | 观察 phase start 事件。 |
| `ila_laser_tx` | `txusrclk2` | `probe10` | `laser_tx_core_0_dbg_phase_offset_tx[7:0]` | 8 | `txusrclk2` | 观察 phase offset 调试值。 |
| `ila_laser_tx` | `txusrclk2` | `probe11` | `laser_tx_core_0_dbg_current_state_tx[7:0]` | 8 | `txusrclk2` | 观察发送状态机当前状态。 |
| `ila_laser_tx` | `txusrclk2` | `probe12` | `laser_tx_core_0_dbg_cfg_update_pulse_tx` | 1 | `txusrclk2` | 观察 APPLY/cfg_update 是否进入 TX 域。 |
| `ila_laser_tx` | `txusrclk2` | `probe13` | `laser_tx_core_0_dbg_pattern_valid_tx` | 1 | `txusrclk2` | 观察配置校验后 pattern 是否有效。 |
| `ila_laser_tx` | `txusrclk2` | `probe14` | `laser_tx_core_0_dbg_engine_start_tx` | 1 | `txusrclk2` | 观察 ENABLE 后发送引擎启动事件。 |

## 5. AXI/FCLK 域与 txusrclk2 域区分

### 5.1 AXI/FCLK 域 ILA

```text
ILA 名称：ila_laser_axi_cfg
Clock：gt_ctrl_clk
主要用途：PS/AXI GPIO 控制、status、BRAM 配置读取链路
```

它适合观察：

```text
PS 是否写 GPIO；
gpio_status 是否变化；
BRAM 配置读取是否发生；
BRAM 地址和数据是否符合预期。
```

### 5.2 txusrclk2 域 ILA

```text
ILA 名称：ila_laser_tx
Clock：txusrclk2
主要用途：发送状态机、txdata/valid_mask、外部同步输出
```

它适合观察：

```text
cfg_update_pulse_tx；
engine_start_tx；
busy/done；
current_state_tx；
txdata；
valid_mask；
eom/soa/acq 输出。
```

### 5.3 当前未看到的独立 AXI bring-up/rate ILA

当前 `impl_1` 的 debug core 报告中没有看到：

```text
ila_1000m_bringup_axi
ila_dynamic_rate_axi
```

也没有看到 `rate_state/current_rate/target_rate/error_code` 这组动态切换控制信号作为当前 ILA probe 列出。若需要这些信号上板观察，需要后续在不破坏现有功能的前提下重新规划 debug 结构并重新实现；本轮未做该修改。

## 6. 本轮结论

1. 当前 `impl_1` 中基础控制链路 ILA 没有被全部删除。
2. 当前 `impl_1` 中存在两个 ILA：
   - `ila_laser_axi_cfg`：AXI/FCLK / `gt_ctrl_clk` 域；
   - `ila_laser_tx`：`txusrclk2` 域。
3. `ila_laser_tx` 中仍保留 `txdata/valid_mask/engine_start/busy/done/current_state/cfg_update` 等发送侧关键 probe。
4. 当前没有独立的 `ila_1000m_bringup_axi` 或 rate controller AXI ILA 出现在 debug core 报告中。
5. `dbg_hub/clk` 当前接在 `gt_txusrclk2`，这仍是 Hardware Manager 识别稳定性的风险点。


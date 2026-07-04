# 1000M Profile1 static AXI/FCLK bring-up ILA 修复报告

## 1. 本轮问题现象

1000M Profile1 static bitstream 已能 Program FPGA，但在 Vivado Hardware Manager 中对 `hw_ila_3` 执行 `trigger_now` 后出现 waveform upload corrupted。已有自检显示现有 `dbg_hub/clk` 接到 `gt_txusrclk2`，而 `gt_txusrclk2` 依赖 GT TXOUTCLK 与 TX MMCM lock。

该结构不适合作为 1000M static bring-up 的首要 debug 结构：当 GT/MMCM/txusrclk2 尚未稳定时，debug hub 本身也可能不稳定，Vivado Hardware Manager 的 arm / trigger / upload 行为就会受到影响。

## 2. 当前已通过的层级

- 短路径完整 1000M static build 已完成。
- `write_bitstream` 已完成。
- bit / ltx 已重新生成并归档。
- timing summary 显示 all user specified timing constraints are met。
- implemented netlist 检查显示：
  - `dbg_hub/clk` 接到 `gt_ctrl_clk`，其 clock 为 `clk_fpga_0`；
  - `ila_1000m_bringup_axi/clk` 接到 `gt_ctrl_clk`，其 clock 为 `clk_fpga_0`。
- 本轮新增 AXI/FCLK bring-up ILA 上板截图证据，已确认：
  - GT/MMCM ready；
  - `txusrclk2_alive_axi` 有效；
  - UDP/AXI GPIO 发出的 `APPLY` 能进入 PL 并触发 `cfg_update_seen`；
  - UDP/AXI GPIO 发出的 `ENABLE` 能进入 PL 并触发 `engine_start_seen`。

## 3. 当前未通过的层级

- 本轮只覆盖 AXI/FCLK bring-up ILA 层面的状态与控制链路验证。
- 本报告不声明 1000M 外部光口链路闭环通过。
- 本报告不声明 txusrclk2 域 `txdata[63:0] / valid_mask[63:0]` 已由本轮新增截图再次验证。
- 本报告不声明 UDP、动态 rate set、GTX DRP 或 MMCM DRP 已实现。

## 4. 根因判断

原 debug hub 依赖 `txusrclk2`。`txusrclk2` 是由 GT TXOUTCLK 和 TX user-clock MMCM 产生的发送域时钟。1000M bring-up 早期正需要确认 CPLL lock、TX MMCM lock、TX reset done、GT ready 和 txusrclk2 alive 等状态，如果 debug hub 也依赖被观察对象本身，就会形成“调试基础设施依赖待调试时钟”的问题。

因此本轮修复方向是：把 debug hub 和首要 bring-up ILA 移到稳定 AXI/FCLK 域，以便即使 `txusrclk2` 不稳定，也能先观察 AXI 域同步后的 GT 状态、GPIO 控制和 txusrclk2 alive/frequency 证据。

## 5. 本轮修改内容

### 5.1 `laser_gt_tx_profile1_1000m.v`

新增 debug-only AXI/FCLK 域观测逻辑：

- `txusrclk2_counter_tx`：在 `txusrclk2` 域自由运行；
- `txusrclk2_counter_gray_tx`：将 txusrclk2 counter 转为 Gray code；
- `txusrclk2_counter_gray_meta_axi / txusrclk2_counter_gray_sync_axi`：在 `ctrl_clk / gt_ctrl_clk` 域进行两级同步；
- `txusrclk2_freq_counter_axi`：在 AXI/FCLK 域将同步后的 Gray counter 转回 binary；
- `txusrclk2_toggle_axi`：同步 `txusrclk2_counter_tx[8]`，作为低速跳变观察；
- `txusrclk2_alive_axi`：比较 AXI 域 counter 是否变化，形成 alive 标志。

这些逻辑只用于 bring-up debug，不参与 GT TX data、reset、ready 或业务发送状态机决策。

### 5.2 `laser_tx_core.v`

新增 debug-only AXI 域状态：

- `dbg_axi_gpio_ctrl[31:0]`
- `dbg_axi_apply_toggle`
- `dbg_axi_enable`
- `dbg_axi_soft_reset`
- `dbg_axi_cfg_valid`
- `dbg_axi_cfg_error`
- `dbg_axi_busy_tx`
- `dbg_axi_done_tx`
- `dbg_axi_pattern_valid`
- `dbg_axi_cfg_update_seen`
- `dbg_axi_engine_start_seen`

其中 `engine_start` 是 txusrclk2 域事件，采用 tx 域 toggle + `cdc_toggle_sync` 同步回 AXI/FCLK 域，再在 AXI 域锁存为 sticky seen flag。`cfg_update_seen` 基于 AXI 域配置 toggle 变化锁存。

### 5.3 `gt_profile1_1000m_axi_bringup_debug.tcl`

新增实现前 hook 中的 debug 插入：

- 强制 `dbg_hub/clk` 连接到 `gt_ctrl_clk / clk_fpga_0`；
- 创建 `ila_1000m_bringup_axi`；
- `ila_1000m_bringup_axi/clk` 连接到 `gt_ctrl_clk / clk_fpga_0`；
- 接入 18 个 AXI/FCLK 域 probe。

### 5.4 `gt_profile1_1000m_impl_pre.tcl`

在原 1000M Profile1 clock period 检查和 AXI/TX 异步 clock group 约束后，调用 `gt_profile1_1000m_axi_bringup_debug.tcl`。

### 5.5 `build_gt_profile1_1000m_static.tcl`

为避免 Windows 260 字符路径限制，将 1000M static 的临时复制工程移到短路径：

```text
D:/FPGA_Learn/laser_tx/_p1_1g_vivado/p1.xpr
```

最终 bit / ltx / reports 仍归档到：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/
```

同时在复制工程中重新生成 BD output products，使 module reference 的 `laser_tx_core` DCP 包含本轮新增 debug-only RTL。

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| debug hub clock | `gt_txusrclk2` | `gt_ctrl_clk / clk_fpga_0` | debug hub 不再依赖 GT/MMCM/txusrclk2 |
| bring-up 首要 ILA | 主要依赖 txusrclk2 域 ILA | 新增 AXI/FCLK 域 `ila_1000m_bringup_axi` | GT 未完全稳定时也可先看状态 |
| txusrclk2 alive 判断 | 无 AXI 域证据 | Gray counter CDC + alive flag | 可在 AXI ILA 中判断 txusrclk2 是否在跑 |
| engine_start 观测 | txusrclk2 域 pulse | tx toggle + AXI sticky seen | 避免直接跨域接单拍 pulse |
| build 工作路径 | `reports/.../vivado_project/laser_tx_profile1_1000m.xpr` | `_p1_1g_vivado/p1.xpr` | 避免 Vivado debug IP 生成路径超过 Windows 260 字符 |
| BD output products | 可能沿用旧 module reference DCP | 复制工程内 reset/generate `system.bd` | 确保 debug-only RTL 进入综合/实现 |
| 业务逻辑 | 不变 | 不变 | 未改变发送数据路径、BRAM 格式、UDP 协议 |

## 7. AXI/FCLK 域 ILA probe 列表

`ila_1000m_bringup_axi` 的 cell path / CELL_NAME：

```text
ila_1000m_bringup_axi
```

probe 列表：

| Probe | Width | 信号 |
|---|---:|---|
| probe0 | 1 | `cplllock_axi` / `u_laser_gt_tx_profile1_1000m/cplllock_sync` |
| probe1 | 1 | `txresetdone_axi` / `u_laser_gt_tx_profile1_1000m/txresetdone_sync` |
| probe2 | 1 | `tx_mmcm_locked_axi` / `u_laser_gt_tx_profile1_1000m/tx_mmcm_locked_sync` |
| probe3 | 1 | `gt_ready_axi` / `u_laser_gt_tx_profile1_1000m/gt_ready_ctrl` |
| probe4 | 1 | `txusrclk2_alive_axi` |
| probe5 | 1 | `txusrclk2_toggle_axi` |
| probe6 | 32 | `txusrclk2_freq_counter_axi[31:0]` |
| probe7 | 32 | `gpio_ctrl_axi[31:0]` / `axi_gpio_0_gpio_io_o[31:0]` |
| probe8 | 1 | `gpio_apply_toggle_axi` / GPIO bit 8 |
| probe9 | 1 | `gpio_enable_axi` / GPIO bit 9 |
| probe10 | 1 | `gpio_soft_reset_axi` / GPIO bit 10 |
| probe11 | 1 | `cfg_valid_axi` |
| probe12 | 1 | `cfg_error_axi` |
| probe13 | 1 | `busy_tx_axi` |
| probe14 | 1 | `done_tx_axi` |
| probe15 | 1 | `cfg_update_seen_axi` |
| probe16 | 1 | `engine_start_seen_axi` |
| probe17 | 1 | `pattern_valid_axi` |

## 8. CDC 方法说明

- `cplllock / txresetdone / tx_mmcm_locked / gt_ready`：通过 1000M GT wrapper 中已有的 AXI/FCLK 域同步或稳定状态寄存后接入 AXI ILA。
- `txusrclk2_freq_counter_axi`：txusrclk2 域 counter 先转 Gray code，再经 AXI/FCLK 域两级同步，最后在 AXI/FCLK 域转回 binary。
- `txusrclk2_toggle_axi`：使用两级同步将 txusrclk2 域低速 toggle 同步到 AXI/FCLK 域。
- `txusrclk2_alive_axi`：在 AXI/FCLK 域比较同步后的 counter 是否变化并形成 alive flag。
- `engine_start_seen_axi`：txusrclk2 域 `engine_start` 事件先 toggle，再通过 `cdc_toggle_sync` 同步到 AXI/FCLK 域并锁存。
- `cfg_update_seen_axi`：在 AXI/FCLK 域根据 apply/config toggle 变化锁存。

没有把 `txdata[63:0] / valid_mask[63:0]` 直接跨到 AXI ILA 中作为主 bring-up 观测对象；它们仍应在 txusrclk2 稳定后由 txusrclk2 域 ILA 观察。

## 9. 构建验证记录

执行命令：

```powershell
& 'D:\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'D:\FPGA_Learn\laser_tx\scripts\build_gt_profile1_1000m_static.tcl'
```

结果：

```text
synth_1 status: synth_design Complete!
impl_1 status: write_bitstream Complete!
Bitgen Completed Successfully.
```

bit 路径：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
```

ltx 路径：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

timing summary：

```text
WNS = 7.029 ns
TNS = 0.000 ns
TNS failing endpoints = 0
WHS = 0.057 ns
THS = 0.000 ns
All user specified timing constraints are met.
```

## 10. Implemented debug 结构检查

检查报告：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/reports/axi_bringup_debug_implemented_check.rpt
```

关键结论：

```text
dbg_hub/clk nets=gt_ctrl_clk clocks=clk_fpga_0
ila_1000m_bringup_axi/clk nets=gt_ctrl_clk clocks=clk_fpga_0
```

因此本轮目标结果已满足：

```text
dbg_hub/clk = axi_clk / PS FCLK / gt_ctrl_clk
```

而不是：

```text
dbg_hub/clk = txusrclk2
```

## 11. Profile0 回退保护

构建脚本在构建前后均检查 Profile0 原始生成文件：

```text
laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v: TXOUT_DIV = 8
laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.xml: gt0_val_tx_line_rate = 0.5
laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.xml: gt0_val_cpll_txout_div = 8
```

本轮未覆盖当前 500M Profile0 XCI，也未改变 Profile0 回退路径。

## 12. 硬件接口一致性说明

本轮未修改：

```text
UDP 协议
动态 rate set
GTX DRP
MMCM DRP
AD9528
laser_tx_core 功能逻辑
BRAM 配置格式
500M Profile0 回退路径
GPIO / BRAM / GT status 地址
```

本轮只修改：

```text
RTL debug-only 信号
CDC 同步/事件锁存
ILA/debug hub 修复脚本
1000M static build 脚本
中文调试报告
```

## 13. 上板验证步骤

1. Vivado Hardware Manager 下载：
   - `D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit`
   - `D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx`
2. 确认 Hardware Manager 能识别 `ila_1000m_bringup_axi`。
3. 对 `ila_1000m_bringup_axi` 执行 `trigger_now`。
4. 确认 waveform 可以 upload。
5. 观察：
   - `cplllock_axi`
   - `tx_mmcm_locked_axi`
   - `txresetdone_axi`
   - `gt_ready_axi`
   - `txusrclk2_alive_axi`
   - `txusrclk2_freq_counter_axi`
6. 再运行 Vitis ELF。
7. 串口确认程序运行。
8. 通过 UDP 或 UART 发送 `WRITE_CONFIG / SELECT_CONFIG / APPLY / ENABLE`。
9. 在 AXI ILA 中先确认：
   - `gpio_apply_toggle_axi`
   - `gpio_enable_axi`
   - `cfg_update_seen_axi`
   - `engine_start_seen_axi`
10. 最后在 txusrclk2 域 ILA 中观察 `txdata / valid_mask`。

## 14. 1000M AXI/FCLK bring-up ILA 上板截图证据

本节归档用户本轮新增的 AXI/FCLK bring-up ILA 截图和 UDP 配置截图。图片位于：

```text
D:/FPGA_Learn/laser_tx/docs/images/
```

### 14.1 本次测试使用的 UDP 配置

UDP 配置命令截图：

![1000M UDP Direct127 gap8 repeat4 配置]()

本次 ILA 波形对应的 UDP 命令序列为：

```text
SOFT_RESET
WRITE_CONFIG 0 0x5A 4 8 2 7 0 0 0x89ABCDEF 0x01234567 0x76543210 0x52A55AA5
SELECT_CONFIG 0 1 1
APPLY
ENABLE
```

配置含义：

```text
index = 0
seed = 0x5A
repeat_cycles = 4
gap_len_bits = 8
insert_after = 2
prbs_order = 7
phase_shift_en = 0
loop_en = 0
direct_source = 1
direct_len_127 = 1
```

即：

```text
127bit direct pattern；
重复 4 次；
第 2 次 pattern 后插入 8bit gap；
不循环；
pattern = {pattern_top[30:0], pattern_high, pattern_mid, pattern_low}。
```

实际 pattern 字段：

```text
pattern_low  = 0x89ABCDEF
pattern_mid  = 0x01234567
pattern_high = 0x76543210
pattern_top  = 0x52A55AA5
```

### 14.2 APPLY 前：GT ready / txusrclk2 alive / idle

![APPLY 前 GT ready 与 txusrclk2 alive]()

图 1 对应 `SOFT_RESET + WRITE_CONFIG + SELECT_CONFIG` 后、`APPLY` 前。该图说明：

```text
GT/MMCM/txusrclk2 已经处于可工作状态；
cplllock_sync = 1；
txresetdone_sync = 1；
tx_mmcm_locked_sync = 1；
gt_ready_ctrl = 1；
txusrclk2_alive_axi = 1；
txusrclk2_freq_counter_axi 持续递增；
此时 BRAM 配置已写入并已选择 index=0/direct127，但尚未 APPLY，因此 PL 发送域尚未加载新配置。
```

### 14.3 APPLY 后：cfg_update_seen / cfg_valid / pattern_valid

![APPLY 后 cfg_update_seen]()

图 2 对应发送 `APPLY` 后。该图说明：

```text
APPLY toggle 已进入 PL；
dbg_axi_cfg_update_seen = 1；
dbg_axi_cfg_valid = 1；
dbg_axi_cfg_error = 0；
dbg_axi_pattern_valid = 1；
dbg_axi_engine_start_seen = 0。
```

结论：

```text
WRITE_CONFIG / SELECT_CONFIG / APPLY 控制链路有效；
配置已经被 PL 接收并校验通过；
因为尚未 ENABLE，所以 engine_start_seen = 0 是正常现象。
```

### 14.4 ENABLE 后：engine_start_seen

![ENABLE 后 engine_start_seen]()

图 3 对应发送 `ENABLE` 后。该图说明：

```text
GPIO enable bit 已置 1；
dbg_axi_engine_start_seen = 1；
dbg_axi_cfg_valid = 1；
dbg_axi_cfg_error = 0；
dbg_axi_pattern_valid = 1；
GT/MMCM/txusrclk2 状态仍保持正常。
```

结论：

```text
ENABLE 控制已经进入 PL；
laser_tx_core 的发送启动事件已经发生；
PS/UDP -> AXI GPIO -> PL -> txusrclk2 域发送启动链路有效。
```

若截图中 `busy_tx` 当前值为 0，不判定为失败。原因是本次配置 `loop_en=0`，且 direct127 repeat4 gap8 是有限短序列，发送窗口很短，ILA cursor 位置可能已经落在发送结束后。应理解为：

```text
busy_tx 为瞬态状态，当前 cursor 位置为 0 不影响 engine_start_seen=1 的启动链路结论。
```

### 14.5 与 txusrclk2 域 txdata / valid_mask 图的关系

已有 txusrclk2 域图片：

```text
ila_apply_config_update.png
ila_apply_with_txdata_validmask.png
ila_enable_engine_start.png
ila_enable_txdata_validmask.png
```

其中 `ila_enable_txdata_validmask2.png` 仅作为后续建议命名/待归档项，当前未检测到实际文件，不在本报告中作为已有截图证据引用。

这些图片用于说明 txusrclk2 域 `txdata / valid_mask / engine_start / pattern_valid` 的进一步观察。

本轮新增 3 张 AXI/FCLK 图用于说明：

```text
debug hub 已稳定；
GT/MMCM/txusrclk2 alive；
APPLY/ENABLE 控制事件确实进入 PL；
配置与启动链路在 AXI 侧可确认。
```

两类图的分层定位为：

```text
AXI/FCLK ILA：证明系统状态和控制链路；
txusrclk2 ILA：证明发送数据路径和 valid_mask 输出。
```

## 15. 当前结论

本轮完成了 1000M Profile1 static debug 结构修复：debug hub 和首要 bring-up ILA 均已改到稳定 AXI/FCLK 域；新增 AXI/FCLK 域 ILA 能观察 GT lock/reset/ready、txusrclk2 alive/frequency、GPIO 控制和跨域事件 seen flag。短路径完整 1000M static build 已通过，bit/LTX/timing/clock/debug 检查报告已生成。

结合本轮新增 AXI/FCLK ILA 截图，1000M Profile1 static 在 AXI/FCLK bring-up ILA 下已验证：

```text
GT/MMCM ready；
txusrclk2 alive；
APPLY 进入 PL；
配置校验通过；
ENABLE 进入 PL；
发送启动事件发生。
```

本报告不声明：

```text
1000M 动态调速已经实现；
GTX DRP/MMCM DRP 已完成；
外部光口链路已经闭环验证通过。
```

## 16. 风险与下一步建议

- 新增 AXI ILA 属于 bring-up debug 结构，会增加少量 debug 资源；后续产品化 bitstream 可移除或降低 depth。
- `txusrclk2_freq_counter_axi` 是 CDC 后的观测 counter，不是精密频率计；用于判断 txusrclk2 是否 alive 和大致增长。
- 下一步应在 txusrclk2 域 ILA 中继续观察 `txdata[63:0] / valid_mask[63:0]`，或结合已有 txusrclk2 图补充 1000M static 数据路径证据。
- 若 AXI ILA 稳定而 txusrclk2 域 ILA 仍异常，应继续围绕 GT/MMCM/reset/txusrclk2 本身排查，而不是回到 UDP/APPLY 逻辑。

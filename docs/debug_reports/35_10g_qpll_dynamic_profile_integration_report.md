# 10G QPLL dynamic profile 集成报告

## 1. 本阶段目标

本阶段目标是在已有 500M / 1000M / 1250M / 2000M / 2500M / 3125M / 5000M / 6250M CPLL dynamic profile 基线之上，加入一个固定的 10.000Gbps QPLL profile。

本轮使用内部 UDP status、AXI/FCLK ILA、TX domain ILA、QPLL lock/refclk-lost、GT/MMCM DRP readback 和 txusrclk2 frequency counter 作为 bring-up 依据；不增加外部示波器 GPIO。

## 2. 为什么示波器后移

实验室示波器当前不可用，而且普通 500MHz 示波器也不能证明 10Gb/s 串行眼图或 BER。因此本阶段先推进内部控制链路：QPLL static attributes、PLL source select、QPLL reset/lock/refclk-lost、GT channel DRP、MMCM DRP、VERIFY_RATE、UDP rate set/status。

Oscilloscope low-speed control/clock validation was not run.

## 3. 基线 commit

本阶段基于以下已完成提交继续：

| Commit | 内容 |
|---|---|
| `5403350` | Add QPLL wrapper architecture foundation |
| `b7cac81` | Harden Vitis rate completion checks |
| `c787251` | Guard rate requests while switching |
| `86223d4` | Track programmed CPLL DRP state |
| `5c1624e` | Confirm 10G QPLL parameters |
| `b39c2a6` | Configure QPLL common for 10G |
| `83fbe6b` | Add 10G MMCM DRP sequence |
| `a61e731` | Add QPLL PLL source state semantics |

## 4. 10G 参数来源

10G 参数以隔离 GT Wizard 参数包为主要依据：

```text
reports/qpll_10g_parameter_compare/10g_125m_qpll_n80/
```

采用参数：

| 项目 | 数值 |
|---|---:|
| Line rate | 10.000Gbps |
| MGT REFCLK | 125MHz |
| PLL | QPLL |
| QPLL_N / QPLL_FBDIV_TOP | 80 |
| QPLL_M / QPLL_REFCLK_DIV | 1 |
| QPLL_FBDIV encoding | `10'b0100100000` |
| QPLL_FBDIV_RATIO | `1'b1` |
| TXOUT_DIV | 1 |
| TXSYSCLKSEL | `2'b11` |
| TXOUTCLK | 312.5MHz |
| TXUSRCLK | 312.5MHz |
| TXUSRCLK2 | 156.25MHz |
| MMCM VCO | 625MHz |

## 5. 10.000G 与 10.3125G 区分

本轮加入的是 10.000Gbps，不是 10.3125Gbps。125MHz REFCLK 下采用 QPLL_N=80、M=1、TXOUT_DIV=1：

```text
125MHz × 80 / (1 × 1) = 10.000Gbps
```

当前没有使用 156.25MHz MGT REFCLK，也没有把 10.3125G 参数冒充为 10G。

## 6. QPLL 静态属性策略

当前工程只有一个 10G QPLL profile，因此本阶段不新增 QPLL DRP controller。QPLL COMMON 采用静态 attributes：

| GTXE2_COMMON 参数 | 数值 |
|---|---|
| `QPLL_FBDIV` | `10'b0100100000` |
| `QPLL_FBDIV_RATIO` | `1'b1` |
| `QPLL_REFCLK_DIV` | `1` |
| `QPLL_CFG` | `27'h0680181` |
| `QPLL_CP` | `10'b0000011111` |
| `QPLL_LPF` | `4'b1111` |
| `QPLL_LOCK_CFG` | `16'h21E8` |
| `QPLL_INIT_CFG` | `24'h000006` |
| `QPLL_CLKOUT_CFG` | `4'b0000` |

## 7. Profile table

新增 profile：

| 字段 | 10G profile |
|---|---|
| rate_id | `RATE_ID_10000M = 9` |
| rate_mbps | 10000 |
| refclk | 125MHz |
| pll_type | QPLL |
| qpll_required | 1 |
| QPLL_N | 80 |
| TXOUT_DIV | 1 |
| TXOUT_DIV encoding | `3'b000` |
| MMCM profile | `MMCM_DRP_SEQ_PROFILE8_10000M` |
| expected TXUSRCLK2 | 156.25MHz |
| freq counter window | `153000..159500` |
| AD9528 dynamic | 0 |

原有 CPLL profiles 仍保持 `PLL_TYPE_CPLL`。

## 8. PLL 状态语义

本轮新增/接入以下 PLL 状态语义：

| 状态 | 含义 |
|---|---|
| `target_pll_type` | 当前请求目标使用 CPLL 或 QPLL |
| `active_pll_type` | 最后一次通过 VERIFY_RATE 的 PLL 类型 |
| `programmed_pll_type` | 最近实际完成 PLL source 选择和 lock 流程的 PLL 类型 |
| `qpll_selected` | 送入 GT channel 的 QPLL source select 控制 |
| `rate_qpll_reset` | rate controller 控制的 QPLL reset |

`current_rate` 和 `active_pll_type` 仍只在 VERIFY_RATE 成功后更新。失败时保留 last-good 状态。

## 9. CPLL -> QPLL 状态序列

10G profile 进入路径复用现有 rate switch executor，并在 reset 已断言、TXUSERRDY 已关闭后切换 PLL source：

```text
QUIESCE_TX
ASSERT_RESET
select QPLL / assert-release QPLL reset
PROGRAM_GT_DRP
PROGRAM_MMCM_DRP
RELEASE_RESET
WAIT_MMCM_RESET_RELEASE
WAIT_LOCK(QPLL lock/refclk-lost + MMCM lock + txresetdone + gt_ready)
VERIFY_RATE
DONE / ERROR
```

## 10. QPLL -> CPLL 状态序列

回切 CPLL profile 时，目标 profile 的 `pll_type=CPLL`，`qpll_selected` 在 GTTXRESET 已断言、TXUSERRDY 已关闭期间切回 CPLL encoding。CPLL divider restore 仍沿用已修复的 programmed/active CPLL 语义：

```text
target_cpll_drp_value != programmed_cpll_drp_value
```

时执行 CPLL DRP，否则只写 TXOUT_DIV 和 MMCM DRP。

## 11. QPLL reset / lock / refclk lost

新增错误码：

| Error code | 含义 |
|---|---|
| `QPLL_LOCK_TIMEOUT` | QPLL 未在 timeout 内 lock |
| `QPLL_REFCLK_LOST` | QPLL refclk lost 置位 |

QPLL raw lock/refclk-lost 先同步到 `gt_ctrl_clk` 域，再参与状态机判断。没有使用常量伪造 QPLLLOCK。

## 12. GT channel DRP

10G profile 使用现有 GT channel DRP executor 写 TXOUT_DIV。10G 的 TXOUT_DIV=1，对应当前 DRP encoding `3'b000`。本轮没有新增 QPLL DRP。

## 13. MMCM DRP

新增 `MMCM_DRP_SEQ_PROFILE8_10000M`，目标：

| 项目 | 数值 |
|---|---:|
| MMCM input | TXOUTCLK 312.5MHz |
| CLKIN period | 3.2ns |
| CLKFBOUT_MULT | 2.0 |
| DIVCLK_DIVIDE | 1 |
| CLKOUT1_DIVIDE | 2 |
| CLKOUT0_DIVIDE | 4 |
| TXUSRCLK | 312.5MHz |
| TXUSRCLK2 | 156.25MHz |
| VCO | 625MHz |

DRP 序列复用当前工程已有的 Xilinx VPHY MMCME2 encoding 方法，没有手写未经生成方法验证的 magic number。

## 14. TXUSRCLK2 frequency window

当前 txusrclk2 frequency counter 采用约 1ms 统计窗口。10G profile 预期 TXUSRCLK2=156.25MHz，因此预期计数约 156250。初始窗口设置为：

```text
153000 .. 159500
```

该窗口需要后续上板实测确认。VERIFY_RATE 未被绕过，不能仅凭 QPLLLOCK 或 gt_ready 判定成功。

## 15. ILA probe

本轮继续使用稳定 AXI/FCLK ILA，不让 debug hub 依赖 TXUSRCLK2。新增/保留的关键 mark_debug 信号包括：

- `target_pll_type_dbg`
- `active_pll_type_dbg`
- `programmed_pll_type_dbg`
- `qpll_selected`
- `gt0_txsysclksel_effective`
- `qpllreset_ctrl`
- `qplllock_sync`
- `qpllrefclklost_sync`
- `txusrclk2_freq_counter_axi`
- GT/MMCM DRP addr/data/en/we/rdy/done/error

## QPLL / PLL source ILA 可观测性

为补齐 10G QPLL bring-up 的 PLL source 证据链，本轮将 QPLL/PLL source 状态加入现有稳定 AXI/FCLK 域 ILA。现有 `ila_laser_axi_cfg` 已有 50 个 probe，且 probe0-probe48 均用于 rate、reset、DRP、MMCM lock、GT ready、txusrclk2 frequency 等关键证据。为避免修改 BD ILA probe 数量、capture depth 和 clock，本轮复用 32-bit `ila_laser_axi_cfg/probe49`，将其从单一 `dbg_timeout_count` 升级为 debug-only PLL/QPLL status bus。

该 probe 仍接在 `gt_ctrl_clk / AXI FCLK` 域，不依赖 TXUSRCLK2、TXOUTCLK 或 QPLL/CPLL 输出时钟。新增观测不反馈到 rate controller、GT DRP、MMCM DRP、profile table 或 VERIFY_RATE 逻辑。

### 新增/暴露的 QPLL 关键观测

| 信号 | 位宽 | 所属时钟域 | ILA 承载位置 | 含义 |
|---|---:|---|---|---|
| `qpll_selected` | 1 | `gt_ctrl_clk` | `probe49[16]` | 真实驱动 `TXSYSCLKSEL` mux 的 QPLL source select。 |
| `qplllock_sync` | 1 | `gt_ctrl_clk` 同步后 | `probe49[17]` | 同步后的 QPLLLOCK，用于证明 QPLL lock 已建立。 |
| `qpllrefclklost_sync` | 1 | `gt_ctrl_clk` 同步后 | `probe49[18]` | 同步后的 QPLL reference clock lost，10G DONE 稳态预期为 0。 |
| `gt0_txsysclksel_effective[1:0]` | 2 | `gt_ctrl_clk` 组合稳定选择 | `probe49[20:19]` | 实际送入 GTXE2_CHANNEL 的 `TXSYSCLKSEL`。当前 encoding：CPLL=`2'b00`，QPLL=`2'b11`。 |
| `active_pll_type_dbg[1:0]` | 2 | `gt_ctrl_clk` | `probe49[22:21]` | 最后一次通过 VERIFY_RATE 后正式接受的 PLL 类型。当前 encoding：CPLL=0，QPLL=1。 |
| `programmed_pll_type_dbg[1:0]` | 2 | `gt_ctrl_clk` | `probe49[24:23]` | 最近一次实际完成 PLL source 选择 / lock 流程后的 PLL 类型。 |

同时在同一 probe 中加入推荐辅助项：

| 信号 | 位宽 | ILA 承载位置 | 用途 |
|---|---:|---|---|
| `target_pll_type_dbg[1:0]` | 2 | `probe49[26:25]` | 本轮请求目标 PLL 类型。 |
| `qpllreset_ctrl` | 1 | `probe49[27]` | 观察 QPLL reset 控制。 |
| `cplllock_sync` | 1 | `probe49[28]` | 观察 QPLL->CPLL 回切时 CPLL lock 是否恢复。 |
| `dbg_rate_timeout_count[15:0]` | 16 | `probe49[15:0]` | 保留原 timeout counter 的低 16 位，用于观察 WAIT/timeout 推进。 |

`active_pll_type_dbg` 与 `programmed_pll_type_dbg` 的区别是本阶段 10G/QPLL 恢复语义的关键：`programmed_pll_type_dbg` 表示硬件 source 最近实际切换到哪一类 PLL；`active_pll_type_dbg` 只有在 VERIFY_RATE 成功后才更新，代表当前 rate controller 认可的 last-good PLL 类型。因此，当 source 已切换但 VERIFY 尚未成功时，两者允许短暂不同。

本轮只是增加 ILA 可观测性，不修改动态切换功能逻辑。更新后的 hardware capture 尚未执行；后续上板应重点保存：

```text
docs/images/dynamic_rate/qpll_10g_profile/ila_cpll_to_qpll_10g_pll_select_lock_sequence.png
docs/images/dynamic_rate/qpll_10g_profile/ila_qpll_10g_done_pll_state_freq.png
docs/images/dynamic_rate/qpll_10g_profile/ila_qpll_10g_to_cpll_pll_restore_sequence.png
```

当前证据边界：

```text
ILA probes were added and implementation passed.
Updated hardware capture has not yet been run.
```

## 16. Vitis / UDP 修改

软件新增：

- `LASER_RATE_ID_10000M = 9`
- `rate set 10000`
- `rate plan 10000`
- `rate list` 显示 10000
- QPLL error code 字符串
- `rate status` mode 字符串包含 `10000m_qpll`

UDP 命令格式、UDP 端口、GPIO bitfield、AXI 地址均未改变。

## 17. Synth / implementation / timing

执行命令：

```text
D:/Vivado/2022.2/bin/vivado.bat -mode batch -source scripts/run_qpll_wrapper_architecture_project_flow.tcl
```

结果：

| 项目 | 结果 |
|---|---|
| synthesis | passed |
| implementation | passed |
| write_bitstream | passed |
| write_debug_probes | passed |
| WNS | 7.029ns |
| TNS | 0.000ns |
| WHS | 0.049ns |
| THS | 0.000ns |
| Timing summary | All user specified timing constraints are met |

生成文件：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

报告路径：

```text
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/timing_summary_qpll_wrapper_architecture.rpt
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/utilization_qpll_wrapper_architecture.rpt
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/debug_cores_qpll_wrapper_architecture.rpt
```

## 18. Vitis build

执行目录：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug
```

执行命令：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && make clean && make all"
```

结果：

```text
text = 149279
data = 3432
bss  = 3201088
dec  = 3353799
```

ELF：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf
```

ELF strings 已确认包含 `10000`、`QPLL`、`OK RATE_LIST`、`OK RATE_PLAN`、`QPLL_LOCK_TIMEOUT`、`QPLL_REFCLK_LOST`。

## 19. CPLL 回归

本轮完成 build/timing 级回归，确认现有 CPLL profile 仍可综合实现，且 supported list 已保留：

```text
500,1000,1250,2000,2500,3125,5000,6250
```

Hardware CPLL regression was not run.

## 20. 10G UDP / ILA 结果

Hardware bring-up was not run. 当前不能声明 `rate set 10000` 已上板通过。

## 21. 回切结果

10G -> CPLL 回切尚未上板验证。后续必须覆盖：

```text
10000 -> 6250 -> 10000
10000 -> 5000 -> 10000
10000 -> 1000 -> 10000
10000 -> 500
```

重点验证 QPLL->CPLL、CPLL->QPLL、0x1002/0x1003 CPLL 参数组 restore、current_rate 只在 VERIFY_RATE 成功后更新。

## 22. 示波器与 BER 边界

Oscilloscope validation was not run.

10G eye / BER / external optical-link validation was not run.

## 23. 当前未验证边界

本报告只证明 10G QPLL dynamic profile 的代码集成、Vivado build/timing 和 Vitis build 已通过。

当前不能声明：

- 10G dynamic switching 已上板通过；
- 10G 高速串行眼图通过；
- BER 通过；
- SFP+ 或外部光口链路通过；
- 长期稳定性通过；
- 示波器低速观测通过；
- 任意速率动态调速完成；
- 所有 QPLL profile 均已支持。

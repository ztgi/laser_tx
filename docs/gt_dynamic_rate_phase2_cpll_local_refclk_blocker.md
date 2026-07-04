# GT 动态速率第二阶段：CPLL 本地参考时钟真实切换核查与阻塞报告

## 1. 阶段二目标与本轮处理结论

阶段二原目标是实现真实硬件速率切换的最小闭环：

```text
rate set 500
rate set 1000
500 Mb/s <-> 1000 Mb/s
```

本轮执行了只读核查，没有实现真实 `rate set`，也没有写 GT DRP。结论如下：

```text
当前工程不能安全直接进入 500M <-> 1000M 真实 DRP 切换实现。
必须先补齐 GT DRP 暴露、1G GT Wizard/example design 证据、TX user clocking 重构方案和 XDC/timing 方案。
```

因此本轮按任务书中的停止条件处理：不破坏 Profile 0，不硬写 DRP，只形成阻塞报告和下一步设计建议。

## 2. 为什么第二阶段只应做 CPLL + 本地 REFCLK

第二阶段限定为 CPLL + 本地固定参考时钟是合理的，因为：

1. 当前固定 Profile 0 已使用 CPLL 和本地 125 MHz MGTREFCLK；
2. AD9528 动态参考时钟尚未实现，`laser_ad9528_apply_rate_profile()` 仍是未实现接口；
3. QPLL/common DRP 当前没有完整暴露到当前工程；
4. CPLL 分支理论上比 QPLL/common 分支影响范围小，更适合作为第一条真实动态切换链路。

但“只做 CPLL”不能写成 CPLL-only 死结构。后续 rate controller 应保留 `target_pll/current_pll`、channel/common DRP、selected lock 等字段。

## 3. 为什么优先选择 500M / 1000M

500M / 1000M 是合适的候选对，因为二者都可沿用 64-bit TXDATA、无 8b/10b 的用户语义：

| 目标速率 | 期望 TXUSRCLK | 期望 TXUSRCLK2 | 说明 |
|---:|---:|---:|---|
| 500 Mb/s | 15.625 MHz | 7.8125 MHz | 当前 Profile 0 |
| 1000 Mb/s | 31.25 MHz | 15.625 MHz | 候选目标，需 1G example design 证明 |

但当前工程只有 500M Profile 0 的 GT Wizard/XCI/example-style clocking，没有 1000M XCI 或官方 example design 证据。

## 4. 当前 fixed Profile 0 的真实 GT 参数

本节基于当前工程文件核查：

- `laser_tx.srcs/sources_1/ip/gtwizard_0/gtwizard_0.xci`
- `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v`
- `laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile0.v`
- `scripts/gt_profile0_impl_pre.tcl`
- `reports/gt_profile0/timing_summary.rpt`

| 项目 | 当前 Profile 0 |
|---|---|
| line rate | 0.5 Gb/s |
| TXDATA 外部宽度 | 64 bit |
| TX_INT_DATAWIDTH | 32 |
| 编码 | None，无 8b/10b |
| PLL | CPLL |
| REFCLK | 本地 125 MHz MGTREFCLK0 |
| CPLL fbdiv | XCI 中 `gt0_val_cpll_fbdiv = 4` |
| CPLL refclk div | XCI 中 `gt0_val_cpll_refclk_div = 1` |
| TXOUT_DIV | XCI 中 `gt0_val_cpll_txout_div = 8` |
| TXOUTCLK | 15.625 MHz |
| TXUSRCLK | 15.625 MHz |
| TXUSRCLK2 | 7.8125 MHz |
| TXUSRCLK/TXUSRCLK2 | 2:1 |
| timing hook | 强制检查 TXOUTCLK/TXUSRCLK=64 ns，TXUSRCLK2=128 ns |

## 5. 500M / 1000M CPLL / TXOUT_DIV 参数核查

当前 500M 参数已由现有 bitstream/timing/ILA 验证：

```text
500M:
  REFCLK      = 125 MHz
  PLL         = CPLL
  TXOUT_DIV   = 8
  TXUSRCLK    = 15.625 MHz
  TXUSRCLK2   = 7.8125 MHz
```

1000M 的候选规划值在软件 dry-run 中为：

```text
1000M:
  REFCLK      = LOCAL_125
  PLL         = CPLL
  TXOUT_DIV   = 4
  TXUSRCLK    = 31.25 MHz
  TXUSRCLK2   = 15.625 MHz
```

但该 1000M 配置目前只是规划值，不是已验证 GT Wizard 参数。当前工程缺少：

1. 1000M GT Wizard XCI；
2. 1000M generated HDL/example design；
3. 1000M TXUSRCLK/TXUSRCLK2 clocking helper；
4. 1000M XDC/timing 报告；
5. 1000M 上板 CPLLLOCK/TXRESETDONE/txusrclk2 观测结果。

因此不能把 `TXOUT_DIV=4` 直接写入 DRP 并声明真实切换。

## 6. 当前需要写入的 DRP 地址和数据状态

从参考工程 `D:/FPGA_Learn/project_gtx` 可看到候选 DRP 地址：

| 候选地址 | 名称 | 来源 |
|---:|---|---|
| `9'h088` | TXOUT_DIV | `project_gtx/src/new/gt_rate_ctrl.v` |
| `9'h06A` | TX_CLK25_DIV | `project_gtx/src/new/gt_rate_ctrl.v` |
| `9'h05E` | CPLL 参数 | `project_gtx/src/new/gt_rate_ctrl.v` |

这些地址只能作为参考，不能直接用于当前 `laser_tx` 工程的真实写入，原因：

1. 当前 `laser_tx` 的 GT Wizard 只有 500M Profile 0；
2. 当前工程未生成 1000M XCI 对比表；
3. 当前工程未用 Vivado/GT Wizard example design 确认 1000M 对应 bitfield；
4. 当前 wrapper 中 DRP 输入仍被 tie-off；
5. 当前 TX user clocking 无动态重构。

本轮没有新增任何 DRP 写表。

## 7. 当前 GT DRP 暴露状态

当前 XCI 中：

```text
gt0_val_drp = true
gt0_val_drp_clock = 60
```

但 `laser_gt_tx_profile0.v` 中实际连接为：

```verilog
.gt0_drpaddr_in (9'd0),
.gt0_drpclk_in  (ctrl_clk),
.gt0_drpdi_in   (16'd0),
.gt0_drpdo_out  (drpdo_unused),
.gt0_drpen_in   (1'b0),
.gt0_drprdy_out (drprdy_unused),
.gt0_drpwe_in   (1'b0),
```

结论：

```text
channel DRP 端口在 IP 层存在，但当前 wrapper 没有暴露给 rate controller。
common/QPLL DRP 当前未在 laser_tx 工程中形成可控接口。
```

这是阶段二真实切换 blocker。

## 8. TXUSRCLK / TXUSRCLK2 关系核查

当前 `laser_gt_usrclk_profile0.v` 明确是 Profile 0 专用：

```text
TXOUTCLK 15.625 MHz -> MMCM
  CLKOUT1 /39 -> TXUSRCLK  15.625 MHz
  CLKOUT0 /78 -> TXUSRCLK2  7.8125 MHz
```

`scripts/gt_profile0_impl_pre.tcl` 也强制检查：

```text
GT TXOUTCLK / TXUSRCLK period = 64 ns
GT TXUSRCLK period            = 64 ns
GT TXUSRCLK2 period           = 128 ns
```

如果切到 1000M，按当前 64-bit/no encoding 语义应为：

```text
TXUSRCLK  = 31.25 MHz
TXUSRCLK2 = 15.625 MHz
```

当前 clocking helper 没有 MMCM 动态重构接口，Vivado timing hook 也仍强制 Profile 0 的 64/128 ns 周期。因此不能在当前 clocking 结构不变的情况下安全声明 1000M 数据通路正确。

这是阶段二真实切换的第二个关键 blocker。

## 9. 为什么本轮不实现 `laser_gt_rate_ctrl`

任务书要求如果发现 500M/1000M 不能安全共用当前 CPLL/REFCLK/clocking 方案，则停止并报告，不要硬写 DRP。

本轮发现：

1. channel DRP 未暴露；
2. 1000M DRP bitfield 未由当前 XCI/example design 验证；
3. TX user clocking 固化为 Profile 0；
4. XDC/timing hook 固化为 500M；
5. common/QPLL DRP 未暴露，QPLL 扩展接口也不能在当前 wrapper 中闭合。

因此本轮没有新增：

```text
laser_gt_rate_ctrl.v
laser_gt_drp_writer.v
rate control GPIO/AXI register
rate ILA probe
rate set 真实硬件入口
```

## 10. 建议的通用 `laser_gt_rate_ctrl` 状态机结构

后续实现时，建议保留通用状态：

```text
ST_IDLE
ST_LATCH_REQUEST
ST_STOP_TX
ST_ASSERT_GT_RESET
ST_CONFIG_REFCLK
ST_WRITE_CHANNEL_DRP
ST_WRITE_COMMON_DRP
ST_SELECT_PLL
ST_RESET_SELECTED_PLL
ST_WAIT_SELECTED_PLL_LOCK
ST_RELEASE_TX_RESET
ST_WAIT_TXRESETDONE
ST_DONE
ST_ERROR
```

阶段二可只实现 CPLL 分支，但接口必须保留：

```text
target_pll/current_pll
target_ref/current_ref
selected_lock
cplllock/qplllock
channel/common DRP
txsysclksel
rate_error_code
```

## 11. 建议的 ILA probe

真实实现前应规划 ILA：

```text
rate_apply_toggle
rate_busy
rate_done
rate_error
rate_state[7:0]
target_rate_mbps
current_rate_mbps
target_pll
current_pll
target_ref
current_ref

ch_drpaddr
ch_drpdi
ch_drpdo
ch_drpen
ch_drpwe
ch_drprdy

common_drpaddr
common_drpdi
common_drpdo
common_drpen
common_drpwe
common_drprdy

cplllock
qplllock
selected_lock
txsysclksel
txresetdone
gt_ready

txusrclk2_divided_debug
txdata[63:0]
valid_mask[63:0]
```

其中 `txusrclk2_divided_debug` 是证明 500M/1000M 切换后用户时钟实际变化的关键观测点。

## 12. 回退到 fixed Profile 0 的方法

在真实切换实现前，唯一安全回退方法仍是：

1. 使用当前已验证的 Profile 0 bit/LTX；
2. 保持 GT Wizard、wrapper、XDC、XSA 不变；
3. Vitis 继续使用固定 Profile 0 控制链路；
4. `rate set` 不返回 OK，不伪装动态切换成功。

真实动态切换阶段必须增加 rollback 状态机，例如：

```text
rate set 1000 failed
  -> assert TX reset
  -> restore 500M DRP values
  -> reset CPLL
  -> wait CPLLLOCK
  -> wait TXRESETDONE
  -> verify gt_ready
  -> report OK_ROLLBACK or ERR_RATE_ROLLBACK_FAILED
```

## 13. 当前不涉及 AD9528

本轮未修改 AD9528。阶段二也不应引入 AD9528 动态参考时钟。

```text
AD9528 可变参考时钟留到第三阶段，用于宽范围细步进。
```

## 14. QPLL 后续扩展 blocker

QPLL 动态切换后续至少需要补齐：

1. GTXE2_COMMON QPLL DRP 端口是否暴露；
2. QPLL 是否被其他 GT channel 共用；
3. reset QPLL 是否影响其他 channel；
4. QPLL_N / QPLL_M / QPLL_CFG bitfield 来源；
5. QPLLLOCK 和 selected PLL lock 状态回读；
6. TXSYSCLKSEL 切换是否完全处于 TX reset 期间；
7. QPLL 切换后 TXUSRCLK/TXUSRCLK2 是否正确；
8. QPLL 动态切换失败时如何回退到 fixed fallback。

## 15. 验证建议

在进入真实实现前，请先补齐以下验证资产：

1. 生成或另存 1000M GT Wizard 配置；
2. 打开 1000M example design，确认 TXOUTCLK/TXUSRCLK/TXUSRCLK2；
3. 对比 500M/1000M generated HDL，提取 DRP bitfield；
4. 设计动态 TX user clocking 方案，确认是否需要 MMCM DRP 或多 clocking helper；
5. 修改 wrapper 暴露 channel DRP，但必须先形成 RTL/BD/XDC 变更计划；
6. 加入 `txusrclk2_divided_debug`；
7. 重新综合、实现、timing、bit/LTX、XSA；
8. 再实现 Vitis `rate set 500/1000` 真入口；
9. 上板验证 `rate_busy -> rate_done`、`selected_lock`、`txresetdone`、`gt_ready`、`txusrclk2_divided_debug`。

## 16. 本轮结论

本轮没有实现真实 500M/1000M 动态切换。

原因不是 UDP 或 `gt_rate_plan()`，而是当前硬件工程还不满足真实切换的最低安全条件：

```text
GT DRP 端口未暴露
CPLL/1000M DRP bitfield 未由当前 XCI/example design 确认
TXUSRCLK/TXUSRCLK2 动态关系未实现
XDC/timing 仍固定为 Profile 0
txusrclk2 频率变化没有 debug 观测通道
```

因此本轮按安全规则停止，没有破坏 Profile 0。

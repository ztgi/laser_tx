# 10G QPLL capability check

## 1. 检查目标

本次只做 read-only 检查，目标是确认当前主工程 GT wrapper 是否已经具备安全加入 10G QPLL dynamic profile 的基础能力。

检查范围包括：

- GT Wizard XCI；
- generated HDL；
- `laser_gt_tx_profile0.v` 主工程 wrapper；
- GT 约束；
- 当前 rate controller 可观测/可控信号。

本检查不修改 RTL、Vitis、BD、XDC、Tcl、GT Wizard、DRP 参数或 ILA probe。

## 2. 关键检查结果

| 检查项 | 当前结果 | 结论 |
|---|---|---|
| `GTXE2_COMMON` 是否实例化 | 未在当前主工程 active wrapper 中实例化 | 不具备 QPLL common block |
| `gt_val_tx_qpll` | XCI generated value 为 `false` | 当前 TX profile 为 CPLL-only |
| `gt_val_rx_qpll` | XCI generated value 为 `false` | RX/QPLL 也未启用 |
| `gt0_qplloutclk_in` | 在 `laser_gt_tx_profile0.v` 中接 `1'b0` | QPLL clock 未接入 GT channel |
| `gt0_qplloutrefclk_in` | 在 `laser_gt_tx_profile0.v` 中接 `1'b0` | QPLL refclk 未接入 GT channel |
| `gt0_txsysclksel_in` | 在 `laser_gt_tx_profile0.v` 中固定 `2'b00` | 当前 TX system clock select 固定 CPLL 路径 |
| QPLL lock 观测 | 当前 top/wrapper 没有真实 QPLLLOCK 输出路径 | rate controller 无法等待 QPLL lock |
| QPLL reset 控制 | generated init 中 `QPLL_RESET` 未接出，主工程无控制路径 | rate controller 无法复位/释放 QPLL |
| QPLL reset FSM 参数 | generated init 中 `TX_QPLL_USED="FALSE"` | 官方 reset FSM 走 CPLL 逻辑 |
| XDC | 注释明确当前 uses CPLL, no independent GTXE2_COMMON/QPLL location | 约束侧未准备 QPLL common placement |

## 3. 证据摘录

### 3.1 XCI

当前 `laser_tx.srcs/sources_1/ip/gtwizard_0/gtwizard_0.xci` 中：

```text
gt_val_tx_qpll = false
gt_val_rx_qpll = false
gt0_val_tx_line_rate = 0.5
gt0_val_tx_reference_clock = 125.000
```

虽然 XCI 中存在部分 QPLL 参数字段和 `gt0_val_port_txsysclksel` / `gt0_val_port_qpllpd` 端口选项，但 generated result 明确为 TX/RX QPLL 未启用。

### 3.2 主工程 wrapper

当前 `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` 中：

```verilog
.gt0_txsysclksel_in           (2'b00),
.gt0_qplloutclk_in            (1'b0),
.gt0_qplloutrefclk_in         (1'b0)
```

同时 reset / ready 逻辑以 `cplllock_sync` 为核心：

```verilog
wire gt0_gttxreset_effective = ctrl_rst | rate_gt_tx_reset | ~cplllock_sync;
wire gt0_txuserrdy_effective = ~ctrl_rst & ~rate_txuserrdy_block &
                                cplllock_sync & tx_mmcm_locked_sync;
```

这说明当前动态执行器只闭合了 CPLL lock / reset / ready 链路。

### 3.3 generated init

当前 generated `gtwizard_0_init.v` 中：

```text
TX_QPLL_USED = "FALSE"
RX_QPLL_USED = "FALSE"
QPLLLOCK = tied_to_vcc_i
QPLL_RESET = ()
```

这表示官方 startup FSM 并未真实使用 QPLLLOCK，也没有把 QPLL reset 作为主工程可控输出。

### 3.4 约束

`constraints/laser_tx_gt_profile0.xdc` 中已有说明：

```text
uses CPLL, therefore no independent GTXE2_COMMON/QPLL location is needed.
```

这进一步说明当前约束和 floorplanning 没有纳入 `GTXE2_COMMON` / QPLL。

## 4. 是否可以安全加入 10G

不能。

原因不是 10G 参数本身是否可行，而是当前 wrapper 不具备 QPLL profile 的结构条件：

1. 没有实例化或连接 `GTXE2_COMMON`；
2. 没有真实 `QPLLCLK` / `QPLLREFCLK` 输入到 channel；
3. 没有可观测 `QPLLLOCK`；
4. 没有可控 `QPLLRESET`；
5. `TXSYSCLKSEL` 固定在 CPLL 路径；
6. rate controller 只等待 `cplllock_sync`；
7. ILA/status 不包含 QPLL lock/reset/select；
8. XDC 未包含 QPLL common placement / clocking 约束。

因此当前不能把 10G 加入 supported profile list，也不能把 10G 伪装成 CPLL profile。

## 5. 阻塞项

安全加入 10G QPLL profile 前，至少需要完成：

- 重新生成或扩展 GT Wizard wrapper，使 TX path 支持 QPLL；
- 引入并约束 `GTXE2_COMMON`；
- 连接 `QPLLCLK` / `QPLLREFCLK` 到 GTXE2_CHANNEL；
- 将 `TXSYSCLKSEL` / PLL select 变成可控状态；
- 将 `QPLLLOCK` 同步到 AXI/FCLK 域；
- 将 `QPLLRESET` 纳入 rate controller；
- 增加 QPLL lock timeout / PLL select error code；
- 增加 ILA probe 和 UDP status 字段；
- 重新生成 bit/LTX 并上板验证。

## 6. 当前结论

当前主工程是 CPLL-only dynamic wrapper，不具备安全加入 10G QPLL profile 的 wrapper 条件。

本轮应停止 10G profile table 集成，只输出 QPLL 架构升级计划；`rate list` 不应加入 10000，`rate set 10000` 不应写入 PL request。

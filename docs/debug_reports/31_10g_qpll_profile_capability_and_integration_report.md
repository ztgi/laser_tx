# 10G QPLL profile capability 与集成阶段报告

## 1. 本阶段目标

本阶段目标是确认当前主工程是否具备加入 10G QPLL dynamic profile 的条件。10G 已确认属于 QPLL profile，不属于当前 CPLL profile 的普通扩展。

本轮先执行 Step 1：QPLL capability check。若当前 wrapper 不支持 QPLL，则停止，不修改 profile table，不修改 Vitis supported list，不把 10G 加入 `rate set`。

## 2. 10G 使用 QPLL 的前提

当前已验证的 500M / 1000M / 1250M / 2000M / 2500M / 3125M / 5000M / 6250M 均属于 125MHz REFCLK + CPLL dynamic profile。其验证链路包括：

- CPLL divider DRP；
- TXOUT_DIV DRP；
- MMCM DRP；
- reset / lock / ready；
- `txusrclk2_freq_counter_axi`；
- `VERIFY_RATE`；
- UDP `rate set/status`。

10G 需要 QPLL，因此必须新增或确认 QPLL wrapper 能力，而不能复用 CPLL-only 逻辑伪装成 10G。

## 3. 当前 wrapper QPLL capability check

| 检查项 | 当前结果 | 判断 |
|---|---|---|
| `GTXE2_COMMON` | 当前主工程 active wrapper 未实例化 | 不支持 QPLL common |
| `gt_val_tx_qpll` | XCI generated value 为 `false` | TX QPLL 未启用 |
| `gt_val_rx_qpll` | XCI generated value 为 `false` | RX QPLL 未启用 |
| `gt0_qplloutclk_in` | 在 `laser_gt_tx_profile0.v` 接 `1'b0` | QPLL clock 未接入 |
| `gt0_qplloutrefclk_in` | 在 `laser_gt_tx_profile0.v` 接 `1'b0` | QPLL refclk 未接入 |
| `gt0_txsysclksel_in` | 固定 `2'b00` | 未提供 PLL select 控制 |
| `QPLLLOCK` | generated init 中接 `tied_to_vcc_i`，主工程无真实 QPLLLOCK | 无法验收 QPLL lock |
| `QPLL_RESET` | generated init 中未接出 | rate controller 无法控制 QPLL reset |
| reset FSM 参数 | `TX_QPLL_USED="FALSE"` | 官方 startup FSM 走 CPLL 路径 |
| XDC | 注释说明当前 uses CPLL，无 GTXE2_COMMON/QPLL location | 约束未准备 QPLL |

## 4. 是否存在 GTXE2_COMMON

未在当前主工程 active wrapper 中发现可用 `GTXE2_COMMON` 实例。

当前 generated `gtwizard_0_gt.v` 内部实例化的是 `GTXE2_CHANNEL`。虽然 channel 端口保留 `QPLLCLK` / `QPLLREFCLK` 输入，但主工程没有提供真实 QPLL common clock，而是将 QPLL 输入绑到 0。

## 5. 是否存在 QPLL ports

存在部分 QPLL 相关端口名，但它们没有构成可用 QPLL 系统：

- `gt0_qplloutclk_in`：存在，但主工程接 `1'b0`；
- `gt0_qplloutrefclk_in`：存在，但主工程接 `1'b0`；
- `gt0_txsysclksel_in`：存在，但主工程固定 `2'b00`；
- `QPLLLOCK`：startup FSM 中接常 1，不是真实 QPLL lock；
- `QPLL_RESET`：未接出到主工程控制逻辑。

因此不能把“端口名存在”理解为“QPLL profile 可用”。

## 6. 是否真正加入 10G

没有。

本轮没有修改：

- RTL；
- Vitis；
- BD；
- XDC；
- Tcl；
- DRP 参数；
- ILA probe；
- Vivado 工程文件。

本轮没有把 `RATE_ID_10000M` 加入 profile table，也没有把 `10000` 加入 UDP `rate list` / `rate set`。

## 7. 阻塞原因

当前不具备安全加入 10G QPLL profile 的 wrapper 条件：

1. 没有可用 `GTXE2_COMMON`；
2. 没有真实 QPLL clock/refclk 连接；
3. 没有 QPLL reset 控制；
4. 没有 QPLL lock 观测；
5. 没有 PLL select 控制；
6. reset sequence 只围绕 CPLL lock；
7. ILA / status / error_code 未覆盖 QPLL；
8. XDC 未覆盖 QPLL common placement / clocking。

## 8. 若后续加入 10G，需要的 profile 参数

后续真正实现时，10G profile 至少需要：

- `rate_id`；
- `rate_mbps = 10000`；
- `refclk_id`；
- `pll_type = PLL_TYPE_QPLL`；
- `qpll_required = 1`；
- `qpll_refclk_div`；
- `qpll_fbdiv`；
- `qpll_fbdiv_ratio`；
- `txout_div`；
- `txout_div encoding`；
- `mmcm_drp_seq_id`；
- `expected_txusrclk2_hz`；
- `freq_counter_min/max`；
- QPLL lock timeout；
- reset timeout；
- `ad9528_dynamic_required`。

这些参数必须来自 QPLL-capable GT Wizard / official documentation / 可追溯 DRP map，不能把 10G 写成 CPLL M/N1/N2 profile。

## 9. QPLL reset / lock / ready sequence 建议

后续建议流程：

```text
QUIESCE_TX
ASSERT_RESET
SELECT_QPLL_PROFILE
PROGRAM_QPLL_DRP_OR_SELECT_QPLL_PARAM
RESET_QPLL
WAIT_QPLL_LOCK
PROGRAM_GT_CHANNEL_DRP
PROGRAM_MMCM_DRP
RELEASE_GT_RESET
WAIT_MMCM_RESET_RELEASE
WAIT_MMCM_LOCK
RELEASE_TXUSERRDY
WAIT_TXRESETDONE
WAIT_GT_READY
VERIFY_RATE
DONE / ERROR
```

必须保持：

- `current_rate` 只在 `VERIFY_RATE` 成功后更新；
- QPLLLOCK 必须进入验收链路；
- `txusrclk2_freq_counter_axi` 必须进入 VERIFY；
- 失败时保留 last-good rate；
- 不破坏已有 CPLL profiles。

## 10. frequency counter 位宽检查

若 10G 下 `TXUSRCLK2=156.25MHz`，约 1ms 统计窗口计数约为：

```text
156250
```

当前 3125M / 6250M 阶段已将 `txusrclk2_freq_counter_axi` 和 profile window 扩展到 32-bit / 24-bit 路径，原则上不再受 16-bit 65535 限制。但真正加入 10G 前仍需重新检查：

- counter 采样路径是否完整；
- expected min/max 是否能表达 156250；
- compare path 是否零扩展而非截断；
- ILA probe 是否显示完整位宽。

## 11. Vitis / UDP 影响

本轮未修改 Vitis / UDP。

在当前 wrapper 不支持 QPLL 的前提下：

- `rate list` 不加入 10000；
- `rate set 10000` 不应写入 PL request；
- 如果后续需要 `rate plan 10000`，建议返回 blocked / requires QPLL wrapper support。

## 12. build / timing / utilization / debug core

本轮未修改 RTL/Vitis，也未运行新的 synth/impl/bitstream。

```text
Synthesis/implementation was not run
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required after QPLL wrapper changes.
Hardware test was not run
```

## 13. 当前边界声明

当前结论是：

```text
当前不具备安全加入 10G QPLL profile 的 wrapper 条件，因此本轮不修改 RTL/Vitis，不加入 10G supported list。
```

不能声明：

- 10G dynamic profile 已实现；
- QPLL dynamic profile 已通过；
- 任意速率动态调速完成；
- 宽范围连续调速完成；
- AD9528 动态输出完成；
- 156.25MHz REFCLK 支持完成；
- 外部光口质量 / BER / 长期稳定性通过。

## 14. 下一步建议

下一步应先做 QPLL-capable wrapper 架构升级，而不是直接写 `RATE_ID_10000M`：

1. 生成或扩展支持 QPLL 的 GT Wizard wrapper；
2. 明确 `GTXE2_COMMON` placement 和 XDC；
3. 暴露并同步 `QPLLLOCK`；
4. 控制 `QPLLRESET`；
5. 增加 PLL select 控制；
6. 增加 QPLL ILA probe；
7. build 并确认 debug hub / ILA 稳定；
8. 再进入 10G profile table 和 Vitis supported list 修改。

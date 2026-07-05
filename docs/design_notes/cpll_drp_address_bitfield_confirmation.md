# CPLL DRP address / bitfield 确认报告

## 1. 本阶段目标与边界

本阶段只做 CPLL 参数动态 DRP 的 read-only 可追溯确认，不修改 RTL、BD、XDC、Vitis、GT Wizard、MMCM DRP 表，也不新建任何 125MHz CPLL static board 工程。

当前已通过的 500M / 1000M / 2000M dynamic profile 只覆盖了同一组 CPLL 参数下的 `TXOUT_DIV` 动态切换。下一阶段若要加入 1.25G / 2.5G 等 CPLL 参数变化 profile，必须先确认 CPLL 分频参数的 DRP address、bitfield、encoding、readback mask，以及 reset / relock 观测路径。

结论先写在前面：

```text
CPLL divider DRP address / bitfield 可以从 Xilinx VPHY GTXE2 官方驱动源码追溯确认；
TXOUT_DIV DRP address / bitfield 与当前工程实现一致；
当前主工程已具备 GT DRP 访问、readback、CPLL lock、GTTXRESET、TXUSERRDY、txresetdone、gt_ready 观测路径；
但当前 dynamic executor 还没有独立 CPLLRESET 控制 hook，gt0_cpllreset_in 仍主要由 ctrl_rst 驱动。

因此：可以进入“设计最小 CPLL reset/relock hook + dynamic profile 实现”的下一阶段；
但不能直接只写 0x5E 后沿用现有 TX reset-only sequence。
```

## 2. 证据来源

| 证据来源 | 路径 | 用途 |
|---|---|---|
| 当前 500M GT Wizard generated HDL | `laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v` | 确认当前工程 GTXE2_CHANNEL 端口、CPLL 参数、TXOUT_DIV |
| 1000M compare generated HDL | `reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/generated_ip/gtwizard_0/gtwizard_0_gt.v` | 确认 1000M 静态 profile 的 CPLL 参数与 TXOUT_DIV |
| 2G static generated HDL | `reports/gt_dynamic_rate_2g_static/gtwizard_2000m_compare/generated_ip/gtwizard_0/gtwizard_0_gt.v` | 确认 2G 静态 profile 的 CPLL 参数与 TXOUT_DIV |
| Xilinx VPHY GTXE2 driver | `D:/Vitis/2022.2/data/embeddedsw/XilinxProcessorIPLib/drivers/vphy_v1_12/src/xvphy_gtxe2.c` | 确认 GTXE2 CPLL / TXOUT_DIV DRP address、bitfield、encoding |
| Xilinx VPHY reset helper | `D:/Vitis/2022.2/data/embeddedsw/XilinxProcessorIPLib/drivers/vphy_v1_12/src/xvphy.c` | 确认 VPHY 对 PLL reset 与 GT reset 作为独立步骤处理 |
| 当前 dynamic executor RTL | `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | 确认当前状态机已有 TXOUT_DIV / MMCM DRP，但尚无 CPLLRESET 输出 |
| 当前 GT wrapper RTL | `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 确认 GT DRP、MMCM DRP、reset / ready / debug 接线 |
| 既有 500M/1000M DRP 报告 | `docs/debug_reports/06_drp_parameter_confirmation_for_500m_1000m.md` | 确认当前 TXOUT_DIV-only 动态切换依据 |
| line-rate 搜索记录 | `D:/FPGA_Learn/project_gtx/drp.txt` | 选择 1.25G / 2.5G 候选参数 |

## 3. 当前已验证 profile 的 CPLL 基线

当前 500M / 1000M / 2000M 三档 dynamic profile 均使用：

| 参数 | 当前值 | 说明 |
|---|---:|---|
| REFCLK | 125MHz | 不切换 156.25MHz，不接 AD9528 动态输出 |
| PLL | CPLL | 不使用 QPLL |
| `CPLL_REFCLK_DIV` / M | 1 | 当前三档一致 |
| `CPLL_FBDIV_45` / N1 | 4 | 当前三档一致 |
| `CPLL_FBDIV` / N2 | 4 | 当前三档一致 |
| CPLLCLKOUT | 2.000GHz | 当前三档一致 |
| 500M `TXOUT_DIV` | 8 | 已动态验证 |
| 1000M `TXOUT_DIV` | 4 | 已动态验证 |
| 2000M `TXOUT_DIV` | 2 | 已动态验证 |

这说明当前动态链路已经证明了 GT DRP、MMCM DRP、reset / lock / ready、VERIFY_RATE 与 UDP status 机制可用，但尚未证明 CPLL 参数变化后的重锁流程。

## 4. GTXE2 CPLL divider DRP address / bitfield

Xilinx VPHY GTXE2 driver 中定义：

```text
XVPHY_DRP_CPLL_PROG = 0x5E
```

并在 `XVphy_Gtxe2ClkChReconfig()` 中执行以下 read-modify-write 逻辑：

```text
读取 DRP 0x5E；
清除 0x1FFF；
bits [6:0]   写 CPLL_FBDIV / N2 的 DRP encoding；
bit  [7]     写 CPLL_FBDIV_45 / N1 的 DRP encoding；
bits [12:8]  写 CPLL_REFCLK_DIV / M 的 DRP encoding；
写回 DRP 0x5E。
```

因此，GTXE2 CPLL divider 字段可整理为：

| 字段 | DRP address | bitfield | mask | encoding 来源 |
|---|---:|---:|---:|---|
| `CPLL_FBDIV` / N2 | `0x05E` | `[6:0]` | `0x007F` | `XVphy_DrpEncodeQpllMCpllMN2()` |
| `CPLL_FBDIV_45` / N1 | `0x05E` | `[7]` | `0x0080` | `XVphy_DrpEncodeCpllN1()` |
| `CPLL_REFCLK_DIV` / M | `0x05E` | `[12:8]` | `0x1F00` | `XVphy_DrpEncodeQpllMCpllMN2()` |
| CPLL divider combined mask | `0x05E` | `[12:0]` | `0x1FFF` | read-modify-write 必须保留其它位 |

### 4.1 CPLL encoding

Xilinx VPHY GTXE2 driver 中的编码函数显示：

| attribute 值 | `XVphy_DrpEncodeQpllMCpllMN2()` encoding | 可用于 |
|---:|---:|---|
| 1 | 16 | M 或 N2 |
| 2 | 0 | M 或 N2 |
| 3 | 1 | N2 |
| 4 | 2 | N2 |
| 5 | 3 | N2 |
| 6 | 5 | N2 |
| 8 | 6 | N2 |
| 10 | 7 | N2 |
| 12 | 13 | N2 |
| 16 | 14 | N2 |
| 20 | 15 | N2 |

`CPLL_FBDIV_45` / N1 使用 `XVphy_DrpEncodeCpllN1()`：

| N1 attribute | encoding |
|---:|---:|
| 4 | 0 |
| 5 | 1 |

当前工程需要的已验证或候选值：

| profile | M | M enc | N1 | N1 enc | N2 | N2 enc |
|---|---:|---:|---:|---:|---:|---:|
| 500M / 1000M / 2000M baseline | 1 | 16 | 4 | 0 | 4 | 2 |
| 1.25G preferred candidate | 1 | 16 | 4 | 0 | 5 | 3 |
| 2.5G fallback candidate | 1 | 16 | 4 | 0 | 5 | 3 |

### 4.2 CPLL DRP write/readback 建议

对 1.25G / 2.5G 这类只改变 N2 的候选 profile，推荐 read-modify-write：

```text
read  0x05E -> old
new = (old & ~16'h1FFF)
    | (cpll_fbdiv_n2_enc & 7'h7F)
    | ((cpll_fbdiv_45_n1_enc & 1'h1) << 7)
    | ((cpll_refclk_div_m_enc & 5'h1F) << 8)
write 0x05E <- new
readback 0x05E
check (readback & 16'h1FFF) == (new & 16'h1FFF)
```

不要直接覆盖 0x05E 全 16bit，必须保留 `[15:13]` 等非 divider 位。

## 5. TXOUT_DIV DRP address / bitfield

Xilinx VPHY GTXE2 driver 中定义：

```text
XVPHY_DRP_OUT_DIV_PROG = 0x88
```

`XVphy_Gtxe2OutDivChReconfig()` 中：

| 字段 | DRP address | bitfield | mask | 说明 |
|---|---:|---:|---:|---|
| `RXOUT_DIV` | `0x088` | `[2:0]` | `0x0007` | 当前 TX-only 动态切换不修改 |
| `TXOUT_DIV` | `0x088` | `[6:4]` | `0x0070` | 当前 500/1000/2000 已使用 |

`XVphy_DrpEncodeCpllTxRxD()` 的 TX/RX OUT_DIV encoding：

| OUT_DIV | encoding |
|---:|---:|
| 1 | 0 |
| 2 | 1 |
| 4 | 2 |
| 8 | 3 |
| 16 | 4 |

当前工程已实现并上板验证的 TXOUT_DIV readback 判断：

```text
gt_drp_do[6:4] == target_txout_div_enc
```

## 6. Reset / lock / ready 信号确认

当前 GT Wizard generated HDL / wrapper 暴露了以下必要信号：

| 信号 | 方向 | 当前用途 | 确认结果 |
|---|---|---|---|
| `gt0_cplllock_out` | GT -> PL | 同步到 `cplllock_sync`，参与 `gt_ready` / reset 判断 | 已存在 |
| `gt0_cpllreset_in` | PL -> GT | 当前主要接 `ctrl_rst` | 已存在，但 rate controller 尚未独立控制 |
| `gt0_gttxreset_in` | PL -> GT | 由 `ctrl_rst | rate_gt_tx_reset | ~cplllock_sync` 形成 | 已存在 |
| `gt0_txuserrdy_in` | PL -> GT | 由 `~ctrl_rst & ~rate_txuserrdy_block & cplllock_sync & tx_mmcm_locked_sync` 形成 | 已存在 |
| `gt0_txresetdone_out` | GT -> PL | 同步到 `txresetdone_sync`，用于 WAIT_GT_READY | 已存在 |
| `gt_ready` | wrapper 状态 | 汇总 CPLL/MMCM/TX reset done 状态 | 已存在 |

Xilinx VPHY helper 中 `XVphy_ResetGtPll()` 与 `XVphy_ResetGtTxRx()` 是两个独立 reset helper。这说明在“PLL 参数变化”场景中，PLL reset / relock 不应被等同于普通 GT TX reset。

## 7. 当前工程缺口

当前 `laser_gt_rate_switch_500m_1000m.v` 已具备：

- `PROGRAM_GT_DRP`；
- `PROGRAM_MMCM_DRP`；
- `RATE_RELEASE_RESET`；
- `RATE_WAIT_MMCM_RESET_RELEASE`；
- `RATE_WAIT_LOCK`；
- `RELEASE_TXUSERRDY`；
- `WAIT_GT_READY` / `VERIFY_RATE`；
- `gt_drp_readback_value`；
- `txusrclk2_freq_counter_axi`；
- 错误码 / timeout。

但它当前只针对 `TXOUT_DIV` 变化设计：

```text
GT_DRP_SEQ_TXOUT_DIV
```

并且 `gt0_cpllreset_in` 在主 wrapper 中没有 rate controller 可控 hook。换句话说，当前 executor 可以可靠执行 TXOUT_DIV-only profile，但直接加入 CPLL 参数变化 profile 时还缺少：

1. `rate_cpll_reset` 输出；
2. CPLL DRP sequence 状态；
3. CPLL DRP readback mask/value；
4. CPLL reset hold / release / wait lock 子状态；
5. CPLL reset 与 GT TX reset、MMCM reset 的先后关系；
6. CPLL lock timeout / readback mismatch error code；
7. AXI/FCLK ILA 中的 CPLL reset / CPLL DRP probe。

因此，下一步不能只在 profile table 中加入 N2=5，然后沿用现有 TXOUT_DIV-only 状态机。

## 8. 推荐最小 CPLL 参数动态切换 sequence

在正式实现前，建议将现有 executor 扩展为：

```text
QUIESCE_TX
ASSERT_TX_RESET
ASSERT_CPLL_RESET
PROGRAM_CPLL_DRP      // 0x05E read-modify-write-readback
PROGRAM_TXOUT_DIV_DRP // 0x088 read-modify-write-readback
PROGRAM_MMCM_DRP
RELEASE_CPLL_RESET
WAIT_CPLL_LOCK
RELEASE_GT_RESET_FOR_MMCM_INPUT
WAIT_MMCM_RESET_RELEASE
WAIT_MMCM_LOCK
RELEASE_TXUSERRDY
WAIT_TXRESETDONE
WAIT_GT_READY
VERIFY_TXUSRCLK2_FREQ
UPDATE_CURRENT_RATE
DONE / ERROR
```

实现时可以合并部分状态，但报告和 ILA 必须能区分：

- CPLL DRP 是否写过；
- CPLL readback 是否匹配；
- CPLL reset 是否释放；
- CPLL lock 是否恢复；
- MMCM lock 是否恢复；
- txresetdone / gt_ready 是否恢复。

## 9. 结论

本轮 read-only 确认结果：

| 项目 | 结论 |
---|---|
| `CPLL_REFCLK_DIV` DRP address / bitfield | 已确认：`0x05E[12:8]` |
| `CPLL_FBDIV_45` DRP address / bitfield | 已确认：`0x05E[7]` |
| `CPLL_FBDIV` DRP address / bitfield | 已确认：`0x05E[6:0]` |
| `TXOUT_DIV` DRP address / bitfield | 已确认：`0x088[6:4]` |
| readback mask | CPLL divider：`0x1FFF`；TXOUT_DIV：`0x0070` |
| CPLL lock 观测 | 已存在：`cplllock_sync` |
| CPLL reset 控制 | GT port 存在，但当前 rate controller 未独立控制 |
| 是否可以直接加入 CPLL 参数 profile | 不可以，只写 DRP 不安全 |
| 是否可以进入下一阶段实现 | 可以，但必须先加入最小 CPLL reset/relock hook |

当前不生成 bit/LTX，不做上板验证，不声明新增 CPLL 参数 profile 已通过。


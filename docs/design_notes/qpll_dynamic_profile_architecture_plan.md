# QPLL dynamic profile architecture plan

## 1. 背景

10G profile 已确认需要 QPLL，不属于当前 125MHz REFCLK + CPLL profile 的普通扩展。当前 500M / 1000M / 1250M / 2000M / 2500M / 3125M / 5000M / 6250M 已经验证的是 CPLL dynamic executor 链路：

```text
target rate
-> CPLL/TXOUT_DIV/MMCM DRP
-> reset release
-> MMCM lock
-> GT ready
-> txusrclk2 frequency verify
-> current_rate update
```

10G 不能直接套用这条 CPLL-only 链路。它需要在 GT wrapper、PLL select、reset/lock/status、ILA 和 Vitis 状态回读上增加 QPLL 结构。

## 2. 为什么当前不能直接加入 10G

当前主工程不具备以下必要结构：

- `GTXE2_COMMON`；
- `QPLLCLK` / `QPLLREFCLK` 到 channel 的真实连接；
- `QPLLLOCK` 观测路径；
- `QPLLRESET` 控制路径；
- `TXSYSCLKSEL` / PLL select 动态控制；
- QPLL lock wait / timeout / error_code；
- QPLL debug probe；
- QPLL status UDP 回读。

因此，如果现在把 10G 直接加入 profile table，会出现两个危险结果：

1. 软件显示支持 10G，但硬件没有 QPLL 执行路径；
2. rate controller 可能只看 CPLL/MMCM/GT ready，误把错误 PLL 路径当成成功。

## 3. 推荐架构升级方向

### 3.1 GT wrapper 层

需要重新生成或扩展 GT Wizard wrapper，使其至少支持：

- TX QPLL；
- `GTXE2_COMMON`；
- QPLL out clock / refclk；
- QPLL reset / lock；
- TX PLL select；
- 10G 所需 line rate 和 user clocking。

如果继续使用单通道 TX-only，需要明确 QPLL common 与 channel 的位置约束和连接方式。

### 3.2 rate controller 层

需要把当前 CPLL-only executor 扩展为 PLL-aware executor：

```text
QUIESCE_TX
ASSERT_RESET
SELECT_PLL_PROFILE
PROGRAM_QPLL_OR_CPLL
WAIT_PLL_LOCK
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

新增状态或子流程不应破坏已有 CPLL profiles。`current_rate`、`active_pll_type`、`active_qpll_profile` 必须只在 `VERIFY_RATE` 成功后更新。

### 3.3 debug / status 层

AXI/FCLK ILA 至少需要增加：

- `pll_type`；
- `qpll_required`；
- `qpll_lock`；
- `qpll_reset`；
- `cpll_lock`；
- `cpll_reset`；
- `TXSYSCLKSEL` / `TXPLLCLKSEL`；
- QPLL DRP / readback，如果后续使用 QPLL DRP；
- `txusrclk2_freq_counter_axi`。

UDP status 应增加 QPLL 状态和错误码，例如：

- `QPLL_LOCK_TIMEOUT`；
- `PLL_SELECT_FAILED`；
- `10G_FREQ_OUT_OF_WINDOW`。

### 3.4 Vitis / UDP 层

在 wrapper 未升级前：

- `rate list` 不加入 10000；
- `rate plan 10000` 可以返回 blocked / requires QPLL wrapper support；
- `rate set 10000` 应保持 unsupported 或 blocked，不写 PL request。

在 wrapper 升级并验证后：

- 才允许加入 `rate list`；
- 才允许 `rate set 10000`；
- 必须保留 `VERIFY_RATE`，不能只看 QPLL lock / GT ready。

## 4. frequency counter 位宽要求

若 10G profile 的 `TXUSRCLK2 = 156.25MHz`，约 1ms 统计窗口下计数约为：

```text
156250
```

因此需要确认：

- `txusrclk2_freq_counter_axi` 位宽足够；
- expected min/max window 位宽足够；
- compare path 不截断；
- ILA probe 能显示完整计数值。

不允许用 `65535` 截断，也不允许跳过 frequency verify。

## 5. 推荐执行顺序

1. 生成或扩展 QPLL-capable GT Wizard wrapper；
2. 独立确认 QPLL ports、GTXE2_COMMON、TXSYSCLKSEL、QPLLLOCK、QPLLRESET；
3. 加入 QPLL debug-only probe；
4. 先 build，不加入 `rate set 10000`；
5. 确认 Hardware Manager / ILA 能观察 QPLL；
6. 再实现 10G profile table 和 PLL-aware executor；
7. 运行 synth / impl / bit / ltx；
8. 上板验证 `rate set 10000`；
9. 再验证 10G 与 CPLL profiles 的往返切换。

## 6. 边界声明

本计划不是 10G 已实现，也不是 QPLL dynamic profile 已通过。它只定义从当前 CPLL-only executor 走向 10G QPLL profile 所需的结构升级。

在 QPLL wrapper 和 reset/lock/status 链路完成前，当前 supported profile 应保持为已验证的 CPLL profiles。

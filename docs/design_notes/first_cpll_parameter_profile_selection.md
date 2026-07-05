# 首个 CPLL 参数变化 dynamic profile 选择建议

## 1. 目标

本文件用于选择第一个加入现有 dynamic profile table 的“CPLL 参数变化”代表速率。该阶段不新建 static board 工程，不引入 156.25MHz REFCLK，不接 AD9528，不切 QPLL，不做任意速率或宽范围连续调速。

当前目标不是一次性加入所有 125MHz CPLL 速率，而是先选择一个最小风险 profile，验证：

- CPLL divider DRP；
- CPLL reset / relock；
- GT TX reset / TXUSERRDY；
- MMCM DRP；
- txusrclk2 频率窗口；
- UDP `rate set` / `rate status`；
- AXI/FCLK ILA 证据链。

## 2. 当前已完成基线

| rate | REFCLK | PLL | M | N1 | N2 | CPLLCLKOUT | TXOUT_DIV | TXUSRCLK2 expected | 当前状态 |
|---:|---:|---|---:|---:|---:|---:|---:|---:|---|
| 500M | 125MHz | CPLL | 1 | 4 | 4 | 2.000GHz | 8 | 7.8125MHz | dynamic 已验证 |
| 1000M | 125MHz | CPLL | 1 | 4 | 4 | 2.000GHz | 4 | 15.625MHz | dynamic 已验证 |
| 2000M | 125MHz | CPLL | 1 | 4 | 4 | 2.000GHz | 2 | 31.25MHz | dynamic 已验证 |

上述三档只改变 `TXOUT_DIV` 和 MMCM，不改变 CPLL divider。因此它们证明了动态执行链路基础可用，但没有证明 CPLL 参数变化 profile 可用。

## 3. 候选 profile 对比

根据 `D:/FPGA_Learn/project_gtx/drp.txt` 中 125MHz REFCLK 的 CPLL 匹配结果，优先考虑仍使用 CPLL、仍使用 125MHz REFCLK、且不需要 QPLL / AD9528 / 156.25MHz 的候选。

| 候选 rate | M | N1 | N2 | CPLLCLKOUT | TXOUT_DIV | TXUSRCLK2 expected | 优点 | 风险 |
|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1.25G | 1 | 4 | 5 | 2.500GHz | 4 | 19.53125MHz | 第一个测试 N2=5；TXOUT_DIV=4 已在 1000M 路径用过；TXUSRCLK2 适中 | 需要 CPLL DRP + CPLL reset/relock；MMCM DRP 需新增 |
| 2.5G | 1 | 4 | 5 | 2.500GHz | 2 | 39.0625MHz | 同样测试 N2=5；可复用 1.25G 的 CPLL 参数 | TXUSRCLK2 更高，对 laser_tx_core / timing / ILA 采样更激进 |
| 3.0G | 1 | 4 | 3 | 1.500GHz | 1 | 46.875MHz | 测试 N2=3 | CPLLCLKOUT 低于当前基线，TXUSRCLK2 更高，非首选 |
| 3.125G | 1 | 5 | 5 | 3.125GHz | 2 | 48.828125MHz | 覆盖 N1=5/N2=5 | 同时改变 N1/N2，TXUSRCLK2 更高，风险更大 |

## 4. 推荐选择：1.25G

推荐第一个 CPLL 参数变化 profile 选择：

```text
rate_mbps          = 1250
refclk_id          = REFCLK_125M
refclk_freq_hz     = 125000000
pll_type           = CPLL
CPLL_REFCLK_DIV/M  = 1
CPLL_FBDIV_45/N1   = 4
CPLL_FBDIV/N2      = 5
CPLLCLKOUT         = 2.500GHz
TXOUT_DIV          = 4
TXUSRCLK           = 39.0625MHz
TXUSRCLK2          = 19.53125MHz
AD9528 dynamic     = 0
QPLL               = not used
156.25MHz refclk   = not used
```

选择 1.25G 的原因：

1. 它与当前 500M / 1000M / 2000M 一样使用 125MHz REFCLK + CPLL；
2. 它只需要把 CPLL N2 从 4 改为 5，N1 与 M 仍保持当前值；
3. 它的 TXOUT_DIV=4，当前 1000M 已经验证过 TXOUT_DIV=4 的 DRP encoding 与 readback；
4. 它的 `TXUSRCLK2=19.53125MHz`，低于 2G 的 31.25MHz 与 2.5G 的 39.0625MHz，作为第一档 CPLL 参数变化 bring-up 风险较低；
5. 它能直接验证新增 CPLL DRP / reset / relock hook，而不会同时引入过高用户时钟压力。

## 5. 2.5G 作为 fallback / 第二阶段候选

如果 1.25G 的 CPLL 参数确认、MMCM DRP 和 reset/relock 上板通过，则 2.5G 可以作为第二个候选：

```text
rate_mbps          = 2500
refclk_id          = REFCLK_125M
CPLL_REFCLK_DIV/M  = 1
CPLL_FBDIV_45/N1   = 4
CPLL_FBDIV/N2      = 5
TXOUT_DIV          = 2
TXUSRCLK2          = 39.0625MHz
```

2.5G 与 1.25G 复用同一组 CPLL 参数，只改变 TXOUT_DIV 与 MMCM 输出关系，因此适合在 1.25G 通过后继续验证。但不建议作为第一档，因为它对 `laser_tx_core`、timing 和 ILA 采样窗口压力更高。

## 6. 进入 RTL 实现前必须补齐的内容

在把 1.25G 加入 dynamic profile table 前，必须完成：

1. 增加 `rate_cpll_reset` 或等价 CPLL reset hook；
2. 增加 CPLL DRP sequence：`0x05E` read-modify-write-readback；
3. 增加 CPLL readback mask/value；
4. 增加 CPLL reset hold / release / wait lock 子状态；
5. 增加 CPLL timeout / readback mismatch error code；
6. 增加 AXI/FCLK ILA debug-only probes：
   - CPLL DRP addr/di/do/en/we/rdy；
   - CPLL DRP busy/done/error；
   - cpll_reset_rate；
   - cplllock_sync；
   - CPLL readback value；
7. 新增 1.25G MMCM DRP sequence，并说明参数来源；
8. 新增 1.25G `txusrclk2_freq_counter_axi` 初始窗口；
9. Vitis / UDP 如当前 rate list / parser 只列 500/1000/2000，则增加 `1250`，但不改变协议形态。

## 7. 边界声明

本选择建议不表示 1.25G 已经实现或上板通过。

当前仍然不支持：

- 任意连续速率；
- 宽范围自动参数生成；
- 156.25MHz REFCLK；
- AD9528 动态输出；
- QPLL 切换；
- 外部光口误码率或长期稳定性结论。

推荐下一步是：在 `feature/cpll-dynamic-drp-profile` 分支上，以 1.25G 为第一个 CPLL 参数变化 profile，先实现最小 CPLL reset/relock + CPLL DRP executor，再 build / timing / UDP + ILA 上板验证。


# 125MHz REFCLK 经典 CPLL 速率 profile 候选矩阵

## 1. 目标与边界

本文件用于梳理当前 `laser_tx` 工程在 125MHz REFCLK、CPLL、固定 REFCLK 架构下，哪些经典 line rate 可以安全进入后续 dynamic profile table，哪些只能停留在候选或跳过状态。

本轮是 read-only feasibility / screening，不修改：

- RTL；
- BD；
- XDC；
- GT Wizard 主工程配置；
- Vitis / UDP 协议；
- AD9528；
- 156.25MHz REFCLK；
- QPLL；
- `laser_tx_core` / `pattern_tx_engine`。

结论基于当前工程文件、既有 500M/1000M/2000M 验证报告、当前 GT Wizard XCI、`project_gtx` 参考 line-rate 搜索结果，以及当前 dynamic rate controller 的结构检查。本文不是新的 bitstream build 报告，也不是上板验证报告。

## 2. 已验证基线

当前已经完成上板验证的 dynamic profiles 为：

| profile | line rate | REFCLK | PLL | CPLL M / N1 / N2 | TXOUT_DIV | TXUSRCLK | TXUSRCLK2 | 当前状态 |
|---|---:|---:|---|---|---:|---:|---:|---|
| 500M | 0.500Gbps | 125MHz | CPLL | 1 / 4 / 4 | 8 | 15.625MHz | 7.8125MHz | 已实现、已上板初步验证 |
| 1000M | 1.000Gbps | 125MHz | CPLL | 1 / 4 / 4 | 4 | 31.25MHz | 15.625MHz | 已实现、已上板初步验证 |
| 2000M | 2.000Gbps | 125MHz | CPLL | 1 / 4 / 4 | 2 | 62.5MHz | 31.25MHz | 已实现、已上板初步验证 |

这三档的共同点是：

- REFCLK 固定为 125MHz；
- CPLL feedback / refclk divider 参数不变；
- GT 侧只需要切换 TXOUT_DIV；
- MMCM DRP 表已经按对应 TXOUTCLK/TXUSRCLK/TXUSRCLK2 生成并完成初步验证；
- reset sequence、MMCM lock、GT ready、txusrclk2 frequency verify 已经在当前三档内闭环跑通。

因此当前 dynamic executor 的可靠边界是：

```text
固定 125MHz REFCLK
固定 CPLL 参数 M=1, N1=4, N2=4
只动态修改 GTX TXOUT_DIV + TX user clock MMCM
```

## 3. 候选速率矩阵

下表中的 CPLL 候选来自 `D:/FPGA_Learn/project_gtx/drp.txt` 中 125MHz REFCLK 搜索结果。对于同一速率存在多组 CPLL 解的情况，表中优先列出与当前工程最接近、或能覆盖同族速率的一组；但是否可加入 dynamic profile table，必须以“当前工程能否可靠执行所需 DRP”为准。

| rate | 125MHz CPLL/QPLL 搜索结果摘要 | 与当前 500/1000/2000 CPLL 参数相同 | 是否只需 TXOUT_DIV | TXUSRCLK2 理论值 | 本轮结论 | 原因 |
|---:|---|---|---|---:|---|---|
| 0.500G | CPLL M=1, N1=4, N2=4, TXOUT_DIV=8 | 是 | 是 | 7.8125MHz | 已支持 | 当前 Profile0，已验证 |
| 1.000G | CPLL M=1, N1=4, N2=4, TXOUT_DIV=4 | 是 | 是 | 15.625MHz | 已支持 | 当前 Profile1，已验证 |
| 1.250G | 可用 CPLL，例如 M=1, N1=4, N2=5, TXOUT_DIV=4；也存在其它 CPLL 解 | 否 | 否 | 19.53125MHz | 暂不加入 | 需要动态修改 CPLL feedback 参数；当前工程只验证了 TXOUT_DIV DRP |
| 2.000G | CPLL M=1, N1=4, N2=4, TXOUT_DIV=2 | 是 | 是 | 31.25MHz | 已支持 | 当前 Profile2，已验证 |
| 2.500G | 可用 CPLL，例如 M=1, N1=4, N2=5, TXOUT_DIV=2；也存在其它 CPLL 解 | 否 | 否 | 39.0625MHz | 暂不加入 | 需要动态修改 CPLL feedback 参数；CPLL DRP sequence 尚未在本工程确认 |
| 3.000G | 可用 CPLL M=1, N1=4, N2=3, TXOUT_DIV=1 | 否 | 否 | 46.875MHz | 暂不加入 | 需要 CPLL 参数变化，且 N2=3 组合需 GT Wizard/XCI 进一步确认 |
| 3.125G | 可用 CPLL，例如 M=1, N1=5, N2=5, TXOUT_DIV=2 | 否 | 否 | 48.828125MHz | 暂不加入 | 需要 CPLL 参数变化；当前不做 CPLL DRP 动态切换 |
| 5.000G | 可用 CPLL，例如 M=1, N1=4, N2=5, TXOUT_DIV=1 | 否 | 否 | 78.125MHz | 暂不加入 | 需要 CPLL 参数变化；更高 TXUSRCLK2 也需 static profile/timing/ILA 先验证 |
| 6.250G | 可用 CPLL，例如 M=1, N1=5, N2=5, TXOUT_DIV=1 | 否 | 否 | 97.65625MHz | 暂不加入 | 需要 CPLL 参数变化；更高 TXUSRCLK2 和 GT/MMCM timing 风险需先静态验证 |
| 10.000G | 125MHz 搜索中主要落入 QPLL 解 | 否 | 否 | 156.25MHz | 跳过 | 超出本轮 CPLL-only / no-QPLL / no-refclk-switch 边界 |

## 4. 为什么本轮不新增 1.25G / 2.5G / 3G / 3.125G / 5G / 6.25G

这些速率在 125MHz REFCLK 下并非完全不可达。关键问题是：它们不再属于当前已经验证的 “固定 CPLL 参数 + TXOUT_DIV 切换” 范围。

当前工程已经验证的 GT DRP 侧修改是：

```text
GTX DRP address 0x088
TXOUT_DIV field [6:4]
TXOUT_DIV=8 / 4 / 2
```

而 1.25G、2.5G、3G、3.125G、5G、6.25G 等速率需要修改 CPLL feedback / divider 相关参数。这意味着至少要新增：

- CPLL DRP address / bitfield 确认；
- CPLL parameter readback；
- CPLL reset / relock sequence；
- 与 MMCM DRP 的顺序关系；
- 不同 CPLLCLKOUT 下 TXOUTCLK / MMCM input 的稳定性验证；
- 对应 static profile build 和上板 bring-up。

如果在没有上述确认的情况下直接把这些速率加入 `rate set`，失败时将无法区分是 CPLL DRP、MMCM DRP、reset sequence、频率窗口、GT ready 还是软件 profile 映射的问题。因此本轮筛选结果是：保留为候选，不进入 RTL/Vitis supported profile list。

## 5. MMCM / TX user clocking 影响

在 `TXDATA=64bit`、`TX internal datawidth=32-bit`、`encoding=None` 的当前语义下，可以按以下关系理解：

```text
TXUSRCLK  = line_rate / 32
TXUSRCLK2 = line_rate / 64
laser_tx_core 工作在 TXUSRCLK2 域
```

候选速率对应的理论 TX user clock 如下：

| line rate | TXOUTCLK / TXUSRCLK | TXUSRCLK2 | 说明 |
|---:|---:|---:|---|
| 0.500G | 15.625MHz | 7.8125MHz | 已支持 |
| 1.000G | 31.25MHz | 15.625MHz | 已支持 |
| 1.250G | 39.0625MHz | 19.53125MHz | 候选，需要 static MMCM 参数 |
| 2.000G | 62.5MHz | 31.25MHz | 已支持 |
| 2.500G | 78.125MHz | 39.0625MHz | 候选，需要 static MMCM 参数 |
| 3.000G | 93.75MHz | 46.875MHz | 候选，需要 static MMCM 参数 |
| 3.125G | 97.65625MHz | 48.828125MHz | 候选，需要 static MMCM 参数 |
| 5.000G | 156.25MHz | 78.125MHz | 候选，需先评估 `laser_tx_core` timing 和 ILA/debug 影响 |
| 6.250G | 195.3125MHz | 97.65625MHz | 候选，需先评估更高 TXUSRCLK2 timing 风险 |
| 10.000G | 312.5MHz | 156.25MHz | 本轮跳过，涉及 QPLL/更高频率架构 |

这些理论值只能用于规划。真正加入 dynamic profile 前，每一档都必须有来源明确的 static user clocking / MMCM DRP 参数，不能只按比例手猜写表。

## 6. 当前建议的扩展路线

本轮不建议直接修改 RTL/Vitis 增加新 profile。更稳妥的下一步是把“CPLL 参数可动态修改”作为一个单独阶段：

1. 选择一档需要改变 CPLL 参数、但风险最低的速率做 static profile，例如 1.25G 或 2.5G；
2. 用 GT Wizard 生成对应 XCI/generated HDL/example design；
3. 提取 CPLL primitive 参数、TXOUT_DIV、MMCM 参数；
4. 只读确认 CPLL DRP address/bitfield 和 readback；
5. 做 CPLL DRP 单元级验证；
6. 再把该速率加入 dynamic profile table；
7. 按一条路径先验证，例如 500M -> 1.25G 或 500M -> 2.5G；
8. 最后再扩展到同族速率。

换句话说，本轮筛选之后的真实工程边界是：

```text
当前 dynamic profile table 已覆盖 500M / 1000M / 2000M。
继续扩展 125MHz CPLL 经典速率，需要先补齐 CPLL DRP 动态修改能力。
在 CPLL DRP 未确认前，不应把 1.25G / 2.5G / 3G / 3.125G / 5G / 6.25G 写入 supported profile。
10G 不属于本轮 CPLL-only 范围。
```

## 7. 结论

本轮候选矩阵结论如下：

- 500M / 1000M / 2000M：已支持，继续作为当前通过基线；
- 1.25G / 2.5G / 3G / 3.125G / 5G / 6.25G：125MHz REFCLK 下存在 CPLL 候选解，但需要动态修改 CPLL 参数，本轮不加入；
- 10G：本轮跳过，涉及 QPLL 或更高复杂度架构；
- 本轮不修改 RTL/Vitis，不生成新的 bit/LTX，不声明新增速率已实现。

建议后续把下一阶段命名为：

```text
125MHz CPLL parameter DRP confirmation and first non-TXOUT_DIV-only static/dynamic profile
```

而不是直接叫“宽范围速率完成”。这样更符合当前工程已经验证的能力边界。

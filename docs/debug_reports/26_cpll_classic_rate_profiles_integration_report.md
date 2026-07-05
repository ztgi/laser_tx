# 125MHz CPLL 经典速率 profile 扩展筛选报告

## 1. 本阶段目标与边界

本阶段原目标是在当前已经通过的 500M / 1000M / 2000M 三档 dynamic profile 基础上，评估是否可以继续加入 125MHz REFCLK 下的经典 CPLL 速率 profile。

本轮实际执行结果是：先完成候选速率矩阵和工程可行性筛选，暂不修改 RTL/Vitis，也不新增 supported rate。原因是除 500M / 1000M / 2000M 以外的候选速率不再是“只改 TXOUT_DIV”的同 CPLL 参数切换，而是需要动态修改 CPLL feedback / divider 参数。当前工程尚未完成 CPLL 参数 DRP address/bitfield、readback 和 reset/relock sequence 的确认。

本轮没有修改：

- RTL；
- BD；
- XDC；
- GT Wizard 主工程 XCI；
- Vitis / UDP 协议；
- AD9528；
- 156.25MHz REFCLK；
- QPLL；
- `laser_tx_core` / `pattern_tx_engine`；
- ILA probe。

## 2. 当前已验证基础

当前工程已经具备并完成初步上板验证的动态速率为：

| profile | rate | REFCLK | PLL | CPLL M/N1/N2 | TXOUT_DIV | 状态 |
|---|---:|---:|---|---|---:|---|
| Profile0 | 500M | 125MHz | CPLL | 1/4/4 | 8 | 已实现、已验证 |
| Profile1 | 1000M | 125MHz | CPLL | 1/4/4 | 4 | 已实现、已验证 |
| Profile2 | 2000M | 125MHz | CPLL | 1/4/4 | 2 | 已实现、已验证 |

这三档的共同特征是：CPLL 参数保持不变，仅改变 GTX TXOUT_DIV，并同步切换 TX user clock MMCM 参数。当前 reset sequence、MMCM lock wait、GT ready wait、txusrclk2 frequency verify 和 `current_rate` 更新流程均围绕这个边界完成验证。

## 3. 候选速率筛选结果

详细候选矩阵见：

```text
docs/design_notes/cpll_classic_rate_profile_matrix_125m.md
```

筛选摘要如下：

| rate | 筛选结果 | 主要原因 |
|---:|---|---|
| 500M | 保留已支持 | 已验证基线 |
| 1000M | 保留已支持 | 已验证基线 |
| 1250M | 暂不加入 | 需要 CPLL 参数 DRP，不是 TXOUT_DIV-only |
| 2000M | 保留已支持 | 已验证基线 |
| 2500M | 暂不加入 | 需要 CPLL 参数 DRP，不是 TXOUT_DIV-only |
| 3000M | 暂不加入 | 需要 CPLL 参数 DRP，且候选 N2=3 需 GT Wizard 进一步确认 |
| 3125M | 暂不加入 | 需要 CPLL 参数 DRP，不是 TXOUT_DIV-only |
| 5000M | 暂不加入 | 需要 CPLL 参数 DRP，且更高 TXUSRCLK2 需 static/timing/ILA 验证 |
| 6250M | 暂不加入 | 需要 CPLL 参数 DRP，且更高 TXUSRCLK2 需 static/timing/ILA 验证 |
| 10000M | 跳过 | 不属于本轮 CPLL-only / no-QPLL 边界 |

## 4. 为什么本轮没有新增 RTL profile

当前 dynamic controller 的 GT DRP 能力已经验证到：

```text
GTX DRP address = 0x088
TXOUT_DIV field = [6:4]
TXOUT_DIV=8 / 4 / 2
```

而本轮剩余候选速率需要的不只是 TXOUT_DIV：

- 1.25G / 2.5G / 5G 常见候选需要 CPLLCLKOUT=2.5GHz；
- 3.0G 候选需要 CPLLCLKOUT=1.5GHz；
- 3.125G / 6.25G 候选需要 CPLLCLKOUT=3.125GHz；
- 10G 已超出当前 CPLL-only 目标。

这意味着必须先确认 CPLL DRP 写入地址、bitfield、readback、reset/relock sequence，以及它与当前 MMCM DRP/reset sequence 的先后关系。直接把这些速率写进 profile table，会把“未确认 CPLL DRP”伪装成“普通 profile 扩展”，后续上板失败时无法定位。

## 5. 本轮实际修改内容

本轮只新增文档：

| 文件 | 内容 |
|---|---|
| `docs/design_notes/cpll_classic_rate_profile_matrix_125m.md` | 125MHz REFCLK 下经典 CPLL 候选速率矩阵、筛选结论和后续路线 |
| `docs/debug_reports/26_cpll_classic_rate_profiles_integration_report.md` | 本轮筛选报告和工程边界说明 |

未修改 RTL、Vitis、BD、XDC、GT Wizard、ILA probe 或 build 脚本。

## 6. 构建与测试验证

本轮没有修改可综合逻辑或软件源代码，因此没有重新运行：

- synthesis；
- implementation；
- write_bitstream；
- write_debug_probes；
- Vitis build；
- hardware test。

明确记录：

```text
Synthesis/implementation was not run.
Vitis build was not run.
Hardware test was not run.
No new bit/LTX was generated.
```

## 7. 当前结论

当前 500M / 1000M / 2000M 三档 profile 仍然是工程中唯一应声明 supported 的 dynamic rate set。

本轮不建议新增 1.25G / 2.5G / 3G / 3.125G / 5G / 6.25G，因为它们需要 CPLL 参数动态修改，而当前工程尚未验证 CPLL DRP 参数写入与 relock 流程。

因此本阶段结论是：

```text
125MHz REFCLK 下存在更多 CPLL 候选速率，但当前 dynamic executor 只验证了 TXOUT_DIV-only profile。
在 CPLL DRP 动态修改能力完成前，不应把新增经典 CPLL 速率加入 supported profile table。
```

## 8. 下一步建议

建议下一阶段不要直接“大包围”加入所有速率，而是单独推进：

```text
125MHz CPLL parameter DRP confirmation
```

推荐顺序：

1. 选择一档需要 CPLL 参数变化、风险较低的速率，例如 1.25G 或 2.5G；
2. 生成独立 static GT Wizard profile；
3. 提取 XCI/generated HDL/example design 参数；
4. 确认 CPLL DRP address/bitfield/readback；
5. 做 static build / timing / ILA；
6. 做 CPLL DRP 单元级验证；
7. 再加入 dynamic profile table；
8. 最后做路径验证。

这样可以保持当前 500M / 1000M / 2000M 成功基线不被污染，同时让新增速率失败时有明确归因。

## 9. 边界声明

本轮不证明：

- 1.25G / 2.5G / 3G / 3.125G / 5G / 6.25G dynamic switching 已实现；
- CPLL 参数 DRP 已实现；
- 10G/QPLL 支持已实现；
- 156.25MHz REFCLK 支持已实现；
- AD9528 动态输出已实现；
- 宽范围动态调速已完成；
- 任意连续速率可调。

本轮只完成候选矩阵与工程可行性筛选。

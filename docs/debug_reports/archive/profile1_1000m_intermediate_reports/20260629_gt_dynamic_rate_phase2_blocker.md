# GT 动态速率第二阶段阻塞调试报告

## 1. 本轮问题现象

用户要求从第一阶段 dry-run 进入第二阶段真实硬件切换，优先实现：

```text
rate set 500
rate set 1000
500 Mb/s <-> 1000 Mb/s
```

任务书同时要求：如果 500M/1000M 不能安全共用当前 CPLL/本地 REFCLK/clocking 方案，则停止并报告，不要硬写 DRP。

本轮核查后停止，没有实现真实 `rate set`。

## 2. 当前已通过的层级

| 层级 | 状态 |
|---|---|
| Profile 0 固定 500M 有效发送 | 已上板 ILA 收口 |
| 第一阶段 `gt_rate_plan()` | 已完成 |
| UDP `rate status` / `rate plan` | 已编译进 ELF |
| GT status GPIO | 已存在 |
| AD9528 SPI/readback 软件接口 | 已存在 |

## 3. 当前未通过的层级

| 层级 | 状态 |
|---|---|
| 真实 GT DRP 写入 | 未实现 |
| channel DRP 暴露给 rate controller | 当前未暴露 |
| common/QPLL DRP 暴露 | 当前未暴露 |
| 1000M GT Wizard/example design | 当前未生成/未核查 |
| 1000M TXUSRCLK/TXUSRCLK2 clocking | 当前未实现 |
| 多速率 XDC/timing | 当前未实现 |
| `rate set 500/1000` 真入口 | 未实现 |

## 4. 根因假设

阻塞点不是 UDP 命令解析，而是硬件工程条件不满足：

1. 当前 `laser_gt_tx_profile0.v` 中 DRP 输入被 tie-off；
2. 当前 `laser_gt_usrclk_profile0.v` 是 500M Profile 0 专用 MMCM；
3. 当前 `gt_profile0_impl_pre.tcl` 强制检查 500M 的 64 ns / 128 ns 时钟周期；
4. 当前没有 1000M XCI/example design 证明应写哪些 DRP bitfield；
5. 当前没有 `txusrclk2_divided_debug` 证明切速率后用户时钟真的变化。

## 5. 本轮修改内容

本轮只新增文档报告，没有修改 RTL/BD/XDC/Vitis 源码。

| 文件 | 修改内容 |
|---|---|
| `D:/FPGA_Learn/laser_tx/docs/gt_dynamic_rate_phase2_cpll_local_refclk_blocker.md` | 新增阶段二真实切换阻塞报告 |
| `D:/FPGA_Learn/laser_tx/docs/debug_reports/20260629_gt_dynamic_rate_phase2_blocker.md` | 新增本轮调试报告 |

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| RTL | 未改 | 未改 | Profile 0 不受影响 |
| BD/wrapper | 未改 | 未改 | 不新增接口，不改时钟 |
| XDC | 未改 | 未改 | timing 仍是 Profile 0 |
| Vitis C | 未改 | 未改 | `rate set` 仍未真实启用 |
| DRP 写表 | 无 | 无 | 不硬写未知 bitfield |
| 文档 | 无阶段二 blocker 报告 | 新增 blocker 报告 | 明确下一步前置条件 |

## 7. 为什么这样修改

任务书要求真实切换必须安全闭环，且 `rate set` 返回 OK 时必须代表硬件真的切换完成。

当前条件下如果直接把 `rate set 1000` 接到 DRP 写入，会产生三个严重风险：

1. DRP 地址/数据未验证，可能写坏 GTX channel 配置；
2. 即使 CPLL lock，TXUSRCLK/TXUSRCLK2 也可能不匹配 64-bit 数据语义；
3. 如果失败，没有 rollback 回到 fixed Profile 0 的可靠路径。

因此本轮正确动作是停止并报告，而不是写一个不可靠的 `laser_gt_rate_ctrl`。

## 8. 硬件接口一致性说明

本轮明确未修改：

```text
未修改 RTL
未修改 BD
未修改 wrapper
未修改 XDC
未修改 GT Wizard
未修改 txusrclk2
未写 GT DRP
未配置 AD9528 动态 clock-tree
未做 GTX 动态改速率
未改变 Profile 0 固定发送链路
未改变 GPIO / BRAM / GT status 地址
```

## 9. 构建验证记录

Build was not run.

原因：本轮没有修改 RTL、BD、XDC、wrapper、Vitis C 或 BSP，只新增文档报告。无需重新综合、实现或编译 ELF。

## 10. 上板验证记录

Hardware test was not run.

本轮没有生成新的 bitstream/ltx/xsa，也没有新的 ELF 行为需要上板验证。

## 11. 当前分层结论

| 层级 | 结论 |
|---|---|
| Profile 0 固定 500M | 保留，未修改 |
| 第一阶段 dry-run | 保留，未修改 |
| 500M -> 1000M 真实切换 | 未实现 |
| 1000M -> 500M 回退 | 未实现 |
| channel DRP | IP 层存在，wrapper 未暴露 |
| common/QPLL DRP | 当前 laser_tx 工程未暴露 |
| TXUSRCLK/TXUSRCLK2 动态关系 | 未实现 |
| AD9528 动态配置 | 未涉及 |

## 12. 风险说明

1. 不能用参考工程中的 DRP 地址直接写当前 `laser_tx`，必须先由当前 GT Wizard/example design 生成对比确认；
2. 当前 `laser_gt_usrclk_profile0.v` 是 Profile 0 专用，不能自然覆盖 1000M；
3. 当前 timing hook 固定检查 Profile 0 的 64/128 ns 周期；
4. 后续一旦暴露 DRP 和新增 rate controller，将同时触及 RTL、BD/XDC、wrapper/XSA、Vitis，必须按 AGENTS.md Section 1/2/3 全部报告。

## 13. 下一步建议

建议下一轮不要直接写 DRP，而是先做“阶段二前置设计包”：

1. 新建 1000M GT Wizard 配置或 example design，用 Vivado 输出真实 1000M 参数；
2. 对比 500M/1000M generated HDL，得到官方确认的 DRP bitfield；
3. 设计动态 TX user clocking：明确 500M/1000M 下 TXOUTCLK、TXUSRCLK、TXUSRCLK2；
4. 制定 `laser_gt_rate_ctrl` RTL 接口、rate control/status register map、ILA probe；
5. 制定 wrapper/BD/XDC/XSA/Vitis platform 更新计划；
6. 经用户确认后，再进入真实 RTL/BD 实现。

# GT 动态速率第二阶段前置设计包调试报告

## 1. 本轮问题现象

第一阶段 dry-run 已经完成 `gt_rate_plan()`、`rate status`、`rate plan <Mbps>` 的软件规划链路，但第二阶段仍不能直接实现 `rate set 500/1000`，原因是当前缺少当前工程对应的 1000M GT Wizard 对比证据、GTX DRP address/bitfield 证据，以及动态 TX user clocking 方案。

用户明确要求：

- 不直接实现 `rate set 500/1000`；
- 不硬写 GTX DRP；
- 不破坏当前已验证的固定 500 Mb/s Profile 0；
- 先完成 1000M 对比、clocking 方案、rate_ctrl 草案和工程影响分析。

## 2. 当前已通过的层级

当前固定 Profile 0 已在前序阶段完成有效发送 case 上板 ILA 验证。本轮只做离线工程设计包生成。

本轮已完成：

- 隔离生成 1000M GT Wizard TX 对比工程；
- 生成 1000M output products；
- 生成 1000M example design；
- 提取 500M 与 1000M TX user clocking MMCM 参数；
- 确认当前主工程 Profile 0 生成文件仍为 500M；
- 生成阶段二前置设计包 Markdown。

## 3. 当前未通过或未确认的层级

- 未实现真实 GTX DRP 写入；
- 未实现 MMCM DRP；
- 未实现 `rate set 500/1000`；
- 未生成 1000M 主工程 bitstream；
- 未进行 1000M 上板验证；
- 未验证动态 500M ↔ 1000M 切换；
- RX line-rate 对比未形成完整一致结论：selected properties 显示 `gt0_val_rx_line_rate = 0.5`，但 generated HDL 中 `RXOUT_DIV = 4`。

## 4. 根因假设

当前不能直接进入 `rate set` 实现的根因不是 UDP 命令解析，也不是软件 dry-run 状态机，而是硬件速率切换所需的底层时钟与 GT 配置证据不足：

1. 500M 与 1000M 的 GT divider 差异需要从当前 XCI/generated HDL 对比得到；
2. GTX DRP 地址与 bitfield 不能从其他工程直接套用；
3. 1000M 下 TXUSRCLK/TXUSRCLK2 频率变化，现有 `laser_gt_usrclk_profile0.v` 是 500M 专用参数；
4. 若只写 TXOUT_DIV 而不重配 MMCM，会导致 GT user clocking 与 `laser_tx_core` 工作域不自洽。

## 5. 本轮修改内容

本轮新增/修改文件：

```text
scripts/create_gtwizard_1000m_compare.tcl
docs/gt_dynamic_rate_phase2_pre_design_package.md
docs/debug_reports/20260629_gt_dynamic_rate_phase2_pre_design_package.md
```

本轮生成资料目录：

```text
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/
```

### 5.1 `scripts/create_gtwizard_1000m_compare.tcl`

新增隔离 1000M 对比脚本。该脚本：

- 复制当前 Profile 0 XCI 到 `reports/`；
- 重写 copied XCI 的 `gen_directory` / `OUTPUTDIR`，避免 output products 写回当前 `laser_tx.gen`；
- 在隔离 Vivado project 中设置 1000M TX 对比参数；
- 生成 output products；
- 生成 example design；
- 导出 selected properties 报告；
- 不打开、不修改 `laser_tx.xpr`。

### 5.2 `docs/gt_dynamic_rate_phase2_pre_design_package.md`

新增阶段二前置设计包，记录：

- 1000M 对比生成结果；
- 500M/1000M TX 参数差异；
- 官方 example design TX user clocking 差异；
- 候选 DRP 差异表；
- 动态 TXUSRCLK/TXUSRCLK2 方案 A/B/C；
- 推荐方案；
- `laser_gt_rate_ctrl` 接口草案；
- wrapper/BD/XDC/XSA/Vitis 后续更新计划；
- Profile 0 回滚保护。

### 5.3 `docs/debug_reports/20260629_gt_dynamic_rate_phase2_pre_design_package.md`

新增本轮 Markdown 调试报告。

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| 1000M 对比方式 | 无当前工程隔离对比脚本 | 新增 isolated Vivado 对比脚本 | 可重复生成 1000M TX 对比资料 |
| copied XCI output path | 初始脚本曾继承原 `gen_directory`，存在污染风险 | 重写为 `reports/.../generated_ip/gtwizard_0` | 避免写回当前 `laser_tx.gen` |
| selected properties | 初始未输出 RX line-rate 字段 | 增加 `gt0_val_rx_line_rate` | 明确暴露 RX 侧不一致风险 |
| Profile 0 主工程 | 固定 500M 已验证 | 保持 500M；确认 `TXOUT_DIV=8` | 不破坏当前上板验证链路 |
| 动态 DRP 表 | 无当前工程差异表 | 给出基于 generated HDL delta 的候选项 | 仍需 UG476/GT Wizard DRP map 确认 |
| TX user clocking | 只知道 Profile0 固定 MMCM | 提取 500M/1000M 官方 MMCM 参数 | 证明动态速率必须处理 MMCM |
| RTL 功能逻辑 | 已验证 Profile0 发送链路 | 未修改 | 功能链路不受影响 |
| BD/XDC/wrapper/XSA | 现状 | 未修改 | 无硬件平台变化 |
| Vitis 软件 | 现状 | 未修改 | 无软件行为变化 |

## 7. 为什么这样修改

新增对比脚本的目的，是避免在主 Vivado 工程里直接改 GT Wizard IP。1000M 对比必须能复现，但不能污染当前已验证的 500M Profile 0。

重写 copied XCI 的 `gen_directory` / `OUTPUTDIR` 是为了防止 Vivado 将 copied IP 的 output products 生成到原工程 `laser_tx.gen` 下。

补充 `gt0_val_rx_line_rate` 输出，是为了让脚本直接暴露 RX 侧当前解析结果。实际结果显示 TX 已为 1.0，但 RX line-rate 仍为 0.5，因此本轮只把该对比作为 TX 方向规划依据，不能声明 RX/全双工 1000M 已完整确认。

提取 example design MMCM 参数，是为了判断能否只写 GTX divider。结果表明 500M 与 1000M MMCM 参数不同，因此动态速率设计必须把 TX user clocking 纳入状态机。

## 8. 硬件接口一致性说明

本轮明确未修改：

```text
未修改 RTL 功能逻辑
未修改 BD
未修改 XDC
未修改 GT Wizard 主工程 XCI
未修改 wrapper
未修改 XSA
未修改 txusrclk2 当前 Profile0 结构
未修改 Vitis 源码
未做 GTX 动态改速率
未改变 Profile 0 固定发送链路
未改变 GPIO / BRAM / GT status 地址
```

本轮新增脚本只生成隔离 reports 目录下的 GT Wizard comparison 资料。

## 9. 构建验证记录

执行命令：

```powershell
& 'D:\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'D:\FPGA_Learn\laser_tx\scripts\create_gtwizard_1000m_compare.tcl'
```

结果：

```text
INFO: 1000M GT Wizard comparison generation finished.
OK generate_target all
OK open_example_project
```

生成报告：

```text
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/gtwizard_1000m_selected_properties.txt
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/gtwizard_1000m_generation_summary.txt
```

关键 selected properties：

```text
gt0_val_tx_line_rate = 1.0
gt0_val_rx_line_rate = 0.5
gt0_val_tx_data_width = 64
gt0_val_encoding = None
gt0_val_tx_int_datawidth = 32
gt0_val_cpll_fbdiv_45 = 4
gt0_val_cpll_fbdiv = 4
gt0_val_cpll_refclk_div = 1
gt0_val_cpll_txout_div = 4
gt0_val_cpll_rxout_div = 4
```

当前 Profile 0 恢复/保持检查：

```text
laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v:
  CPLL_FBDIV      = 4
  CPLL_FBDIV_45   = 4
  CPLL_REFCLK_DIV = 1
  RXOUT_DIV       = 8
  TXOUT_DIV       = 8

laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.xml:
  gt0_val_tx_line_rate   = 0.5
  gt0_val_rx_line_rate   = 0.5
  gt0_val_cpll_txout_div = 8
  gt0_val_cpll_rxout_div = 8
```

Vivado synthesis / implementation / timing / bitstream：

```text
Synthesis/implementation was not run
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required
Bitstream was not generated
XSA was not exported
```

## 10. 上板验证记录

```text
Hardware test was not run
```

本轮是离线设计包与 Vivado IP comparison 生成，不是上板验证。

## 11. 当前分层结论

| 层级 | 结论 |
| --- | --- |
| 固定 500M Profile0 有效发送链路 | 前序已完成上板 ILA 收口；本轮未改动 |
| 1000M TX GT Wizard 对比 | 已生成隔离 comparison |
| 1000M RX / 全双工一致性 | 未确认；RX line-rate 仍显示 0.5 |
| 1000M TX user clocking example | 已提取，官方 MMCM 参数与 500M 不同 |
| GTX DRP address/bitfield | 未确认；禁止真实写 DRP |
| MMCM 动态重配置 | 仅形成方案，未实现 |
| `rate set 500/1000` | 未实现，仍应保持 unsupported |
| BD/XDC/wrapper/XSA | 未修改 |
| bitstream | 未重新生成 |
| 硬件动态切换 | 未验证 |

## 12. 风险说明

1. Vivado 对 `gt0_val_rx_line_rate` 输出 disabled parameter warning，最终 selected properties 中 RX line-rate 仍为 0.5，因此本阶段不能作为 RX/全双工 1000M 设计依据。
2. 当前候选 DRP 表只有 generated HDL parameter delta，没有可直接写入的 DRP address/bitfield。
3. 500M 与 1000M 官方 example design MMCM 参数不同，动态速率必须处理 MMCM 重配置或安全 clock mux。
4. Windows 路径较长，Vivado 输出了 path length warning；如后续 IP 操作异常，可考虑缩短 comparison 目录。
5. `git` 当前不在 PowerShell PATH 中，未能执行 `git status --short`；本报告按显式修改文件列表记录。

## 13. 下一步建议

1. 先确认 GTXE2_CHANNEL 中 TXOUT_DIV/RXOUT_DIV 的 DRP address 与 bitfield，不要直接套其他工程；
2. 生成 TX/RX 参数一致的最终 1000M profile，或者明确本工程只做 TX 动态；
3. 做 1000M 单速率 bitstream 验证，确认 TXUSRCLK=31.25 MHz、TXUSRCLK2=15.625 MHz；
4. 再设计 `laser_gt_rate_ctrl` RTL，并让 `rate set` 从 unsupported 进入受控状态机；
5. 任何真实实现前都要保留 Profile 0 回滚路径，确认 `TXOUT_DIV=8` 和 500M ILA 验证不被破坏。


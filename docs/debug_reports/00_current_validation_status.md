# laser_tx 当前验证状态总览

本文是当前 `laser_tx` 项目的最短阅读入口，用于快速判断哪些链路已经有证据、哪些仍未实现或未验证。

本报告仅整理既有文档和证据，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX。

## 当前可烧写产物入口（2026-07-13）

已建立两套带 manifest、SHA-256、配套报告和烧写说明的本地产物包：

| Bundle | 用途 | 验证边界 |
| --- | --- | --- |
| `artifacts/builds/current_ad9528_measurement/` | AD9528 OUT0 Bank110 FPGA 频率测量及 PS/UDP 回读 | 内部计数/UDP 已上板；外部仪器未验证 |
| `artifacts/builds/rollback_fixed_refclk_baseline/` | measurement 接入前的固定参考时钟回退 | rebuild/timing/DRC 通过；本次重建包未重新上板 |

完整溯源、哈希、回退顺序和边界见 `44_build_artifact_packaging_and_provenance_report.md`。两套 bit/LTX/ELF 不得交叉混用。

本文后部保留了早期阶段描述用于历史追溯；涉及当前动态 profile、AD9528 和构建产物时，应以最新编号报告为准。

## AD9528 PLL2 fine-step TEST0 规划状态

- 已完成实现路径感知的只读枚举模型和 host tests；
- `VCXO_122P88` 明确标记为 `VCXO_DIRECT/board_measured=1/pll2_fine_step_candidate=0`；
- ADI calibration divider 合法性已纳入枚举，all candidates=274（含 VCXO direct 基线），低风险 shortlist=20，精确 3000M experimental shortlist=0；
- 固定 `3000M/FIXED_125M_CPLL` 继续为 `BLOCKED/NO_LEGAL_VERIFIED_125M_CPLL_PROFILE`；
- 原 124.8 MHz 数学候选因 `M1×N2=260` 超过 ADI 0x0201 feedback calibration divider 上限 255，已从候选中排除；
- 寄存器审计 gate 为 `NO_PROVEN_PLL2_REGISTER_IMAGE`，且共享输出影响仍未确认；
- 新增只读 `ad9528 dump full`，未新增任何 PLL2 写操作，未修改 RTL、BD/XDC 或 supported rates。
- 已解析 97 字节 application-initialized full dump，并完成 125.44 MHz / 124.416 MHz 两套完整寄存器计划对比；
- 两候选 calibration divider 均可编码，但 charge-pump、loop-filter、共享 PLL2 输出及 global SYNC 许可未闭环，最终 gate 仍为 `NO_SAFE_PLL2_TEST0_CANDIDATE`；
- 124.416 MHz 候选只作为下一轮参数闭环优先对象，尚未生成执行入口、未写 AD9528、未上板。
- 已新增显式 `ad9528 candidate set pll2_test0` measurement-only executor 并通过 Vitis clean build；它只在 ADRV9009/JESD 停止、共享 PLL2 输出影响实验室临时接受的条件下使用；
- executor 使用完整 ADI reference configuration、禁止 CHANNEL_SYNC、要求 calibration/PLL2 lock/连续3个测量窗口并自动 rollback；尚未上板，`pll2_functionally_measured=0`、`board_verified=0`。

## 1. 当前分层状态表

| 层级 / 功能 | 当前状态 | 证据入口 | 备注 |
| --- | --- | --- | --- |
| Profile0 500M 有效发送 case | 已完成 ILA 阶段性验证 | `01_profile0_500m_ila_validation_summary.md` | Direct63 / Direct127 / PRBS6 / PRBS7 有效发送 case 通过 |
| Profile0 非法配置保护 | 部分通过，边界项待需求确认 | `01_profile0_500m_ila_validation_summary.md` | seed=0 fallback、PRBS/direct_len mismatch 属于需求边界 |
| Profile1 1000M static build | bit/LTX/timing 已通过 | `02_profile1_1000m_static_build_and_debug_fix.md` | 这是静态 bitstream，不是动态 rate set |
| Profile1 1000M debug hub 修复 | 已完成 | `02_profile1_1000m_static_build_and_debug_fix.md` | `dbg_hub/clk` 和 AXI bring-up ILA 使用 `gt_ctrl_clk / clk_fpga_0` |
| Profile1 1000M AXI/FCLK ILA | 已完成阶段性上板观察 | `03_profile1_1000m_static_ila_validation_summary.md` | GT/MMCM/txusrclk2 alive、APPLY、ENABLE 已有真实 GUI 截图 |
| Profile1 1000M txusrclk2 数据路径 | 已有部分既有截图/报告支撑，仍建议继续补强 | `03_profile1_1000m_static_ila_validation_summary.md` | AXI/FCLK ILA 不替代 txdata/valid_mask 深入观察 |
| Phase A dry-run rate controller | 已完成 RTL/Vitis 实现与 app build，未上板验证 | `05_phaseA_dryrun_rate_controller_report.md` | `rate set` 仅 dry-run，不改变真实速率 |
| 动态 `rate set` | 真实切换未实现 | 本状态表 | 不支持 500M/1000M 运行时真实切换 |
| GTX DRP | 未实现 | 本状态表 | 未写 GTX DRP |
| MMCM DRP | 未实现 | 本状态表 | 未写 MMCM DRP |
| 外部光口闭环 | 未验证 | 本状态表 | 不得写成已通过 |

## 2. 当前可以引用的结论

可以引用：

```text
Profile0 500M 有效发送 case 已完成上板 ILA 阶段性验证；
Profile0 Direct63 / Direct127 / PRBS6 / PRBS7 有效发送 case 通过；
Profile0 repeat_cycles=0、insert_after>repeat_cycles、非法 prbs_order 已被拒绝；
Profile1 1000M static bit/LTX/timing 已生成并通过实现检查；
Profile1 1000M static 的 debug hub 已改为稳定 AXI/FCLK 域；
Profile1 1000M static 的 AXI/FCLK bring-up ILA 已观察到 GT/MMCM ready、txusrclk2 alive、APPLY 和 ENABLE 控制事件；
Profile1 1000M static 下 cfg_valid=1、cfg_error=0、engine_start_seen=1 已有 GUI 截图证据。
Phase A dry-run rate controller 已完成 RTL/Vitis 实现和 bringup app build；rate set 500/1000 仅 dry-run，真实速率不变。
```

## 3. 当前不能引用或必须降级的结论

不能写成：

```text
1000M 动态调速已经完成；
真实 rate set 500/1000 已经实现；
GTX DRP 已经完成；
MMCM DRP 已经完成；
1000M static build 通过等价于上板闭环通过；
AXI/FCLK ILA 状态验证等价于外部光口闭环通过；
CSV 重绘 PNG 是主要报告证据；
Profile0 的结论可以直接搬到 Profile1。
```

## 4. 证据优先级

后续正式报告采用以下证据优先级：

```text
1. 真实 Vivado Hardware Manager / ILA GUI 截图；
2. Vivado 原始 log / timing report / implemented debug check report；
3. 原始 ILA CSV；
4. 辅助脚本统计；
5. CSV 重绘 PNG：已废弃，不再作为正式主证据。
```

## 5. 当前主报告入口

推荐只读以下主报告：

```text
README_validation_report_reading_order.md
00_current_validation_status.md
01_profile0_500m_ila_validation_summary.md
02_profile1_1000m_static_build_and_debug_fix.md
03_profile1_1000m_static_ila_validation_summary.md
```

如需追溯中间失败过程，再查看：

```text
docs/debug_reports/archive/
```


## 6. AD9528 OUT0 测量链路补充状态

| 层级 / 功能 | 当前状态 | 证据入口 | 备注 |
| --- | --- | --- | --- |
| AD9528 OUT0 ILA 频率测量 | 已有上板稳态证据 | `ad9528_out0_frequency_measurement_report.md` | ODIV2 count=61437，对应 OUT0 约122.874MHz；非示波器证据 |
| AD9528 OUT0 PS/UDP 回读 | 软件/硬件接口已实现，build与新接口上板状态见41号报告 | `41_ad9528_out0_software_measurement_readback_report.md` | 专用只读 AXI GPIO；不接Bank111，不改变GT profile |

本补充状态优先于本文前部早期 Phase A 描述；历史段落保留用于追溯，当前动态 rate/profile 结论应以最新编号报告和实际 `rate list/status` 为准。

# laser_tx 当前验证状态总览

本文是当前 `laser_tx` 项目的最短阅读入口，用于快速判断哪些链路已经有证据、哪些仍未实现或未验证。

本报告仅整理既有文档和证据，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX。

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


# Profile0 500M ILA 验证摘要报告

本文是 Profile0 固定 500M 阶段的正式摘要入口。它合并早期 Profile0 上板 ILA 验证结论，但不把 Profile0 结论直接搬到 Profile1。

本报告仅整理既有文档和证据，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX。

## 1. 来源报告与证据

主要来源：

```text
reports/board_validation/profile0_final/laser_tx_profile0_effective_tx_ila_closure_report.md
reports/board_validation/profile0_final/profile0_cases_ila_validation_report.md
reports/board_validation/profile0_final/vivado_ila_trigger_settings.md
reports/board_validation/profile0_final/direct63/profile0_direct63_ila_validation_report.md
docs/debug_reports/archive/profile0_old_reports/20260629_ila_txusrclk2_probe_update.md
```

原始证据保留在：

```text
reports/board_validation/profile0_final/
```

真实 Vivado GUI 截图保留在：

```text
docs/images/phase1_static_ila/500m_profile0/ila_apply_config_update.png
docs/images/phase1_static_ila/500m_profile0/ila_apply_with_txdata_validmask.png
docs/images/phase1_static_ila/500m_profile0/ila_enable_engine_start.png
docs/images/phase1_static_ila/500m_profile0/ila_enable_txdata_validmask.png
```

说明：早期 CSV 重绘 PNG 已废弃并归档，不再作为本摘要主证据。

## 2. 有效发送 case 结论

Profile0 500M 阶段已完成以下有效发送 case 的上板 ILA 阶段性验证：

| case | 当前结论 | 说明 |
| --- | --- | --- |
| Direct63 | 通过 | APPLY/ENABLE、TX 状态机、txdata/valid_mask 有预期活动 |
| Direct127 | 通过 | 127bit direct pattern 有效发送 case 通过 |
| PRBS6 | 通过 | PRBS6 有效发送 case 通过 |
| PRBS7 | 通过 | PRBS7 有效发送 case 通过 |

可以保留结论：

```text
Profile0 有效发送 case 已完成上板 ILA 阶段性验证。
```

不应扩大为：

```text
Profile0 所有需求全部通过。
```

## 3. APPLY / ENABLE 链路

既有 GUI 截图显示：

```text
APPLY 后 cfg_update_pulse_tx 出现；
pattern_valid_tx 置 1；
ENABLE 后 engine_start_tx 出现；
busy_tx 短暂拉高；
current_state_tx 出现启动/运行/完成变化；
done_tx 最终置位。
```

该结论说明 Profile0 阶段：

```text
PS/控制软件 -> AXI GPIO -> PL -> txusrclk2 域配置加载与启动事件
```

已获得 ILA 阶段性证据。

## 4. txdata / valid_mask

既有 GUI 截图显示：

```text
ENABLE 后 txdata[63:0] 出现非零数据；
valid_mask[63:0] 出现有效全 1 窗口；
短测试序列结束后 txdata / valid_mask 回到 0。
```

因此可写为：

```text
Profile0 有效发送 case 中，发送数据路径和 valid_mask 输出已经初步跑通。
```

但不应写成：

```text
外部光口链路闭环已验证。
```

## 5. 非法配置保护边界

当前 RTL/验证口径：

| 配置项 | 当前行为 | 结论 |
| --- | --- | --- |
| `repeat_cycles=0` | 报错 | 保护有效 |
| 非法 `prbs_order` | 报错 | 保护有效 |
| `insert_after > repeat_cycles` | 报错 | 保护有效 |
| `seed=0` | fallback 到默认非零 seed，不报错 | 需求边界未收敛 |
| PRBS mode + direct_len_127 mismatch | PRBS 模式下 direct_len_sel 被忽略 | 需求边界未收敛 |

保留结论：

```text
非法配置保护中 repeat_cycles=0、insert_after>repeat_cycles、非法 prbs_order 已被拒绝；
seed=0 和 PRBS/direct_len mismatch 属于需求边界与当前 RTL 行为不一致，暂列为未收敛项。
```

## 6. CSV 重绘 PNG 处理

早期曾尝试基于 ILA CSV 做辅助可视化。该类 CSV 重绘 PNG 已归档到：

```text
docs/debug_reports/archive/csv_redraw_png_deprecated/
```

当前正式证据优先级为：

```text
真实 Vivado GUI 截图 > 原始 ILA CSV/log > 辅助脚本统计。
```

CSV 重绘 PNG 不再作为主证据。

## 7. 本阶段边界

Profile0 摘要不证明：

```text
Profile1 1000M 通过；
动态 rate set 完成；
GTX DRP/MMCM DRP 完成；
外部光口闭环通过。
```


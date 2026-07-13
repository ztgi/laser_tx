# laser_tx 上板验证与 ILA 调试报告阅读顺序说明

本文是 `laser_tx` 验证报告体系的总入口。它说明当前应该先读哪些主报告、旧报告如何归档、哪些结论可以引用、哪些结论必须降级。

本轮仅做文档整理，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX。

## 1. 推荐阅读顺序

1. 先读：

   ```text
   00_current_validation_status.md
   ```

   用于快速了解当前项目验证状态。

2. 如果要烧写当前 AD9528 measurement 版本或回退 fixed-refclk baseline，紧接着阅读：

   ```text
   44_build_artifact_packaging_and_provenance_report.md
   ```

   该报告给出两套 bundle 的来源、SHA-256、bit/LTX/XSA/ELF 对应关系、timing/DRC 和回退烧写顺序。禁止跨 bundle 混用产物。

3. 如果关心 Profile0 500M：

   ```text
   01_profile0_500m_ila_validation_summary.md
   ```

4. 如果关心 1000M static 是怎么 build 和修 debug 的：

   ```text
   02_profile1_1000m_static_build_and_debug_fix.md
   ```

5. 如果关心 1000M static 上板 ILA 结果：

   ```text
   03_profile1_1000m_static_ila_validation_summary.md
   ```

6. 如果追溯 500M <-> 1000M 动态速率切换的早期设计：

   ```text
   04_dynamic_rate_switch_design_plan.md
   ```

7. 如果需要追溯中间失败过程、历史 debug 过程或旧报告：

   ```text
   docs/debug_reports/archive/
   reports/board_validation/profile0_final/
   reports/gt_profile1_1000m_static/
   ```

## 2. 当前正式主报告

| 主报告 | 作用 | 当前有效性 |
| --- | --- | --- |
| `00_current_validation_status.md` | 当前分层状态总览 | 当前推荐最短入口 |
| `01_profile0_500m_ila_validation_summary.md` | Profile0 500M 有效发送与非法配置边界摘要 | Profile0 阶段性结论有效 |
| `02_profile1_1000m_static_build_and_debug_fix.md` | 1000M static build、旧 debug 问题、AXI/FCLK ILA 修复摘要 | 1000M static build/debug 主入口 |
| `03_profile1_1000m_static_ila_validation_summary.md` | 1000M AXI/FCLK ILA 上板截图证据摘要 | 1000M static ILA 阶段性主入口 |
| `04_dynamic_rate_switch_design_plan.md` | 500M <-> 1000M 动态速率切换设计评审与实施计划 | 仅为计划，不代表 DRP/rate set 已实现 |
| `05_phaseA_dryrun_rate_controller_report.md` | Phase A dry-run rate controller 实现报告 | 已实现 dry-run 控制面；不代表真实动态切换 |
| `44_build_artifact_packaging_and_provenance_report.md` | Current measurement 与 rollback fixed-refclk 构建产物溯源 | 当前烧写/回退产物主入口 |

## 3. 旧报告到新主报告的映射

| 旧报告 / 证据 | 当前处理 | 合并到 |
| --- | --- | --- |
| `reports/board_validation/profile0_final/laser_tx_profile0_effective_tx_ila_closure_report.md` | 保留原路径，作为 Profile0 原始主依据 | `01_profile0_500m_ila_validation_summary.md` |
| `reports/board_validation/profile0_final/profile0_cases_ila_validation_report.md` | 保留原路径，作为 Profile0 case 原始依据 | `01_profile0_500m_ila_validation_summary.md` |
| `reports/board_validation/profile0_final/direct63/profile0_direct63_ila_validation_report.md` | 保留原路径，作为 Direct63 原始依据 | `01_profile0_500m_ila_validation_summary.md` |
| `docs/debug_reports/archive/profile0_old_reports/20260629_ila_txusrclk2_probe_update.md` | 已移动到 archive | `01_profile0_500m_ila_validation_summary.md` |
| `docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_static_build.md` | 已移动到 archive | `02_profile1_1000m_static_build_and_debug_fix.md` |
| `docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_ila_debug_check.md` | 已移动到 archive | `02_profile1_1000m_static_build_and_debug_fix.md` |
| `docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_axi_bringup_ila_fix.md` | 已移动到 archive | `02_profile1_1000m_static_build_and_debug_fix.md`、`03_profile1_1000m_static_ila_validation_summary.md` |
| `docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_dynamic_rate_phase1_planner.md` | 已移动到 archive | `02_profile1_1000m_static_build_and_debug_fix.md` |
| `docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_dynamic_rate_phase2_blocker.md` | 已移动到 archive | `02_profile1_1000m_static_build_and_debug_fix.md` |
| `docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_dynamic_rate_phase2_pre_design_package.md` | 已移动到 archive | `02_profile1_1000m_static_build_and_debug_fix.md` |
| `docs/gt_dynamic_rate_phase2_1000m_static_validation.md` | 保留原路径，作为详细历史主报告 | `02_profile1_1000m_static_build_and_debug_fix.md`、`03_profile1_1000m_static_ila_validation_summary.md` |

## 4. 证据优先级说明

后续报告证据优先级统一为：

```text
1. 真实 Vivado Hardware Manager / ILA GUI 截图：最高优先级，用于报告展示；
2. Vivado 原始 log / timing report / implemented debug check report：用于证明 build、clock、debug hub 连接；
3. 原始 ILA CSV：可作为离线统计和复核依据；
4. 辅助脚本统计：只作为补充；
5. CSV 重绘 PNG：仅为早期辅助可视化，已废弃，不再作为主证据，不再纳入正式报告。
```

## 5. CSV 重绘 PNG 废弃归档

早期曾尝试基于 ILA CSV 做辅助可视化，但后续报告不再将 CSV 重绘 PNG 作为主要证据。

已归档位置：

```text
docs/debug_reports/archive/csv_redraw_png_deprecated/
```

该目录中的 PNG 和 `csv_redraw_summary.json` 为早期 CSV 辅助重绘图，已废弃，不作为当前报告主证据。

原始 CSV/log 未删除。真实 Vivado GUI 截图未删除。

## 6. 真实 Vivado GUI 截图保留清单

当前已存在并保留：

```text
docs/images/phase1_static_ila/500m_profile0/ila_apply_config_update.png
docs/images/phase1_static_ila/500m_profile0/ila_apply_with_txdata_validmask.png
docs/images/phase1_static_ila/500m_profile0/ila_enable_engine_start.png
docs/images/phase1_static_ila/500m_profile0/ila_enable_txdata_validmask.png
docs/images/phase1_static_ila/1000m_static/ila_1000m_axi_00_before_apply_gt_ready_idle.png
docs/images/phase1_static_ila/1000m_static/ila_1000m_axi_01_after_apply_cfg_update_seen.png
docs/images/phase1_static_ila/1000m_static/ila_1000m_axi_02_after_enable_engine_start_seen.png
docs/images/phase1_static_ila/1000m_static/udp_1000m_direct127_gap8_repeat4_config.png
```

当前未检测到实际文件，仅作为建议命名或待归档项：

```text
docs/images/phase1_static_ila/500m_profile0/ila_enable_txdata_validmask2.png
```

不得伪造图片，也不得把未存在的文件写成已有截图证据。

## 7. 当前可以引用的结论

可以引用：

```text
Profile0 500M 有效发送 case 已完成上板 ILA 阶段性验证；
Profile0 Direct63 / Direct127 / PRBS6 / PRBS7 有效发送 case 通过；
Profile0 repeat_cycles=0、insert_after>repeat_cycles、非法 prbs_order 已被拒绝；
seed=0 和 PRBS/direct_len mismatch 属于需求边界未收敛项；
1000M Profile1 static bit/LTX/timing 已生成并通过实现检查；
1000M Profile1 static 的 debug hub 已改为稳定 AXI/FCLK 域；
1000M Profile1 static 下 AXI/FCLK ILA 已观察到 GT/MMCM ready、txusrclk2 alive、APPLY、cfg_valid=1、cfg_error=0、ENABLE、engine_start_seen=1。
```

## 8. 当前必须降级或禁止引用的旧结论

不得引用或必须降级：

```text
CSV 重绘 PNG 作为主证据；
由于无法 GUI 截图所以用 CSV 生成图替代 GUI 截图；
figures/ 下 CSV 重绘图作为正式证据；
Profile0 结论直接搬到 Profile1；
1000M static build 通过等于上板闭环通过；
1000M static 已实现动态 rate set；
GTX DRP/MMCM DRP 已完成；
AXI/FCLK ILA 状态验证等于外部光口链路闭环通过。
```

## 9. 当前未验证 / 未实现项

必须继续明确：

```text
动态 rate set：未实现；
GTX DRP：未实现；
MMCM DRP：未实现；
外部光口闭环：未验证；
1000M static 下外部同步/光口实际输出：仍需进一步上板或示波器/接收链路验证。
```

## 10. AD9528 OUT0 测量报告入口

如果关心 AD9528 OUT0 的 FPGA ILA 频率证据和 PS/UDP 软件回读，按以下顺序阅读：

```text
ad9528_out0_frequency_measurement_report.md
41_ad9528_out0_software_measurement_readback_report.md
```

如果关心下一步 PLL2 fine-step TEST0 的候选选择、3000M 实现路径状态和安全停止点，阅读：

```text
../design_notes/ad9528_fine_step_test0_candidate_selection.md
43_ad9528_pll2_test0_register_image_audit.md
45_ad9528_pll2_test0_dual_candidate_register_plan.md
```

其中 43 号报告记录旧 124.8 MHz 候选因 calibration divider=260 被否决；45 号报告使用完整运行镜像比较新的 125.44/124.416 MHz 候选，并给出当前 `NO_SAFE_PLL2_TEST0_CANDIDATE` gate。后者不代表 PLL2 candidate 已实现或上板。

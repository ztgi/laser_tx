# Profile1 1000M static build 与 debug 结构修复摘要

本文是 1000M Profile1 static build、旧 ILA/debug 自检、AXI/FCLK bring-up ILA 修复的正式摘要入口。

本报告仅整理既有文档和证据，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX。

## 1. 合并来源

已合并的旧中间报告：

```text
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_static_build.md
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_ila_debug_check.md
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_axi_bringup_ila_fix.md
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_dynamic_rate_phase1_planner.md
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_dynamic_rate_phase2_blocker.md
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_dynamic_rate_phase2_pre_design_package.md
```

相关主报告仍可追溯：

```text
docs/gt_dynamic_rate_phase2_1000m_static_validation.md
```

## 2. 为什么先做 1000M static

阶段二前置设计已经确认：

```text
500M -> 1000M 不只是 GTX TXOUT_DIV=8 -> 4；
还必须同步处理 TX user clock MMCM；
TXUSRCLK/TXUSRCLK2 需要从 15.625/7.8125 MHz 切换到 31.25/15.625 MHz。
```

因此当前先做独立 1000M static bitstream，用于验证：

```text
GT Wizard 1000M 静态配置；
1000M user clocking；
timing；
ILA/debug 结构；
现有 PS/UDP/APPLY/ENABLE 控制流程在 1000M static 下是否可继续使用。
```

这不是动态 rate set。

## 3. 1000M static build 结果

当前 1000M Profile1 static 目标：

| 项目 | 目标 / 结果 |
| --- | --- |
| Line rate | 1.000 Gb/s |
| TXDATA width | 64 bit |
| Encoding | None |
| TX internal datawidth | 32 |
| TXOUT_DIV | 4 |
| TXUSRCLK | 31.25 MHz |
| TXUSRCLK2 | 15.625 MHz |
| TXUSRCLK:TXUSRCLK2 | 2:1 |

已生成的 1000M static bit/LTX：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

Timing 结果：

```text
Setup WNS = 7.029 ns
Setup TNS = 0.000 ns
Timing constraints met
```

## 4. Profile0 回退保护

Profile0 500M 未被覆盖：

```text
Profile0 TXOUT_DIV = 8；
Profile0 500M XCI 未被 1000M XCI 覆盖；
Profile0 500M bit/LTX 未作为本阶段输出覆盖；
Profile0 已验证路径仍可回退。
```

## 5. 旧 debug 结构问题

旧 1000M ILA/debug 自检阶段发现：

```text
dbg_hub/clk = gt_txusrclk2；
txusrclk2 依赖 GT TXOUTCLK 和 TX MMCM lock；
hw_ila_3 trigger_now 后 waveform upload corrupted；
问题更可能来自 debug hub / ILA clock 依赖不稳定 txusrclk2；
不能直接判定为 UDP/APPLY 逻辑失败。
```

结论：

```text
txusrclk2 域 ILA 可作为二级观察；
但不适合作为 1000M bring-up 的首要 debug 入口。
```

## 6. AXI/FCLK bring-up ILA 修复

修复后结构：

```text
dbg_hub/clk = gt_ctrl_clk / clk_fpga_0；
新增 ila_1000m_bringup_axi；
ila_1000m_bringup_axi/clk = gt_ctrl_clk / clk_fpga_0；
GT/MMCM/txusrclk2 状态通过 CDC 或稳定寄存同步到 AXI/FCLK 域；
新增 txusrclk2_alive_axi；
新增 txusrclk2_freq_counter_axi。
```

AXI/FCLK bring-up ILA 用于首要观察：

```text
cplllock_sync
txresetdone_sync
tx_mmcm_locked_sync
gt_ready_ctrl
txusrclk2_alive_axi
txusrclk2_freq_counter_axi
gpio/apply/enable
cfg_valid/cfg_error
cfg_update_seen
engine_start_seen
```

## 7. 当前未实现内容

本阶段仍未实现：

```text
rate set 500/1000；
GTX DRP；
MMCM DRP；
laser_gt_rate_ctrl 动态切换；
运行时 GT reset/relock 状态机；
外部光口闭环验证。
```

因此不能写成：

```text
1000M 动态调速完成。
```


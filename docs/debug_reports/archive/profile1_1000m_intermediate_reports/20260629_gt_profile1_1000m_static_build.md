# 1000M Profile1 静态分支构建调试报告

## 1. 本轮问题现象

阶段二前置设计包确认 500M 到 1000M 需要同时改变 GTX `TXOUT_DIV` 和 TX user clocking。本轮目标是建立独立 1000M 静态工程路径，先完成构建、timing、bit/LTX 生成，不直接实现运行时动态 `rate set 500/1000`。

## 2. 当前已通过的层级

```text
1000M 隔离 GT Wizard XCI：已生成
1000M TXOUT_DIV=4：已确认
1000M user clocking：已实现
TXUSRCLK=31.25 MHz：已由 report_clocks 确认
TXUSRCLK2=15.625 MHz：已由 report_clocks 确认
synthesis：已完成
implementation：已完成
timing：已通过
bitstream：已生成
ltx：已生成
Profile0 TXOUT_DIV=8 回退保护：已确认
```

## 3. 当前未通过的层级

```text
1000M 静态 bitstream 上板下载：未执行
READ_GT_STATUS 上板读回：未执行
APPLY / ENABLE 上板 ILA 验证：未执行
txusrclk2_divided_debug 示波器或 ILA 实测：未执行
动态 rate set：未实现，且本阶段禁止实现
```

## 4. 根因假设

动态 500M/1000M 切换的风险点不只在 GTX `TXOUT_DIV`。1000M 需要 `TXUSRCLK/TXUSRCLK2` 从 15.625/7.8125 MHz 切到 31.25/15.625 MHz，如果未先验证 1000M 静态分支，后续动态切换时无法区分问题来自 GT 参数、MMCM 参数、reset sequence、ILA 时钟还是上层 `laser_tx_core`。

## 5. 本轮修改内容

| 文件 | 修改内容 | 目的 |
| --- | --- | --- |
| `laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile1_1000m.v` | 新增 1000M 专用 MMCM user clocking | 从 31.25 MHz TXOUTCLK 生成 31.25 MHz TXUSRCLK 与 15.625 MHz TXUSRCLK2 |
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile1_1000m.v` | 新增 1000M GT TX wrapper | 接入 1000M user clocking、状态同步、TXUSRCLK2 debug 分频和 GT ILA |
| `rtl/laser_tx_board_top_profile1_1000m.v` | 新增 1000M 静态 top | 保持同一 PS/BD 控制链路，替换为 1000M GT wrapper |
| `constraints/laser_tx_gt_profile1_1000m.xdc` | 新增 1000M 静态 XDC | 约束同一 GTX 引脚与 125 MHz refclk，并记录 1000M clock 目标 |
| `scripts/gt_profile1_1000m_impl_pre.tcl` | 新增 implementation pre-hook | 在实现前校验 TXOUTCLK/TXUSRCLK/TXUSRCLK2 周期是否符合 1000M |
| `scripts/build_gt_profile1_1000m_static.tcl` | 新增/修正隔离构建脚本 | 复制工程、替换本地 1000M XCI、重生 IP output products、运行 synth/impl/bitgen |
| `scripts/create_gtwizard_1000m_compare.tcl` | 扩展 GT Wizard 1000M 对比生成 | 生成隔离 1000M XCI 与 selected properties 报告 |
| `docs/gt_dynamic_rate_phase2_1000m_static_validation.md` | 新增阶段报告 | 固化 1000M 静态验证分支设计和构建结果 |
| `docs/debug_reports/20260629_gt_profile1_1000m_static_build.md` | 新增本调试报告 | 记录本轮构建问题、修复和结论 |

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| 1000M 静态 top | 无 | `laser_tx_board_top_profile1_1000m` | 可独立构建 1000M bitstream |
| GT profile | 仅 500M Profile0 | 隔离工程内 1000M Profile1 | 不覆盖 500M |
| `TXOUT_DIV` | 500M 为 8 | 1000M 为 4 | line rate 到 1.0G |
| `TXUSRCLK` | 15.625 MHz | 31.25 MHz | 满足 1000M 内部 32-bit 语义 |
| `TXUSRCLK2` | 7.8125 MHz | 15.625 MHz | `laser_tx_core` 1000M 静态节拍 |
| 动态 DRP | 无 | 仍无 | 未实现动态速率切换 |
| Vitis 协议 | 已有 UDP/命令 | 未修改 | 同一 PS 控制流程继续使用 |
| XSA | 现有 500M/主工程 XSA | 未导出 1000M XSA | BD/地址未变，暂不需要 |
| 上板验证 | 500M 已收口 | 1000M 未上板 | 不能声明 1000M 硬件通过 |

## 7. 为什么这样修改

1. 使用隔离工程而不是覆盖主工程 XCI，是为了保护已上板验证的 500M Profile 0。
2. 新增 `laser_gt_usrclk_profile1_1000m.v`，是为了避免误复用 500M MMCM 参数。
3. 在 implementation pre-hook 中检查 clock period，是为了在实现阶段直接阻断错误 clocking，例如误把 1000M TXUSRCLK2 仍接成 7.8125 MHz。
4. 新增 `txusrclk2_divided_debug`，是为了上板时能用 ILA/示波器间接确认 TXUSRCLK2 是否为 15.625 MHz。
5. 保持 Vitis 命令协议不变，是因为本阶段只验证 1000M 静态 bitstream，不改变 PS 控制语义。

## 8. 硬件接口一致性说明

```text
未修改 laser_tx_core 功能逻辑
未修改主工程 500M Profile0 GT XCI
未修改主工程 BD
未修改主工程 HDL wrapper
未修改主工程 XSA
未修改 GPIO / BRAM / GT status 地址
未修改 Vitis UDP 协议
未做 GTX DRP
未做 MMCM DRP
未接入 laser_gt_rate_ctrl
未实现运行时动态改速率
```

1000M 静态 top 使用同一套板级端口：

```text
DDR / FIXED_IO
gt_refclk125_p/n
gtx_txp_out / gtx_txn_out
eom_out / soa_gate_out / acq_trig_out / acq_gate_out
```

未新增、删除或重命名外部端口。

## 9. 构建验证记录

执行命令：

```powershell
& 'D:\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'D:\FPGA_Learn\laser_tx\scripts\build_gt_profile1_1000m_static.tcl'
```

构建过程中曾遇到并修复：

| 问题 | 原因 | 修复 |
| --- | --- | --- |
| Tcl regex 报错 | Tcl 不支持脚本中原写法的 `[\s\S]` 转义 | 改为明确检查关键字段 |
| impl pre-hook 检出 TXOUTCLK 仍为 64 ns | 隔离工程仍引用 Profile0 XCI/output products | 在复制工程中覆盖本地 XCI |
| 生成文件仍保持 Profile0 | 旧 IP output products 未清理 | 删除隔离工程 gen 内 GT IP 输出并 `reset_target all` / `generate_target all` |

最终构建证据：

```text
reports/gt_profile1_1000m_static/vivado_project/laser_tx_profile1_1000m.runs/impl_1/runme.log:
INFO: [Vivado 12-1842] Bitgen Completed Successfully.
write_bitstream completed successfully
```

Clock 证据：

```text
reports/gt_profile1_1000m_static/reports/clocks.rpt:
TXOUTCLK          period = 32.000 ns
clkout1_txusrclk  period = 32.000 ns
clkout0_txusrclk2 period = 64.000 ns
```

Timing 证据：

```text
reports/gt_profile1_1000m_static/reports/timing_summary.rpt:
WNS = 7.029 ns
TNS = 0.000 ns
All user specified timing constraints are met.
```

生成文件：

```text
reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

## 10. 上板验证记录

Hardware test was not run。

当前不能声明：

```text
1000M 静态 Profile1 上板通过
1000M GT ready 上板通过
1000M APPLY / ENABLE 上板通过
1000M txdata / valid_mask 上板通过
动态速率切换已实现
```

## 11. 当前分层结论

| 层级 | 结论 |
| --- | --- |
| 500M Profile0 回退保护 | 通过，主工程仍为 `TXOUT_DIV=8` |
| 1000M GT output products | 通过，隔离工程生成 `TXOUT_DIV=4` |
| 1000M user clocking | 通过，报告确认 31.25/15.625 MHz |
| Synthesis | 通过 |
| Implementation | 通过 |
| Timing | 通过 |
| Bit/LTX | 通过 |
| XSA | 未导出，因 BD/地址/Vitis 控制链路未改变 |
| 上板验证 | 未执行 |
| 动态 rate set | 未实现 |

## 12. 风险说明

1. 1000M selected properties 报告中 `gt0_val_rx_line_rate` 读回仍为 `0.5`，虽然生成后的 `RXOUT_DIV=4`。本阶段只声明 TX 静态路径，不声明 RX 或全双工 1000M。
2. 1000M `laser_tx_core` 在 15.625 MHz TXUSRCLK2 下的实际板上行为尚未验证。
3. 新增 ILA 会增加 debug 资源和部分 routing 负载，当前 timing 已通过，但上板时仍需使用同一次 bit/LTX。
4. 1000M 静态验证通过前，不应推进动态 DRP/MMCM 重配置。

## 13. 下一步建议

1. 使用以下 bit/LTX 上板：

   ```text
   D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
   D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
   ```

2. 先读 `READ_GT_STATUS`，确认 `cplllock=1`、`txresetdone=1`、`gt_ready=1`、`tx_mmcm_locked=1`。
3. 用 ILA 抓 `cfg_update_pulse_tx`、`engine_start_tx`、`busy_tx`、`done_tx`、`txdata[63:0]`、`valid_mask[63:0]`。
4. 用新增 `txusrclk2_divided_debug` 证明 1000M 静态下 TXUSRCLK2 为 15.625 MHz。
5. 1000M 静态上板验证通过后，再进入 GTX DRP address/bitfield 和 MMCM DRP 参数确认；若失败，先定位静态 1000M，不进入动态切换。

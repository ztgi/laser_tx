# 修复 dbg_hub 时钟并补充动态 rate ILA probe 报告

## 1. 本轮目标

本轮只做 debug 结构修复：

```text
1. 将 dbg_hub/clk 从 gt_txusrclk2 改为稳定的 gt_ctrl_clk / clk_fpga_0；
2. 保持 ila_laser_axi_cfg/clk = gt_ctrl_clk；
3. 保持 ila_laser_tx/clk = txusrclk2；
4. 在 AXI/FCLK 域 ILA 中加入动态 rate switch probe；
5. 保留原有 AXI/FCLK ILA probe；
6. 保留原有 txusrclk2 ILA probe。
```

本轮未修改：

```text
rate controller 功能
GTX/MMCM DRP 状态机
支持速率集合
AD9528
Vitis 协议
AXI 地址
XSA / platform / BSP
```

## 2. 修改前问题

上一轮 `impl_1` 的 ILA probe 清单确认：

```text
dbg_hub
ila_laser_axi_cfg
ila_laser_tx
```

基础 ILA 没有丢，但存在两个 debug 结构问题：

```text
1. dbg_hub/clk = gt_txusrclk2；
2. 动态 rate controller 关键信号没有进入 AXI/FCLK ILA。
```

其中 `dbg_hub/clk = gt_txusrclk2` 会导致 Hardware Manager bring-up 依赖 GT TX user clock。如果 GT/MMCM/TXUSRCLK2 在上板早期不稳定，Vivado 可能报：

```text
The debug hub core was not detected.
Reading intermittently wrong data from core.
```

## 3. 修改后结构

### 3.1 debug hub clock

修改前：

```text
dbg_hub/clk = gt_txusrclk2
C_CLK_INPUT_FREQ_HZ = 300000000
```

修改后：

```text
dbg_hub/clk = gt_ctrl_clk
C_CLK_INPUT_FREQ_HZ = 50000000
```

实现方式：

```text
在 impl_1 opt_design pre hook 中，link_design 后显式执行：
disconnect_debug_port dbg_hub/clk
connect_debug_port dbg_hub/clk gt_ctrl_clk
set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
```

实现日志证据：

```text
INFO: dbg_hub/clk forced to AXI/FCLK net: gt_ctrl_clk
```

`report_debug_core` 结果：

```text
Debug Core "dbg_hub"
C_CLK_INPUT_FREQ_HZ = 50000000
clk Net Name = gt_ctrl_clk
```

### 3.2 AXI/FCLK ILA

`ila_laser_axi_cfg` 保持：

```text
clk = gt_ctrl_clk
```

原有 probe0-probe5 保留：

```text
probe0  axi_gpio_0_gpio_io_o[31:0]
probe1  laser_tx_core_0_gpio_status[31:0]
probe2  laser_tx_core_0_dbg_bram_en
probe3  laser_tx_core_0_dbg_bram_addr[31:0]
probe4  laser_tx_core_0_dbg_bram_dout[31:0]
probe5  laser_tx_core_0_dbg_bram_rst
```

新增 probe6-probe23：

| probe | 信号 | 位宽 | 时钟域 | 用途 |
|---:|---|---:|---|---|
| probe6 | `dbg_rate_state[7:0]` | 8 | AXI/FCLK | 动态 rate switch 状态 |
| probe7 | `dbg_target_rate_mbps[15:0]` | 16 | AXI/FCLK | 目标速率 |
| probe8 | `dbg_current_rate_mbps[15:0]` | 16 | AXI/FCLK | 当前速率 |
| probe9 | `dbg_rate_error` | 1 | AXI/FCLK | rate switch 错误标志 |
| probe10 | `dbg_rate_error_code[7:0]` | 8 | AXI/FCLK | rate switch 错误码 |
| probe11 | `dbg_gt_drp_write_attempted` | 1 | AXI/FCLK | GTX DRP 写尝试标志 |
| probe12 | `dbg_mmcm_drp_write_attempted` | 1 | AXI/FCLK | MMCM DRP 写尝试标志 |
| probe13 | `dbg_gt_drp_busy` | 1 | AXI/FCLK | GTX DRP busy |
| probe14 | `dbg_gt_drp_done` | 1 | AXI/FCLK | GTX DRP done |
| probe15 | `dbg_gt_drp_error` | 1 | AXI/FCLK | GTX DRP error |
| probe16 | `dbg_mmcm_drp_busy` | 1 | AXI/FCLK | MMCM DRP busy |
| probe17 | `dbg_mmcm_drp_done` | 1 | AXI/FCLK | MMCM DRP done |
| probe18 | `dbg_mmcm_drp_error` | 1 | AXI/FCLK | MMCM DRP error |
| probe19 | `dbg_txusrclk2_alive_axi` | 1 | AXI/FCLK | TXUSRCLK2 alive 同步状态 |
| probe20 | `dbg_txusrclk2_freq_counter_axi[31:0]` | 32 | AXI/FCLK | TXUSRCLK2 频率/活动计数 |
| probe21 | `dbg_tx_quiesce_req` | 1 | AXI/FCLK | 切换前 TX quiesce 请求 |
| probe22 | `dbg_tx_idle_seen` | 1 | AXI/FCLK | 已看到 TX idle |
| probe23 | `dbg_apply_enable_blocked` | 1 | AXI/FCLK | rate switch 期间 APPLY/ENABLE 屏蔽状态 |

### 3.3 txusrclk2 ILA

`ila_laser_tx` 保持：

```text
clk = txusrclk2
```

保留 probe：

```text
txdata[63:0]
valid_mask[63:0]
eom_out
soa_gate_out
acq_trig_out
acq_gate_out
busy_tx
done_tx
phase_active_tx
phase_start_pulse_tx
phase_offset_tx[7:0]
current_state_tx[7:0]
cfg_update_pulse_tx
pattern_valid_tx
engine_start_tx
```

## 4. 修改文件列表

| 文件 | 修改内容 |
|---|---|
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 新增 debug-only 输出端口，将已有 AXI/FCLK 域 rate switch 状态信号导出给 BD ILA；不修改状态机或 DRP 逻辑。 |
| `rtl/laser_tx_board_top.v` | 新增内部 debug-only wires，并把 `laser_gt_tx_profile0` 的 rate debug 输出接入 `system_wrapper`。未新增板级外部引脚。 |
| `laser_tx.srcs/sources_1/bd/system/system.bd` | 扩展 `ila_laser_axi_cfg` 到 24 个 probe，新增 AXI/FCLK rate debug 输入端口并连接 probe6-probe23。 |
| `laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v` | 重新生成并同步 wrapper，使新增 BD debug 输入端口进入工程 compile order。 |
| `laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v` | Vivado `make_wrapper -force` 生成结果。 |
| `laser_tx.gen/sources_1/bd/system/synth/system.v` | BD output products 重新生成。 |
| `laser_tx.gen/sources_1/bd/system/sim/system.v` | BD output products 重新生成。 |
| `scripts/fix_dbg_hub_and_add_rate_ila_probes.tcl` | 新增 BD 修改脚本。 |
| `scripts/rebuild_after_debug_ila_fix.tcl` | 新增完整 synth/impl/bit/LTX 构建脚本。 |
| `scripts/gt_profile0_impl_pre.tcl` | 在 impl pre hook 中强制 `dbg_hub/clk` 连接 `gt_ctrl_clk`，设置 debug hub 频率为 50 MHz。 |
| `scripts/rerun_impl_after_dbg_hub_hook_fix.tcl` | 新增实现重跑与报告/LTX 导出脚本。 |
| `docs/debug_reports/12_fix_dbg_hub_and_add_rate_ila_probes.md` | 新增本报告。 |

## 5. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| `dbg_hub/clk` | `gt_txusrclk2` | `gt_ctrl_clk` | Hardware Manager 不再依赖 GT TX user clock 才能识别 debug hub |
| debug hub 频率参数 | 300 MHz | 50 MHz | 与 `gt_ctrl_clk / clk_fpga_0` 匹配 |
| `ila_laser_axi_cfg/clk` | `gt_ctrl_clk` | `gt_ctrl_clk` | 保持不变 |
| `ila_laser_axi_cfg` probe 数 | 6 | 24 | 新增 rate switch AXI/FCLK probe |
| 原 AXI ILA probe | GPIO/BRAM/status | 保留 | 配置链路观测不丢失 |
| `ila_laser_tx/clk` | `txusrclk2` | `txusrclk2` | 保持不变 |
| TX ILA probe | TX data/status/sync | 保留 | 发送侧观测不丢失 |
| rate controller 功能 | 已有逻辑 | 未修改 | 功能行为不变 |
| GTX/MMCM DRP 逻辑 | 已有逻辑 | 未修改 | DRP 行为不变 |
| Vitis 协议 | 已有协议 | 未修改 | 软件命令不变 |
| AXI 地址 | 已有地址 | 未修改 | 不需要重导 XSA |

## 6. 接口与板级一致性说明

本轮没有新增、删除或重命名板级外部端口。

新增的是 `system_wrapper` 与 BD `system` 的内部 debug-only 输入端口，用于把 `laser_gt_tx_profile0` 中已经存在的 AXI/FCLK 域 rate switch 状态信号送入 ILA。

检查结果：

```text
板级 GTX 引脚未改；
板级同步输出引脚未改；
SPI 引脚未改；
AXI GPIO/BRAM/GT status 地址未改；
Vitis 可见寄存器/命令协议未改；
未重新导出 XSA。
```

## 7. 时钟与复位说明

Clock/reset behavior changed intentionally only for debug hub clock.

具体为：

```text
dbg_hub/clk：gt_txusrclk2 -> gt_ctrl_clk
ila_laser_axi_cfg/clk：保持 gt_ctrl_clk
ila_laser_tx/clk：保持 txusrclk2
```

没有修改：

```text
GT TXUSRCLK/TXUSRCLK2 生成方式；
laser_tx_core txusrclk2 工作域；
AXI/FCLK 频率；
reset polarity；
GT reset sequence；
MMCM reset sequence。
```

## 8. AXI 地址与软件影响

AXI address map unchanged.

本轮未修改：

```text
AXI GPIO base address
BRAM base address
GT status base address
xparameters.h 依赖
Vitis platform/BSP
UDP/UART 命令协议
```

因此不需要重新导出 XSA，也不需要重建 Vitis platform/BSP。

## 9. Validate Design / 生成文件 / 综合实现

执行：

```powershell
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source scripts\fix_dbg_hub_and_add_rate_ila_probes.tcl -notrace"
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source scripts\rebuild_after_debug_ila_fix.tcl -notrace"
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source scripts\rerun_impl_after_dbg_hub_hook_fix.tcl -notrace"
```

结果：

```text
validate_bd_design：通过
synthesis：通过
implementation：通过
bitstream：通过
write_debug_probes：通过
```

第一次完整 build 后发现 `dbg_hub/clk` 仍为 `gt_txusrclk2`，因此追加修复 `scripts/gt_profile0_impl_pre.tcl` 并重跑 implementation。最终 `report_debug_core` 已确认 `dbg_hub/clk = gt_ctrl_clk`。

## 10. QoR / timing / utilization

当前 timing：

| Metric | Result |
|---|---:|
| Setup WNS | 7.029 ns |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| Hold WHS | 0.043 ns |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 |

当前 utilization 摘要：

| Resource | Used | Utilization |
|---|---:|---:|
| Slice LUTs | 20729 | 7.47% |
| Slice Registers | 18922 | 3.41% |
| Block RAM Tile | 44.5 | 5.89% |
| DSPs | 0 | 0.00% |
| BUFGCTRL | 5 | 15.63% |
| MMCME2_ADV | 1 | 12.50% |

Timing result:

```text
All user specified timing constraints are met.
```

## 11. bit / LTX / report 路径

当前 `impl_1` 产物：

```text
Bit:
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit

LTX:
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

dynamic artifacts 同源产物：

```text
Bit:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit

LTX:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

文件记录：

| 文件 | Size | LastWriteTime | SHA256 |
|---|---:|---|---|
| `laser_tx.runs/impl_1/laser_tx_board_top.bit` | 17416462 | 2026-07-01 21:39:13 | `4C3D88CD652266A92F81159147C73A879670CF29AD1681B829119F24B8C2CD75` |
| `laser_tx.runs/impl_1/laser_tx_board_top.ltx` | 107574 | 2026-07-01 21:40:00 | `DE1828534A8D55C69FA32485BA491FBF39B69DAF5D545D56C8F9014B11EBC20A` |
| `reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 17416462 | 2026-07-01 21:39:13 | `4C3D88CD652266A92F81159147C73A879670CF29AD1681B829119F24B8C2CD75` |
| `reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 107574 | 2026-07-01 21:40:00 | `DE1828534A8D55C69FA32485BA491FBF39B69DAF5D545D56C8F9014B11EBC20A` |

辅助报告：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_debug_core.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_timing_summary.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_clocks.rpt
```

## 12. 功能等价性说明

Expected system behavior unchanged.

本轮新增的是 debug-only 输出端口、BD debug 输入端口和 ILA probe 连接。它们只用于观测，不反馈到控制路径。

明确未修改：

```text
rate_state 状态机跳转；
GTX DRP 写序列；
MMCM DRP 写序列；
GT reset sequence；
laser_tx_core 配置加载；
APPLY / ENABLE 行为；
txdata / valid_mask 生成；
外部同步输出逻辑；
UDP/Vitis 命令协议。
```

功能等价性结论基于代码结构检查与 build 后 netlist debug report；尚未执行上板验证。

## 13. 当前是否上板验证

```text
Hardware test was not run.
```

当前只能声明：

```text
debug 结构修复已完成；
bit/LTX 已重新生成；
timing 已通过；
report_debug_core 已确认 dbg_hub/clk = gt_ctrl_clk；
AXI/FCLK ILA 已包含新增 rate probe；
txusrclk2 ILA 已保留。
```

不能声明：

```text
500M<->1000M 动态切换已上板通过；
GTX/MMCM DRP 切换已实测通过；
外部光口链路闭环通过。
```

## 14. 下一步建议

建议上板顺序：

```text
1. Vivado Hardware Manager Program Device；
2. bit 选择：
   D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
3. ltx 选择：
   D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
4. Refresh device，确认不再报 debug hub not detected；
5. 先 trigger AXI/FCLK ILA，观察 rate_state/current_rate/target_rate/error_code；
6. 确认 debug hub 稳定后，再执行 rate status；
7. 最后再进入 rate set 1000 / rate set 500 上板验证。
```


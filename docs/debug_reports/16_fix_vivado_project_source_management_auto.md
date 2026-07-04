# Vivado project source management 修复报告

## 1. 本轮任务范围

本轮只修复 Vivado project source 属性，目标是处理：

```text
[filemgmt 56-176] Module references are not supported in manual compile order mode and will be ignored.
```

以及由 `system.bd` 被 AutoDisabled 引起的：

```text
module 'system' not found
```

本轮不修改 RTL 功能逻辑，不修改 rate controller，不修改 GTX/MMCM DRP 写序列，不修改 Vitis，不重新设计 ILA probe。

## 2. 修改前问题

工程此前处于 manual compile order / `source_mgmt_mode=None` 的遗留状态。该模式不支持 BD Module Reference，因此 Vivado 会忽略 BD 中的 module reference，例如 `laser_tx_core_0`。

随后恢复 automatic source management 后，又暴露出 `system.bd` 文件属性异常：

```text
USED_IN=simulation
USED_IN_SYNTHESIS=0
IS_AUTO_DISABLED=1
```

这导致 `system_wrapper.v` 中例化的 `system` 模块没有进入 synthesis compile order，`synth_1` 报：

```text
ERROR: [Synth 8-439] module 'system' not found
```

另外，sources_1 中曾经存在 direct/manual build 遗留的 generated HDL 普通源拷贝，例如导入的 `system.v` 和 GT Wizard generated HDL。这会造成普通 source 与 BD/IP generated source 混用。

## 3. 修改内容

修改脚本：

```text
D:/FPGA_Learn/laser_tx/scripts/fix_project_source_management_auto.tcl
```

脚本执行的 source 属性修复如下：

1. 将 project source management 恢复为 automatic：

```tcl
set_property source_mgmt_mode All [current_project]
```

2. 强制 project top：

```tcl
set_property top laser_tx_board_top [get_filesets sources_1]
set_property top_file D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v [get_filesets sources_1]
```

3. 只保留一份 ordinary source `system_wrapper.v`：

```text
D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
```

并确保以下 generated wrapper 不作为普通 source 同时参与：

```text
D:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/hdl/system_wrapper.v
```

4. 移除此前 direct/manual flow 遗留的 imported generated HDL 普通源：

```text
D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/sources_1/bd/system/synth/system.v
D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/sources_1/ip/gtwizard_0/...
```

5. 恢复 `system.bd` 用于 synthesis + simulation：

```text
USED_IN=synthesis simulation
USED_IN_SYNTHESIS=1
IS_AUTO_DISABLED=0
```

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| source_mgmt_mode | `None` | `All` | 恢复 Vivado automatic source management，支持 BD Module Reference |
| top | `laser_tx_board_top` | `laser_tx_board_top` | 保持不变 |
| top_file | `rtl/laser_tx_board_top.v` | `rtl/laser_tx_board_top.v` | 保持不变 |
| `system.bd` Used In | `simulation` | `synthesis simulation` | `system` 模块重新进入 synthesis compile order |
| `system.bd` AutoDisabled | `1` | `0` | 解除 BD 自动禁用 |
| `system_wrapper.v` | 曾有 generated/imported 混用风险 | compile order 中只剩 imported wrapper 一份 | 避免重复 wrapper |
| imported generated HDL | 存在 direct flow 遗留普通源 | 已从 sources_1 普通源移除 | 避免 BD/IP generated HDL 混用 |
| rate controller | 未修改 | 未修改 | 功能逻辑不变 |
| GT/MMCM DRP | 未修改 | 未修改 | DRP 写序列不变 |
| Vitis | 未修改 | 未修改 | 软件不变 |

## 5. 输出检查结果

检查摘要文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/source_mgmt_fix/source_mgmt_fix_summary.txt
```

当前结果：

```text
source_mgmt_mode=All
top=laser_tx_board_top
top_file=D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
system_wrapper_files=D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
laser_tx_board_top_files=D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
system_bd_files=D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd
system_bd_USED_IN=synthesis simulation
system_bd_USED_IN_SYNTHESIS=1
system_bd_IS_AUTO_DISABLED=0
imported_generated_hdl_files=
```

`report_compile_order` 中 `system_wrapper.v` 只出现一次：

```text
system_wrapper_compile_order_count=1
30 system_wrapper.v Synth & Sim Verilog xil_defaultlib No D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
```

`report_compile_order` 中 missing instance 已为空：

```text
Missing instances for 'synthesis' with fileset 'sources_1':
< empty >
```

## 6. synth_1 验证结果

只运行了 `synth_1`，没有运行 implementation / bitstream。

结果文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/source_mgmt_fix/synth_1_status.txt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/source_mgmt_fix/synth_1_runme_synth_design_lines.txt
D:/FPGA_Learn/laser_tx/laser_tx.runs/synth_1/runme.log
```

`synth_1` 状态：

```text
synth_1_status=synth_design Complete!
```

`runme.log` 中 top 正确：

```text
Command: synth_design -top laser_tx_board_top -part xc7z100ffg900-2
synth_design completed successfully
```

最新 `runme.log` 未再出现：

```text
Module references are not supported in manual compile order mode
module 'system' not found
```

## 7. 仍存在但非本轮目标的提示

最新 `synth_1` 中还有一条 incremental synthesis checkpoint 相关 Critical Warning：

```text
[Synth 8-6895] The reference checkpoint ... system_wrapper.dcp is not suitable for use with incremental synthesis ...
Synthesis will continue with the default flow
```

Vivado 已自动回退 default flow，且 synthesis 完成。本轮用户要求只修 project source 属性，因此没有继续修改 run strategy 或 incremental synthesis 设置。

## 8. 硬件接口一致性说明

本轮未修改：

- RTL 功能逻辑；
- `laser_gt_rate_switch_500m_1000m.v`；
- `laser_gt_tx_profile0.v`；
- GTX/MMCM DRP 写序列；
- Vitis / BSP / UDP；
- BD 内部功能连接；
- AXI 地址映射；
- 外部端口；
- XDC；
- bit/LTX。

本轮仅修改 Vivado project source 管理属性，使 BD/IP/Module Reference 回到 automatic source management 的正规 flow。

## 9. 当前结论

本轮已完成 project source 属性收口：

```text
source_mgmt_mode=All
system.bd USED_IN=synthesis simulation
USED_IN_SYNTHESIS=1
IS_AUTO_DISABLED=0
top=laser_tx_board_top
top_file=D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
system_wrapper 仅一份参与 compile order
synth_design -top laser_tx_board_top
synth_1 通过
```

因此，原始 `[filemgmt 56-176] Module references are not supported in manual compile order mode` 已通过恢复 automatic source management 处理；`system` 模块找不到的问题也通过启用 `system.bd` synthesis 使用解决。

## 10. 后续建议

1. 如果希望 GUI 中完全无 Critical Warning，可后续单独处理 stale incremental synthesis checkpoint 设置；
2. 下一步若要生成 bit/LTX，应在当前 automatic source management 状态下继续跑 implementation / bitstream；
3. 不要再切回 `source_mgmt_mode None`；
4. 不要再把 BD/IP generated HDL 拷贝作为普通 source 混入 sources_1；
5. 不要使用 blackbox stub / `read_checkpoint -cell` 与 project/IP flow 混用。

# PS7 OOC DCP source origin 定位报告

## 1. 本轮任务范围

本轮只定位 `system_processing_system7_0_0.dcp` 为什么会在综合时重新出现在 `sources_1` 中，并确认是否仍触发 `[Project 1-840]`。

本轮未修改：

- RTL 功能逻辑；
- `laser_gt_rate_switch_500m_1000m.v`；
- `laser_gt_tx_profile0.v`；
- GT/MMCM DRP 写序列；
- Vitis / BSP / UDP；
- BD 功能连接；
- ILA probe；
- XDC；
- bit/LTX。

本轮没有删除磁盘上的 DCP 文件。

## 2. 当前问题

用户在 GUI 中移除 `system_processing_system7_0_0.dcp` 后，重新综合时该 DCP 又回到工程视图，并怀疑它被某个脚本或 source set 重新作为普通 source 加回 `sources_1`，进而触发：

```text
[Project 1-840]
```

本轮目标是查清楚：

1. 这个 DCP 是否在 `sources_1`；
2. 是否有脚本显式 `add_files` 或 `read_checkpoint` 它；
3. 如果它在 `sources_1`，能否只从 project source set 移除；
4. 重新打开工程和重新跑 `synth_1` 后是否还出现 `[Project 1-840]`。

## 3. 执行的检查

执行脚本：

```text
D:/FPGA_Learn/laser_tx/scripts/check_and_remove_ps7_dcp_source.tcl
```

该脚本执行：

```tcl
get_files -of_objects [get_filesets sources_1] *system_processing_system7_0_0.dcp
get_files -all *system_processing_system7_0_0.dcp
report_property <dcp_file_object>
remove_files <dcp_file_object>
close_project
open_project
update_compile_order
reset_run synth_1
launch_runs synth_1
```

同时保留：

```text
source_mgmt_mode=All
top=laser_tx_board_top
top_file=D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
system.bd USED_IN=synthesis simulation
system.bd USED_IN_SYNTHESIS=1
system.bd IS_AUTO_DISABLED=0
```

## 4. 查询结果

查询报告目录：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/ps7_dcp_source_check/
```

### 4.1 DCP 在 sources_1 中的状态

`get_files -of_objects [get_filesets sources_1] *system_processing_system7_0_0.dcp` 返回：

```text
d:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/ip/system_processing_system7_0_0/system_processing_system7_0_0.dcp
```

`get_files -all *system_processing_system7_0_0.dcp` 同样返回该路径。

该 file object 属性：

```text
FILESET_NAME=sources_1
USED_IN=synthesis implementation
USED_IN_SYNTHESIS=1
USED_IN_IMPLEMENTATION=1
IS_AUTO_DISABLED=0
IS_GENERATED=1
IS_AVAILABLE=1
FILE_TYPE=Design Checkpoint
NAME=d:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/ip/system_processing_system7_0_0/system_processing_system7_0_0.dcp
```

关键点是：

```text
IS_GENERATED=1
PARENT_COMPOSITE_FILE=.../system_processing_system7_0_0.xci
```

这说明它不是手动加入的普通 HDL/source 文件，而是 BD 中 PS7 IP 的 OOC generated DCP，由父 IP/XCI 管理。

### 4.2 remove_files 结果

脚本尝试只从 project source set 移除该 file object：

```tcl
remove_files <system_processing_system7_0_0.dcp>
```

Vivado 返回：

```text
CRITICAL WARNING: [filemgmt 20-1679] Unable to remove the file:
.../system_processing_system7_0_0.dcp
from the fileset 'sources_1'.
File is part of a sub-design (IP, Block Design, DSP Design, etc.) and must be removed via the sub-design parent.
```

这条信息明确说明：该 DCP 是 sub-design 的一部分，不能作为普通 source 从 `sources_1` 直接移除。它会由 `system.bd -> system_processing_system7_0_0.xci -> OOC DCP` 自动管理。

## 5. 谁把 DCP 加回 sources_1

结论：不是脚本，也不是手动普通 source。

真正来源是：

```text
system.bd
  -> system_processing_system7_0_0.xci
      -> generated OOC DCP
          -> system_processing_system7_0_0.dcp
```

也就是 Vivado automatic source management 在解析 BD/IP 子设计时自动把 PS7 IP 的 OOC checkpoint 作为 generated implementation/synthesis artifact 暴露到 fileset 中。

这与手动 `add_files *.dcp` 或手动 `read_checkpoint -cell` 不是同一类行为。

## 6. 工程与脚本搜索结果

搜索范围包括：

```text
laser_tx.xpr
scripts/*.tcl
*.tcl
```

关键结果：

- 未发现脚本显式 `add_files system_processing_system7_0_0.dcp`；
- 未发现脚本显式 `read_checkpoint` 该 PS7 DCP；
- `scripts/*direct*.tcl` 中存在 direct build 自己写出的 checkpoint，例如 `post_synth_dynamic_500m_1000m.dcp`、`mmcm_txoutclk_debug_impl.dcp`，但这些不是 `system_processing_system7_0_0.dcp`；
- `laser_tx.xpr` 中存在 `synth_1` incremental checkpoint 设置，指向的是 `laser_tx_board_top.dcp`，不是 `system_processing_system7_0_0.dcp`；
- `reset_ila_child_run_state.tcl` 中只是检查 ILA DCP 是否存在，不会添加 PS7 DCP。

因此，当前没有证据表明某个 Tcl 脚本把 `system_processing_system7_0_0.dcp` 当普通 source 手动加回。

## 7. 重新打开工程后的复查

关闭并重新打开工程后：

```text
source_mgmt_mode=All
top=laser_tx_board_top
top_file=D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
system_bd_USED_IN=synthesis simulation
system_bd_USED_IN_SYNTHESIS=1
system_bd_IS_AUTO_DISABLED=0
system_wrapper_files=D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
```

`system_processing_system7_0_0.dcp` 仍返回：

```text
sources_1_dcp=d:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/bd/system/ip/system_processing_system7_0_0/system_processing_system7_0_0.dcp
```

但这是 BD/IP 子设计自动生成产物，不是普通 source 混用。

## 8. synth_1 验证结果

重新运行 `synth_1`：

```text
synth_1_status=synth_design Complete!
```

`runme.log` 关键行：

```text
Command: synth_design -top laser_tx_board_top -part xc7z100ffg900-2
Synthesis finished with 0 errors, 0 critical warnings and 142 warnings.
synth_design completed successfully
```

最新 `runme.log` 未出现：

```text
[Project 1-840]
[filemgmt 56-176] Module references are not supported in manual compile order mode
module 'system' not found
```

## 9. 修改前后差异表

| 项目 | 修改前/疑点 | 检查后结论 | 影响 |
| --- | --- | --- | --- |
| DCP 是否在 sources_1 | 是 | 是，但 `IS_GENERATED=1` 且属于 sub-design parent | 不是手动普通 source |
| DCP 是否可 remove_files | 期望可移除 | Vivado 明确拒绝，提示必须通过 sub-design parent 管理 | 不能直接移除该 generated DCP |
| 谁加回 DCP | 怀疑脚本或 GUI 普通 source | `system.bd -> PS7 XCI -> OOC DCP` 自动生成 | 属于 BD/IP 正常链路 |
| 是否删除磁盘 DCP | 禁止 | 未删除 | 符合要求 |
| system.bd synthesis | 必须保留 | `USED_IN=synthesis simulation` | 正常 |
| source_mgmt_mode | automatic | `All` | 正常 |
| top | `laser_tx_board_top` | `laser_tx_board_top` | 正常 |
| system_wrapper | 只保留一份 | imported wrapper 一份 | 正常 |
| `[Project 1-840]` | 用户看到过 | 最新 synth_1 未出现 | 当前已不复现 |

## 10. 硬件接口一致性说明

本轮未修改：

- RTL 功能逻辑；
- BD 功能连接；
- XDC；
- wrapper 端口；
- AXI 地址映射；
- PS MIO/EMIO；
- GT/MMCM DRP 写序列；
- Vitis/BSP/UDP；
- ILA probe；
- bit/LTX。

Clock/reset behavior unchanged。

AXI address map unchanged。

## 11. 当前结论

`system_processing_system7_0_0.dcp` 会重新出现在 `sources_1`，根因不是某个脚本或用户手动普通 source 加回，而是 Vivado automatic source management 从 `system.bd` 的 PS7 IP 子设计自动暴露 OOC generated DCP。

该 DCP 的关键属性是：

```text
IS_GENERATED=1
FILE_TYPE=Design Checkpoint
PARENT_COMPOSITE_FILE=system_processing_system7_0_0.xci
```

因此不能也不应该通过删除磁盘 DCP 或普通 `remove_files` 强行处理。当前最新 `synth_1` 已通过，且没有 `[Project 1-840]`。

## 12. 后续建议

1. 不要继续手动删除 `system_processing_system7_0_0.dcp`；
2. 不要把 BD/IP generated OOC DCP 与手动普通 source DCP 混为一类；
3. 如果 GUI 再显示 `[Project 1-840]`，应记录具体是哪一个 DCP 路径触发，因为当前 PS7 DCP 在最新 `synth_1` 中未触发；
4. 继续保持 `source_mgmt_mode=All`；
5. 继续保持 `system.bd` 用于 synthesis + simulation；
6. 不要切回 manual compile order；
7. 不要使用 blackbox stub / `read_checkpoint -cell` 混用 project/IP flow。

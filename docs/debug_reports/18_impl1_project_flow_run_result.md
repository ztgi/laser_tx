# impl_1 project flow 运行结果报告

## 1. 本轮任务范围

本轮只运行主工程 implementation / bitstream flow，用于判断 `impl_1` 是否真正失败，以及失败是否由 `[Project 1-840]` 引起。

本轮未修改：

- RTL 功能逻辑；
- BD 功能连接；
- GT/MMCM DRP 写序列；
- ILA probe；
- Vitis；
- XDC；
- `system_processing_system7_0_0.dcp`；
- source set。

本轮没有修复 `MMCM_LOCK_TIMEOUT`，没有上板验证，也不声明 500M -> 1000M 动态切换成功。

## 2. 运行前工程属性

运行前复核文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/project_impl1/pre_impl_project_properties.txt
```

内容：

```text
source_mgmt_mode=All
top=laser_tx_board_top
top_file=D:/FPGA_Learn/laser_tx/rtl/laser_tx_board_top.v
system_wrapper_files=D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v
system_bd_files=D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/bd/system/system.bd
system_bd_USED_IN=synthesis simulation
system_bd_USED_IN_SYNTHESIS=1
system_bd_IS_AUTO_DISABLED=0
```

说明当前工程仍保持 automatic source management，`system.bd` 参与 synthesis，top/top_file 正确，`system_wrapper.v` 只有 imported wrapper 这一份。

## 3. 执行命令

执行脚本：

```text
D:/FPGA_Learn/laser_tx/scripts/run_impl1_bitstream_project_flow.tcl
```

脚本执行的 Vivado run 操作：

```tcl
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

## 4. impl_1 结果

状态摘要文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/project_impl1/impl1_status_summary.txt
```

结果：

```text
impl_1_STATUS=opt_design ERROR
impl_1_PROGRESS=20%
impl_1_DIR=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1
impl_1_runme=D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/runme.log
```

因此，本轮 `impl_1` 确实失败，但失败点发生在 `opt_design` 前置脚本阶段，不是 bitstream 阶段。

## 5. impl_1/runme.log 第一条 ERROR

`impl_1/runme.log` 中没有 `ERROR:` 前缀行。

日志中第一条实际导致 run 退出的失败诊断是：

```text
GT Profile 0 CDC constraint failed: expected one clk_fpga_0 clock; got ''.
sourcing script D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl failed
```

对应位置：

```text
runme.log:70 GT Profile 0 CDC constraint failed: expected one clk_fpga_0 clock; got ''.
runme.log:71 sourcing script D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl failed
```

因此，当前第一故障点应定位到：

```text
D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl
```

该脚本期望实现设计中存在唯一的 `clk_fpga_0` clock，但当前 `link_design` 后查询结果为空。

## 6. [Project 1-840] 是否为失败根因

`runme.log` 中确实出现多条 `[Project 1-840]` Critical Warning，例如：

```text
CRITICAL WARNING: [Project 1-840] The design checkpoint file
.../system_processing_system7_0_0.dcp
was generated for an IP by an out of context synthesis run ...
```

但是后续日志显示：

```text
link_design completed successfully
```

也就是说 `[Project 1-840]` 没有阻止 `link_design` 完成。本轮 `impl_1` 真正停止在后续 source pre-hook：

```text
source D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl
GT Profile 0 CDC constraint failed: expected one clk_fpga_0 clock; got ''.
```

因此，不能把 `[Project 1-840]` 自动当作 implementation 失败根因。

## 7. write_bitstream / bit / ltx 状态

本轮没有进入 `write_bitstream`。

状态：

```text
write_bitstream_lines=
bit_exists=0
ltx_exists=0
```

未生成：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

因此也没有复制新的 bit/LTX 到：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/
```

## 8. timing / debug report 状态

由于 `impl_1` 在 `opt_design` 前置脚本阶段失败，未打开 implemented design，因此本轮未生成新的：

```text
impl1_timing_summary.rpt
impl1_debug_core_full_path.rpt
```

WNS / TNS / WHS / THS 本轮不可用。

## 9. 修改前后差异表

| 项目 | 运行前 | 运行后 | 影响 |
| --- | --- | --- | --- |
| source_mgmt_mode | `All` | `All` | 未改变 |
| top | `laser_tx_board_top` | `laser_tx_board_top` | 未改变 |
| top_file | `rtl/laser_tx_board_top.v` | `rtl/laser_tx_board_top.v` | 未改变 |
| system.bd | synthesis + simulation | synthesis + simulation | 未改变 |
| RTL 功能逻辑 | 未改 | 未改 | 功能不变 |
| DRP 写序列 | 未改 | 未改 | 功能不变 |
| Vitis | 未改 | 未改 | 软件不变 |
| impl_1 | Not started | `opt_design ERROR` | 失败于 pre-hook clock check |
| bit/LTX | 无主工程 impl_1 新产物 | 仍无 | 不可上板使用 |
| `[Project 1-840]` | 预期可能出现 | 出现但 link_design 成功 | 不是当前失败根因 |

## 10. 硬件接口一致性说明

本轮未修改任何硬件接口：

- 未新增/删除/重命名顶层端口；
- 未改变端口方向或位宽；
- 未改变 AXI 地址；
- 未改变 PS MIO/EMIO；
- 未改变 clock/reset topology；
- 未改变 GT/MMCM DRP 控制；
- 未改变 ILA probe；
- 未改变 Vitis 软件可见行为。

Clock/reset behavior unchanged。

AXI address map unchanged。

## 11. 当前结论

本轮主工程 `impl_1` 已实际运行，并确认：

```text
impl_1_STATUS=opt_design ERROR
impl_1_PROGRESS=20%
```

当前没有 `ERROR:` 前缀行，但第一条导致 run 停止的失败诊断是：

```text
GT Profile 0 CDC constraint failed: expected one clk_fpga_0 clock; got ''.
```

`[Project 1-840]` 是 BD/IP OOC DCP 相关 Critical Warning，但本轮不是失败根因，因为 `link_design completed successfully` 已经在其后出现。

## 12. 下一步建议

下一步不要继续处理或删除 `system_processing_system7_0_0.dcp`。

应只定位：

```text
D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl
```

为什么在当前 project implementation netlist 中找不到唯一 `clk_fpga_0` clock。建议先只读检查该脚本中对 `clk_fpga_0` 的匹配方式，以及当前 `link_design` 后实际 clock 名称是否变成了 `u_system_wrapper/system_i/processing_system7_0/inst/FCLK_CLK0`、`gt_ctrl_clk` 或其他 Vivado 自动命名。

在修复该 pre-hook clock 名称匹配前，不应继续声明 bit/LTX 已生成，也不应进入上板动态切换验证。

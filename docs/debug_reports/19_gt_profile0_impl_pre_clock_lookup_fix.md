# GT Profile0 impl pre-hook 时钟查找修复与失败定位报告

## 1. 本轮问题背景

本轮只处理 `scripts/gt_profile0_impl_pre.tcl` 中 AXI/FCLK 时钟查找失败的问题，不处理 `system_processing_system7_0_0.dcp`，也不继续处理 `[Project 1-840]`。

当前 `impl_1` 真正停止点为：

```text
GT Profile 0 CDC constraint failed: expected one clk_fpga_0 clock; got ''.
```

该问题发生在 implementation pre-hook 中，原脚本假设 AXI/FCLK clock object 一定名为 `clk_fpga_0`，并直接执行固定名称查找。实际 Vivado run 环境中，该 clock object 可能不存在或名称/约束加载状态不同，因此 hard-code 查找会导致 pre-hook 失败。

## 2. 本轮修改范围

本轮只修改/新增 Vivado Tcl 诊断与 pre-hook 查找逻辑：

| 文件 | 类型 | 说明 |
| --- | --- | --- |
| `scripts/gt_profile0_impl_pre.tcl` | 修改 | 将固定 `get_clocks clk_fpga_0` 改为分层查找：优先 `gt_ctrl_clk` net，其次 `FCLK_CLK0` pin，最后 clock 名称匹配。 |
| `scripts/query_link_design_clocks_for_gt_profile0.tcl` | 新增/修改 | 只读查询脚本，用于在已综合设计中输出 clock/net/pin 对应关系。 |
| `docs/debug_reports/19_gt_profile0_impl_pre_clock_lookup_fix.md` | 新增 | 本报告。 |

未修改：

```text
RTL
BD 功能连接
XDC 板级约束
GTX/MMCM DRP 写序列
rate controller 功能
Vitis / BSP / UDP 协议
ILA probe 列表
system_processing_system7_0_0.dcp / PS7 OOC DCP source set
source_mgmt_mode
manual compile order
```

## 3. read-only 时钟查询结果

执行只读查询后，在 `open_run synth_1` 查询环境中可以看到 AXI/FCLK clock object：

```text
get_clocks:
  clk_fpga_0
```

关键查询结果：

```text
get_nets -hier *gt_ctrl_clk* =
  gt_ctrl_clk
  u_system_wrapper/gt_ctrl_clk
  u_system_wrapper/system_i/gt_ctrl_clk

get_pins -hier *FCLK_CLK0* =
  u_system_wrapper/system_i/processing_system7_0/FCLK_CLK0
  u_system_wrapper/system_i/processing_system7_0/inst/FCLK_CLK0

get_clocks -of_objects [get_nets -hier *gt_ctrl_clk*] =
  clk_fpga_0

get_clocks -of_objects [get_pins -hier *FCLK_CLK0*] =
  clk_fpga_0
```

因此，从结构查询看，AXI/FCLK/`gt_ctrl_clk` 对应的 clock object 应为：

```text
clk_fpga_0, period = 20 ns
```

只读查询输出文件：

```text
reports/dynamic_rate_500m_1000m/gt_profile0_clock_query/link_design_clock_query.txt
reports/dynamic_rate_500m_1000m/gt_profile0_clock_query/report_clocks_after_open_synth.rpt
```

## 4. pre-hook 修改前后差异

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| AXI/FCLK clock 查找 | 只执行 `get_clocks clk_fpga_0` | 优先通过 `gt_ctrl_clk` net 找 clock；其次通过 `FCLK_CLK0` pin；最后尝试 `*clk_fpga_0*` / `*FCLK_CLK0*` 名称匹配 | 避免只依赖固定 clock 名称 |
| 多候选处理 | 未处理 | 打印候选并报错，不盲选 | 防止错误约束到非目标时钟 |
| 无候选处理 | 报 `expected one clk_fpga_0` | 打印 `get_clocks`、`gt_ctrl_clk` net、`clk_fpga_0` net、`FCLK_CLK0` pin 后报错 | 失败诊断更明确 |
| CDC/debug hub 约束意图 | AXI/FCLK 与 GT/user clock 异步分组，dbg_hub/clk 绑定到 gt_ctrl_clk | 保持不变 | 不改变设计功能或 debug intent |
| 功能逻辑 | 不涉及 | 不涉及 | RTL/DRP/Vitis 行为不变 |

## 5. 重新运行 impl_1 结果

执行：

```tcl
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

当前结果：

```text
impl_1 STATUS   = opt_design ERROR
impl_1 PROGRESS = 20%
```

未生成：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

`impl_1/runme.log` 显示 `link_design completed successfully`，随后在 pre-hook 中停止。

## 6. 当前最新第一条真正失败点

当前最新失败点不是 `[Project 1-840]`，而是 pre-hook 在 implementation run 环境中无法找到 AXI/FCLK clock object。

`impl_1/runme.log` 中关键输出：

```text
link_design completed successfully
source D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl

INFO: Available clocks:
  u_laser_gt_tx_profile0/.../GTXE2_i/TXOUTCLK
  u_laser_gt_tx_profile0/.../GTXE2_i/TXOUTCLKFABRIC
  u_laser_gt_tx_profile0/.../GTXE2_i/RXOUTCLKFABRIC
  u_laser_gt_tx_profile0/.../GTXE2_i/RXOUTCLK
  MGT_REFCLK_125M
  clkfbout
  clkout0_txusrclk2
  clkout1_txusrclk

INFO: gt_ctrl_clk nets:
  gt_ctrl_clk
  u_system_wrapper/gt_ctrl_clk
  u_system_wrapper/system_i/gt_ctrl_clk

INFO: clk_fpga_0 nets:
  <empty>

INFO: FCLK_CLK0 pins:
  u_system_wrapper/system_i/processing_system7_0/FCLK_CLK0
  u_system_wrapper/system_i/processing_system7_0/inst/FCLK_CLK0

GT Profile 0 CDC constraint failed:
  cannot resolve unique AXI/FCLK clock from gt_ctrl_clk net, FCLK_CLK0 pin, or clock name match.
```

这说明：

1. implementation pre-hook 中 `gt_ctrl_clk` net 和 `FCLK_CLK0` pin 都存在；
2. 但这些对象在当前 run 环境中没有关联到任何 clock object；
3. `get_clocks` 列表中没有 `clk_fpga_0`；
4. 因此脚本没有盲选其它 clock，而是按要求停止。

## 7. 为什么不是 [Project 1-840] 根因

本轮没有继续处理 `system_processing_system7_0_0.dcp` 或 `[Project 1-840]`。

原因是本次日志中可以看到：

```text
link_design completed successfully
```

随后才进入：

```text
source D:/FPGA_Learn/laser_tx/scripts/gt_profile0_impl_pre.tcl
```

并在 AXI/FCLK clock 查找处停止。因此当前失败根因应记录为：

```text
impl pre-hook 环境中 AXI/FCLK clock object 缺失或未被约束加载。
```

而不是：

```text
[Project 1-840] 直接导致 implementation 失败。
```

## 8. 当前判断

本轮已经完成了用户要求的“不要只写死 `clk_fpga_0`”修复：脚本现在会按 `gt_ctrl_clk` net、`FCLK_CLK0` pin、clock 名称匹配的顺序查找，并在多候选或无候选时明确报错。

但是 implementation run 环境中实际没有 AXI/FCLK clock object，因此 build 仍不能继续到 bitstream。

这不是 rate controller、GTX/MMCM DRP、Vitis 或 ILA probe 功能问题；它是 implementation 约束/run 环境中的 FCLK clock object 缺失问题。

## 9. 后续最小建议

下一步不应继续处理 PS7 OOC DCP，也不应修改 RTL/DRP/Vitis。

建议用户确认是否允许在 `gt_profile0_impl_pre.tcl` 中加入一个受控 fallback：

```text
当 gt_ctrl_clk net 和 FCLK_CLK0 pin 存在，但没有对应 clock object 时，
在 pre-hook 中基于 FCLK_CLK0 pin 或 gt_ctrl_clk net 显式补建 clk_fpga_0 20 ns clock，
然后再执行 CDC clock group 与 dbg_hub/clk 绑定检查。
```

该动作属于约束补全，不改变硬件功能逻辑，但它不再只是“查找 clock object”，而是“在缺失时创建 clock object”。因此本轮没有擅自加入。

## 10. 构建与验证记录

| 项目 | 结果 |
| --- | --- |
| read-only clock query | 已执行 |
| `gt_profile0_impl_pre.tcl` robust lookup | 已修改 |
| `reset_run impl_1` | 已执行 |
| `launch_runs impl_1 -to_step write_bitstream -jobs 4` | 已执行 |
| `wait_on_run impl_1` | 已执行 |
| impl_1 STATUS | `opt_design ERROR` |
| bitstream | 未生成 |
| LTX | 未生成 |
| timing WNS/TNS/WHS/THS | 未生成，implementation 未完成 |
| hardware test | 未执行 |

## 11. 功能等价性与边界

Expected system behavior unchanged。

本轮没有修改 RTL、BD 功能连接、GTX/MMCM DRP、Vitis、UDP 协议或 ILA probe，因此不会改变 laser_tx 数据路径、rate controller 状态机、AXI 地址、BRAM/GPIO/GT status 寄存器语义。

当前不能声明：

```text
implementation 通过；
bit/LTX 已生成；
MMCM_LOCK_TIMEOUT 已修复；
500M -> 1000M 动态切换通过。
```

当前只能声明：

```text
pre-hook 已从硬编码 clock 名称改为分层查找并带诊断；
impl_1 最新失败点已定位为 implementation pre-hook 环境中 AXI/FCLK clock object 缺失。
```

## 12. 受控 fallback 后的最终 build 结果

在用户确认允许“只补全 AXI/FCLK clock constraint”的前提下，`scripts/gt_profile0_impl_pre.tcl` 进一步加入了受控 fallback。

fallback 触发条件为：

```text
1. 分层查找没有找到 AXI/FCLK clock object；
2. 当前不存在同名 clk_fpga_0 clock；
3. 能唯一筛选到 PS7 generated instance pin：
   u_system_wrapper/system_i/processing_system7_0/inst/FCLK_CLK0
```

满足上述条件时，脚本执行：

```tcl
create_clock -name clk_fpga_0 -period 20.000 \
    [get_pins u_system_wrapper/system_i/processing_system7_0/inst/FCLK_CLK0]
```

随后再次检查：

```text
get_clocks clk_fpga_0                         = clk_fpga_0
get_clocks -of_objects FCLK_CLK0 pin          = clk_fpga_0
get_clocks -of_objects *gt_ctrl_clk* net      = clk_fpga_0
```

`impl_1/runme.log` 关键证据：

```text
INFO: AXI/FCLK clock object missing; creating controlled fallback clock clk_fpga_0 on u_system_wrapper/system_i/processing_system7_0/inst/FCLK_CLK0 with period 20.000 ns.
INFO: AXI/FCLK fallback get_clocks clk_fpga_0: clk_fpga_0
INFO: AXI/FCLK fallback clocks of FCLK_CLK0 pin: clk_fpga_0
INFO: AXI/FCLK fallback clocks of gt_ctrl_clk nets: clk_fpga_0
INFO: AXI/FCLK clock resolved from controlled fallback create_clock: clk_fpga_0
INFO: GT Profile 0 CDC AXI/FCLK clock used: clk_fpga_0
INFO: Applied asynchronous clock groups: clk_fpga_0 <-> ... TXOUTCLK clkout1_txusrclk clkout0_txusrclk2
INFO: dbg_hub/clk forced to AXI/FCLK net: gt_ctrl_clk
write_bitstream completed successfully
```

## 13. implementation / bitstream / LTX 结果

重新执行：

```tcl
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

结果：

```text
impl_1 STATUS   = write_bitstream Complete!
impl_1 PROGRESS = 100%
```

生成文件：

| 文件 | size | LastWriteTime |
| --- | ---: | --- |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit` | 17416462 | 2026-07-03 17:47:27 |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx` | 154556 | 2026-07-03 17:48:19 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 17416462 | 2026-07-03 17:47:27 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 154556 | 2026-07-03 17:48:19 |

## 14. timing 结果

timing report：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/project_impl1/impl1_timing_summary.rpt
```

Design Timing Summary：

| Metric | Result |
| --- | ---: |
| WNS | 7.029 ns |
| TNS | 0.000 ns |
| TNS failing endpoints | 0 |
| WHS | 0.045 ns |
| THS | 0.000 ns |
| THS failing endpoints | 0 |

Vivado 报告：

```text
All user specified timing constraints are met.
```

## 15. debug core 检查结果

debug report：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/project_impl1/impl1_debug_core_full_path.rpt
```

debug core 列表：

```text
dbg_hub
ila_laser_axi_cfg
ila_laser_tx
```

`dbg_hub/clk`：

```text
Net Name = gt_ctrl_clk
C_CLK_INPUT_FREQ_HZ = 50000000
```

`ila_laser_axi_cfg/clk`：

```text
u_system_wrapper/system_i/gt_ctrl_clk
```

`ila_laser_axi_cfg` probe port 数：

```text
probe0 ... probe49，共 50 个 probe port
```

`ila_laser_tx` 保留为 txusrclk2 域 ILA。该 ILA 作为 TX 域发送数据/状态观测窗口，不作为 debug hub 主时钟来源。

## 16. 当前最终结论

本轮已完成：

```text
1. 修复 gt_profile0_impl_pre.tcl 中 AXI/FCLK clock 查找逻辑；
2. 在 clock object 缺失时，仅对 AXI/FCLK clock constraint 做受控 create_clock fallback；
3. 保持 dbg_hub/clk = gt_ctrl_clk；
4. 保持 ila_laser_axi_cfg = gt_ctrl_clk 域；
5. 保持 ila_laser_tx = txusrclk2 域；
6. 重新生成同源 bit/LTX；
7. timing 通过。
```

本轮没有完成、也不能声明：

```text
MMCM_LOCK_TIMEOUT 已修复；
500M -> 1000M 动态切换已上板通过；
外部光口闭环验证通过。
```

当前结果只说明：

```text
主工程 implementation / bitstream / LTX 已重新收口；
debug hub clock 与 AXI/FCLK ILA clock 结构已按当前约束意图固定到 gt_ctrl_clk；
可以进入下一轮上板加载匹配 bit/LTX 后继续观察 MMCM_LOCK_TIMEOUT 根因。
```

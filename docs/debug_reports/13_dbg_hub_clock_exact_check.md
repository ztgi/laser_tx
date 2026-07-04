# dbg_hub clock 精确核查报告

## 1. 本轮问题现象

用户在 Vivado GUI schematic 中手动观察到 `dbg_hub/clk` 似乎仍连接到 `gt_txusrclk2`，因此要求只收口 debug hub clock，不继续推进 `rate set`、GTX/MMCM DRP、Vitis 或其它功能。

同时，用户执行类似命令：

```tcl
report_debug_core [get_debug_cores]
```

时遇到 `Too many positional options`。本轮确认该问题不是 debug core 本身错误，而是 Vivado 2022.2 的 `report_debug_core` 命令语法限制：该命令不接受 debug core 对象作为位置参数。

## 2. 当前已执行的检查

执行命令：

```bat
call D:\Vitis\2022.2\settings64.bat
vivado -mode batch -source scripts/check_debug_core_clocks_exact.tcl
```

脚本执行内容：

```tcl
open_project D:/FPGA_Learn/laser_tx/laser_tx.xpr
open_run impl_1
get_debug_cores
report_debug_core -full_path
get_pins -hier -filter {NAME =~ "*dbg_hub*clk*"}
get_nets -of_objects <pin>
get_clocks -of_objects <net>
```

生成文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_core_clock_exact_check.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_core_probe_list_full_path.rpt
```

## 3. implemented design 中 debug core 列表

当前 `impl_1` 中存在 3 个 debug core：

```text
dbg_hub
u_system_wrapper/system_i/ila_laser_axi_cfg
u_system_wrapper/system_i/ila_laser_tx
```

## 4. debug clock 精确结果

`report_debug_core -full_path` 给出的 clock 结果：

```text
dbg_hub:
  C_CLK_INPUT_FREQ_HZ = 50000000
  clk = gt_ctrl_clk

ila_laser_axi_cfg:
  clk = u_system_wrapper/system_i/gt_ctrl_clk

ila_laser_tx:
  clk = u_system_wrapper/system_i/txusrclk2
```

implemented netlist pin/net 直接查询结果：

```text
PIN=dbg_hub/clk
NETS=gt_ctrl_clk
NET_NAME=gt_ctrl_clk
CLOCKS=clk_fpga_0
DRIVER_PINS=u_system_wrapper/gt_ctrl_clk
```

因此，当前 `impl_1` 的实际 debug hub 顶层时钟连接为：

```text
dbg_hub/clk = gt_ctrl_clk = clk_fpga_0 / PS FCLK0
```

不是：

```text
dbg_hub/clk = gt_txusrclk2
```

## 5. ILA clock 结果

| Debug core | Clock | 所属时钟域 | 结论 |
|---|---|---|---|
| `dbg_hub` | `gt_ctrl_clk` | AXI/FCLK / PS FCLK0 | 已改到稳定 FCLK 域 |
| `ila_laser_axi_cfg` | `u_system_wrapper/system_i/gt_ctrl_clk` | AXI/FCLK / PS FCLK0 | 符合要求 |
| `ila_laser_tx` | `u_system_wrapper/system_i/txusrclk2` | TXUSRCLK2 域 | 保留为 TX 发送侧 ILA |

## 6. 旧连接来源排查

搜索范围：

```text
constraints/
scripts/
laser_tx.srcs/constrs_1/
```

发现如下与 `dbg_hub/clk` 相关的位置：

### 6.1 当前生效修复路径

```text
scripts/gt_profile0_impl_pre.tcl
```

当前实现前 hook 中包含：

```tcl
disconnect_debug_port dbg_hub/clk
connect_debug_port dbg_hub/clk $dbg_hub_clk_net
set_property C_CLK_INPUT_FREQ_HZ 50000000 $dbg_hub_core
```

其中 `$dbg_hub_clk_net` 解析为：

```text
gt_ctrl_clk
```

### 6.2 direct build 备用路径

```text
scripts/build_dynamic_500m_1000m_direct.tcl
```

该脚本也会将 `dbg_hub/clk` 强制连接到 `gt_ctrl_clk`。本轮没有使用 direct build 重新生成 bitstream。

### 6.3 残留但本次 impl_1 未作为最终连接依据的旧约束文本

```text
laser_tx.srcs/constrs_1/new/laser_tx_board_io.xdc
```

其中残留：

```tcl
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk]
```

该文件内容容易误导 GUI/source inspection。当前 `impl_1` 的最终事实以 `report_debug_core -full_path` 和 `get_pins/get_nets` implemented netlist 查询为准，结果为 `dbg_hub/clk = gt_ctrl_clk`。

## 7. 为什么 GUI schematic 可能看到旧连接

当前 batch 检查打开的是：

```tcl
open_run impl_1
```

并直接查询 implemented netlist。若 GUI schematic 仍显示 `dbg_hub/clk = gt_txusrclk2`，常见原因包括：

1. GUI 打开的不是最新 `impl_1` implemented schematic；
2. GUI 仍停留在旧 synthesized design 或旧 schematic tab；
3. GUI 中 module references / debug setup 状态 out-of-date；
4. Hardware Manager 加载了旧 bit/LTX；
5. 手动展开到的是某个旧 debug insertion 视图，而不是当前 `impl_1` 最终 routed netlist。

建议在 GUI 中执行：

```tcl
close_design
open_run impl_1
report_debug_core -full_path
```

然后再从当前 implemented design 打开 schematic。

## 8. bit/LTX 与 timing 记录

当前同源 bit/LTX：

| 文件 | 大小 | 修改时间 |
|---|---:|---|
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit` | 17416462 | 2026-07-01 21:39:13 |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx` | 107574 | 2026-07-01 21:40:00 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 17416462 | 2026-07-01 21:39:13 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 107574 | 2026-07-01 21:40:00 |

Timing 报告：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/debug_ila_fix_timing_summary.rpt
```

结果：

```text
WNS = 7.029 ns
TNS = 0.000 ns
All user specified timing constraints are met.
```

## 9. 本轮修改内容

本轮只修改检查脚本与新增文档：

| 文件 | 修改内容 | 影响 |
|---|---|---|
| `scripts/check_debug_core_clocks_exact.tcl` | 修正 clock-like pin 查询列表解析错误；去除 Vivado 2022.2 不支持的 debug core 属性遍历；改用 `report_debug_core -full_path` 与 implemented netlist pin/net 查询 | 仅用于 debug clock 核查，不改变硬件设计 |
| `docs/debug_reports/13_dbg_hub_clock_exact_check.md` | 新增本报告 | 仅文档 |

本轮未修改：

```text
RTL
BD
XDC
Vitis
rate controller
GTX DRP 逻辑
MMCM DRP 逻辑
AD9528
```

## 10. 本轮是否重新 build

本轮没有重新运行 synthesis / implementation / bitstream，因为当前 `impl_1` implemented design 已经通过精确查询证明：

```text
dbg_hub/clk = gt_ctrl_clk
```

此前用于生成当前 bit/LTX 的实现结果已经完成：

```text
synthesis / implementation / bitstream / write_debug_probes
```

本轮只是对现有 `impl_1` 做精确核查与报告整理。

## 11. 当前结论

当前 `impl_1` implemented design 的 debug clock 结构为：

```text
dbg_hub/clk        = gt_ctrl_clk / clk_fpga_0
ila_laser_axi_cfg = gt_ctrl_clk / clk_fpga_0
ila_laser_tx      = txusrclk2
```

因此从 implemented netlist 角度看，`dbg_hub/clk` 已经不再连接到 `gt_txusrclk2`。

当前尚未执行新的上板验证；不能声明 500M↔1000M 动态切换通过。

## 12. 后续建议

1. 在 Vivado GUI 中执行 `close_design; open_run impl_1; report_debug_core -full_path`，确认 GUI 与 batch 打开的是同一个 implemented design。
2. Program Device 时使用同源 bit/LTX：

```text
Bitstream:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit

Debug probes:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

3. 若 Hardware Manager 仍报 debug hub 检测失败，先降 JTAG 频率、只 program bit、不加载 ltx，以区分 JTAG/hw_server 问题和 debug core 问题。
4. 在 debug hub 正常识别前，不继续执行 `rate set 1000` / `rate set 500` 动态切换验证。

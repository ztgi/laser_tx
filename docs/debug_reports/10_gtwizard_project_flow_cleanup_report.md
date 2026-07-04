# GT Wizard Project Flow 接入方式收口报告

生成时间：2026-07-01  
工程目录：`D:/FPGA_Learn/laser_tx`

## 1. 本轮问题现象

Vivado GUI 打开主工程后出现 critical warning：

```text
[Project 1-863] gtwizard_0.dcp was generated for a block design or IP by an out-of-context synthesis run and should not directly be used as a source in a Vivado flow to refer to an IP source.
```

同时 GUI 常规 `synth_1` 曾失败于：

```text
[Synth 8-439] module 'gtwizard_0' not found
failed synthesizing module 'laser_gt_tx_profile0'
```

这说明此前存在两类问题：

1. `gtwizard_0.dcp` 曾被作为普通 project source 加入主工程；
2. 移除 DCP source 后，`synth_1` 没有正确读入官方 generated HDL，导致顶层实例 `u_gtwizard_0` 找不到模块定义。

## 2. 本轮采用的最终方案

本轮最终采用：

```text
GT Wizard XCI 保留
+ 官方 generated HDL 进入 synth_1 compile order
+ 顶层 laser_gt_tx_profile0 直接实例化 gtwizard_0
```

明确不采用：

```text
不使用手写 gtwizard_0_blackbox_stub.v
不手动 read_checkpoint -cell
不把 gtwizard_0.dcp 当普通 source 加入 sources_1
不恢复 generated HDL / blackbox stub / DCP / read_checkpoint 混用
```

## 3. 修改摘要

本轮只修改 Vivado project/source 接入方式和说明文档，不修改 rate controller 功能逻辑。

修改文件：

| 文件 | 修改内容 |
|---|---|
| `laser_tx.xpr` | 保留 `gtwizard_0.xci`；移除手动 `gtwizard_0.dcp` source；移除旧 `gtwizard_0` OOC child run 残留；让 `gtwizard_0.xci` 在主 `sources_1` 中驱动官方 generated HDL 进入 `synth_1` compile order |
| `scripts/build_dynamic_500m_1000m_direct.tcl` | 仅修改一条错误提示文本，去掉 `read_checkpoint -cell` 字样，避免误判为脚本仍使用该命令 |
| `scripts/run_gui_project_impl_1_bitstream_check.tcl` | 新增可重复执行的 GUI/project `impl_1` 到 bitstream 检查脚本 |
| `docs/debug_reports/07_minimal_500m_1000m_dynamic_switch_implementation_report.md` | 增加补充说明，标记旧 DCP-source 表述已被本报告取代 |
| `docs/debug_reports/10_gtwizard_project_flow_cleanup_report.md` | 新增本报告 |

## 4. 修改前问题

修改前 GT Wizard 接入方式存在历史混用痕迹：

| 项目 | 修改前状态 | 问题 |
|---|---|---|
| `gtwizard_0.xci` | 存在 | 正确，但未能单独保证 `gtwizard_0` 模块在主 `synth_1` 可见 |
| `gtwizard_0.dcp` | 曾作为普通 source 加入工程 | 触发 `[Project 1-863]` / `[Project 1-840]` critical warning |
| generated HDL | 存在于 `laser_tx.gen/sources_1/ip/gtwizard_0/` | 曾未进入 `synth_1` compile order，导致 `gtwizard_0 not found` |
| hand-written blackbox stub | 已不应存在 | 若存在会和 generated HDL / DCP 混用 |
| `read_checkpoint -cell` | 不应使用 | 若使用会进入 direct blackbox 绑定路线，不符合本轮方案 |

## 5. 修改后结构

修改后结构为：

```text
laser_tx.xpr
  sources_1
    laser_tx_board_top.v
    laser_gt_tx_profile0.v
    laser_gt_usrclk_profile0.v
    laser_gt_rate_switch_500m_1000m.v
    system_wrapper.v
    gtwizard_0.xci
      -> Vivado 展开官方 generated HDL:
         gtwizard_0.v
         gtwizard_0_gt.v
         gtwizard_0_multi_gt.v
         gtwizard_0_init.v
         gtwizard_0_cpll_railing.v
         gtwizard_0_tx_startup_fsm.v
         gtwizard_0_rx_startup_fsm.v
         gtwizard_0_sync_block.v
```

`synth_1` compile order 已确认包含官方 generated HDL：

```text
gtwizard_0_tx_startup_fsm.v
gtwizard_0_rx_startup_fsm.v
gtwizard_0_init.v
gtwizard_0_cpll_railing.v
gtwizard_0_gt.v
gtwizard_0_multi_gt.v
gtwizard_0_sync_block.v
gtwizard_0.v
```

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| GT Wizard XCI | 存在 | 保留在主工程 `sources_1` | IP 元数据和 IP XDC 仍可由 Vivado 管理 |
| GT Wizard generated HDL | 未稳定进入 `synth_1` compile order | 已进入 `synth_1` compile order | `gtwizard_0` 模块定义可被综合解析 |
| `gtwizard_0.dcp` 普通 source | 曾存在 | 已移除 | 消除 OOC DCP 被当普通 source 的 critical warning 来源 |
| 手写 blackbox stub | 不应存在 | 不存在 | 避免 blackbox/generated HDL/DCP 混用 |
| `read_checkpoint -cell` | 不应存在 | 脚本中无该命令 | 不走 direct blackbox 绑定路线 |
| GT Wizard XDC | 依赖 IP/XCI | implementation 日志确认加载 `gtwizard_0.xdc` | GT Wizard IP constraints 保留 |
| `synth_1` | 曾失败于 `gtwizard_0 not found` | `synth_design Complete!` | GUI/project synthesis 收口 |
| `impl_1` / bitstream | 未确认 | `write_bitstream Complete!` | GUI/project implementation/bitstream 收口 |

## 7. 接口与板级一致性说明

本轮未修改任何外部端口：

```text
未新增 top-level port
未删除 top-level port
未重命名 top-level port
未修改端口方向
未修改端口宽度
未修改板级 pin 约束
```

本轮仅调整 Vivado project source/IP 元数据，不改变 `laser_gt_tx_profile0` 对 `gtwizard_0` 的顶层实例化连接。

## 8. 时钟与复位说明

本轮未修改时钟/复位 RTL 或约束语义：

```text
Clock/reset behavior unchanged
```

implementation 日志中 `gt_profile0_impl_pre.tcl` 仍检查通过：

```text
GT TXOUTCLK / TXUSRCLK period verified: 64.000 ns
GT TXUSRCLK period verified: 64.000 ns
GT TXUSRCLK2 period verified: 128.000 ns
Applied asynchronous clock groups: clk_fpga_0 <-> TXOUTCLK / txusrclk / txusrclk2
```

## 9. AXI 地址与软件影响

本轮不涉及 BD address map 或 Vitis 软件接口：

```text
AXI address map unchanged
XSA / Platform / BSP dependency unchanged
```

未修改：

```text
GPIO / BRAM / GT status 地址
UDP 协议
rate controller 寄存器语义
Vitis 源码
BSP
```

## 10. GT Wizard XDC/IP constraints 加载确认

GUI/project `impl_1` 日志确认加载了 GT Wizard IP XDC：

```text
Parsing XDC File [d:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.xdc] for cell 'u_laser_gt_tx_profile0/u_gtwizard_0/inst'
Finished Parsing XDC File [d:/FPGA_Learn/laser_tx/laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.xdc] for cell 'u_laser_gt_tx_profile0/u_gtwizard_0/inst'
```

同时主工程约束也被加载：

```text
constraints/laser_tx_board_io.xdc
constraints/laser_tx_ad9528_spi.xdc
constraints/laser_tx_gt_profile0.xdc
constraints/laser_sync_pins_template.xdc
```

## 11. Validate / 生成文件 / 综合实现

执行的关键步骤：

```text
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1
wait_on_run synth_1
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
open_run impl_1
report_timing_summary
report_clock_utilization
write_debug_probes
```

结果：

```text
synth_1: synth_design Complete!
impl_1: write_bitstream Complete!
```

生成文件：

```text
bit: D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
ltx: D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_laser_tx_board_top.ltx
timing: D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_timing_summary_impl_1.rpt
clock utilization: D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_clock_utilization_impl_1.rpt
```

## 12. QoR / timing / utilization 对比

本轮主要目标是 project flow 收口，不是 QoR 优化。

| Metric | GUI/project impl_1 结果 | 说明 |
|---|---:|---|
| Setup WNS | 7.029 ns | timing pass |
| Setup TNS | 0.000 ns | 无 setup failing endpoint |
| Hold WHS | 0.049 ns | hold pass |
| Hold THS | 0.000 ns | 无 hold failing endpoint |
| Pulse width WPWS | 3.358 ns | pulse width pass |
| Pulse width TPWS | 0.000 ns | 无 pulse width failing endpoint |

timing summary 明确：

```text
All user specified timing constraints are met.
```

## 13. 功能等价性说明

Expected system behavior unchanged。

本轮没有修改：

```text
RTL 功能逻辑
rate controller 状态机
GTX DRP / MMCM DRP 功能实现
laser_tx_core
BRAM 配置格式
UDP 协议
BD 连接
XDC 约束语义
Vitis 软件
```

本轮改变的是 Vivado 工程解析 GT Wizard 的方式：从“手动 DCP source / 残留 OOC run 混用风险”收敛到“XCI 保留 + 官方 generated HDL 进入主 `synth_1` compile order”。

功能等价性结论基于工程结构检查和 Vivado synthesis/implementation 成功结果；未执行上板验证。

## 14. 修改文件列表

| File | Change |
|---|---|
| `D:/FPGA_Learn/laser_tx/laser_tx.xpr` | GT Wizard 接入方式收口：移除手动 DCP source 与旧 OOC child run；保留 XCI；让官方 generated HDL 由 XCI 展开进入 compile order |
| `D:/FPGA_Learn/laser_tx/scripts/build_dynamic_500m_1000m_direct.tcl` | 更新错误提示文本，避免误判仍使用 `read_checkpoint -cell` |
| `D:/FPGA_Learn/laser_tx/scripts/run_gui_project_impl_1_bitstream_check.tcl` | 新增 GUI/project implementation + bitstream 可重复检查脚本 |
| `D:/FPGA_Learn/laser_tx/docs/debug_reports/07_minimal_500m_1000m_dynamic_switch_implementation_report.md` | 增加补充说明，旧 DCP source 表述由本报告取代 |
| `D:/FPGA_Learn/laser_tx/docs/debug_reports/10_gtwizard_project_flow_cleanup_report.md` | 新增本轮报告 |

## 15. 当前结论

当前可以确认：

```text
gtwizard_0.xci：保留
gtwizard_0 generated HDL：已进入 synth_1 compile order
gtwizard_0.dcp：不在 sources_1 普通 source 中
gtwizard_0_blackbox_stub.v：不存在
scripts 中未使用 read_checkpoint -cell
GT Wizard gtwizard_0.xdc：implementation 中已加载
GUI/project synth_1：通过
GUI/project impl_1/write_bitstream：通过
timing：通过，WNS=7.029 ns，TNS=0.000 ns
```

当前不能声明：

```text
500M↔1000M 动态切换已上板通过
外部光口链路闭环已通过
动态 rate set 已经完成硬件验证
```

## 16. 风险与后续建议

残留风险：

1. 本轮只验证 GUI/project build flow，不包含上板动态切换验证；
2. `write_bitstream` 仍有若干 DRC warning，主要包括 debug hub 和 rate switch readback LUT pin warning，需要后续按上板风险评估；
3. 当前 bit/LTX 可用于下一步上板验证，但不能替代硬件测试结论；
4. 若后续重新导入 IP 或重建工程，需要保持本报告定义的接入方式，避免再次把 `gtwizard_0.dcp` 加回普通 source。

建议下一步：

1. 在 Vivado GUI 重新打开工程，确认不再出现 `[Project 1-863] gtwizard_0.dcp ... should not directly be used as a source`；
2. 使用本轮 GUI/project bit/LTX 做上板前一致性检查；
3. 上板验证前确认 Vitis 不自动下载旧 bit；
4. 上板时先验证 GT ready / txusrclk2 alive / rate status，再测试 `rate set 1000` 与 `rate set 500`。


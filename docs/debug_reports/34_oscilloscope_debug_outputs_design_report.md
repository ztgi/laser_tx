# J9 示波器调试输出设计报告

## 1. 本阶段目标

本阶段目标是在不改变动态切速率功能逻辑的前提下，将 4 路只读调试信号引出到板卡 J9 预留 GPIO 接口，便于使用示波器观察 rate request、TX MMCM lock、GT ready 以及 TXUSRCLK2 活动状态。

本阶段只新增观测输出，不反馈到 rate controller、GT/MMCM DRP、profile table、UDP 协议或 laser_tx_core 数据路径。

## 2. 板卡资料依据

本轮依据用户提供的板卡用户手册和原理图进行确认：

- `D:/FPGA_Learn/project_gtx/docs_platform.pdf`
- `D:/FPGA_Learn/project_gtx/docs_sch.pdf`

用户手册“3.6.4 预留 GPIO 接口”说明 J9 预留 GPIO 接口位于 PL Bank 10，采用 3.3V 电压。原理图中 Z7 HR Bank 10/J9 连接显示对应引脚属于 Bank 10，Bank 10 VCCO 为 3.3V。

本轮未再因缺少 pin map 停止；同时在工程 XDC/RTL 中只读搜索确认 AE17、AH16、AA14、AD15 未被已有功能占用。

## 3. GPIO6～GPIO9 映射

| Scope | J9 | FPGA pin | Debug signal | IO standard | Drive/Slew |
|---|---|---|---|---|---|
| CH1 | GPIO6 / pin 6 | AE17 | `dbg_scope_rate_req` | LVCMOS33 | 4 mA / SLOW |
| CH2 | GPIO7 / pin 7 | AH16 | `dbg_scope_tx_mmcm_locked` | LVCMOS33 | 4 mA / SLOW |
| CH3 | GPIO8 / pin 8 | AA14 | `dbg_scope_gt_ready` | LVCMOS33 | 4 mA / SLOW |
| CH4 | GPIO9 / pin 9 | AD15 | `dbg_scope_txusrclk2_div16` | LVCMOS33 | 4 mA / SLOW |
| GND | pin 10 | DGND | Oscilloscope ground | - | - |

GPIO9 / pin 9 与 DGND / pin 10 相邻，因此将最高频、持续翻转的 `TXUSRCLK2/16` 调试信号放在 GPIO9，便于缩短示波器探头回流路径。

## 4. 与原 GPIO1～GPIO4 的关系

本轮未修改 GPIO1～GPIO4 现有同步输出约束：

| J9 GPIO | FPGA pin | Existing signal |
|---|---|---|
| GPIO1 | AG17 | `eom_out_0` |
| GPIO2 | AB12 | `soa_gate_out_0` |
| GPIO3 | AC14 | `acq_trig_out_0` |
| GPIO4 | AD16 | `acq_gate_out_0` |

未删除或覆盖 AC13 及其它已有真实约束。

## 5. 四路信号来源

| Debug signal | RTL source | Clock domain | 说明 |
|---|---|---|---|
| `dbg_scope_rate_req` | `laser_gt_rate_switch_500m_1000m.request_event` 的展宽副本 | `gt_ctrl_clk` / `clk_fpga_0` | 真实 rate request toggle 事件，只做示波器展宽，不反馈 FSM |
| `dbg_scope_tx_mmcm_locked` | `tx_mmcm_locked_sync` | `gt_ctrl_clk` / `clk_fpga_0` | 使用同步后的 MMCM lock，不优先使用 raw lock |
| `dbg_scope_gt_ready` | `gt_ready_tx` | `txusrclk2` | 系统发送门控使用的最终 ready 输出 |
| `dbg_scope_txusrclk2_div16` | `dbg_txusrclk2_div_counter[3]` | `txusrclk2` | TXUSRCLK2 域自由运行计数器 bit[3]，输出频率为 TXUSRCLK2/16 |

## 6. request 展宽方法

原始 `request_event` 只有一个 `gt_ctrl_clk` 周期，不适合示波器稳定捕获。本轮在 `laser_gt_rate_switch_500m_1000m.v` 内新增只读展宽计数器：

```verilog
localparam [7:0] DBG_SCOPE_RATE_REQ_HOLD_CYCLES = 8'd250;
reg [7:0] dbg_scope_rate_req_count;
assign dbg_scope_rate_req = (dbg_scope_rate_req_count != 8'd0);
```

`gt_ctrl_clk` 当前为 PS FCLK / `clk_fpga_0`，频率 50 MHz，因此 250 个周期对应约：

```text
250 / 50 MHz = 5.0 us
```

该展宽信号只用于示波器观测，不参与 rate request 接收、忙态保护、状态机跳转或任何功能反馈。

## 7. TXUSRCLK2/16 实现

本轮没有将原始 `txusrclk2` 直接连接到普通 GPIO，而是在 `txusrclk2` 域新增自由运行二进制计数器，并输出 bit[3]：

```verilog
reg [7:0] dbg_txusrclk2_div_counter;
assign dbg_scope_txusrclk2_div16 = dbg_txusrclk2_div_counter[3];
```

该输出频率为 `TXUSRCLK2/16`。如果 TXUSRCLK2 在速率切换或异常状态下停止，该输出冻结属于正常观测现象。

理论输出频率示例：

| Profile | TXUSRCLK2 | `dbg_scope_txusrclk2_div16` |
|---|---:|---:|
| 500M | 7.8125 MHz | 488.28125 kHz |
| 1000M | 15.625 MHz | 976.5625 kHz |
| 1250M | 19.53125 MHz | 1.220703125 MHz |
| 2000M | 31.25 MHz | 1.953125 MHz |
| 2500M | 39.0625 MHz | 2.44140625 MHz |
| 3125M | 48.828125 MHz | 3.0517578125 MHz |
| 5000M | 78.125 MHz | 4.8828125 MHz |
| 6250M | 97.65625 MHz | 6.103515625 MHz |

上述频率为设计预期，尚未通过示波器实测。

## 8. 修改文件

| File | Change |
|---|---|
| `rtl/laser_tx_board_top.v` | 新增 4 个顶层示波器调试输出端口，并连接到 GT profile wrapper |
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 新增 4 个 debug-only 输出；连接同步 lock、最终 ready、TXUSRCLK2/16；透传 rate request 展宽输出 |
| `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | 新增 `request_event` 示波器展宽副本，不改变原 FSM 行为 |
| `constraints/laser_tx_board_io.xdc` | 为 J9 GPIO6～GPIO9 新增 AE17/AH16/AA14/AD15 LVCMOS33 约束 |
| `scripts/run_oscilloscope_debug_outputs_project_flow.tcl` | 新增可重复 project flow build/report 脚本 |

## 9. 是否修改 BD

未修改 BD。

本轮只在手写 board top / GT wrapper / rate switch debug-only port / board XDC 中引出调试输出；没有 Refresh Changed Modules，没有修改 `system.bd`，没有修改 AXI 地址、GPIO bitfield、Vitis platform、BSP 或 XSA。

## 10. report_io 与 DRC 结果

`report_io` 输出文件：

```text
D:/FPGA_Learn/laser_tx/reports/oscilloscope_debug_outputs/io_oscilloscope_debug_outputs.rpt
```

关键 IO 绑定结果：

| Signal | PACKAGE_PIN | Bank | Direction | IO Standard | Drive | Slew |
|---|---|---:|---|---|---:|---|
| `dbg_scope_rate_req` | AE17 | 10 | OUTPUT | LVCMOS33 | 4 | SLOW |
| `dbg_scope_tx_mmcm_locked` | AH16 | 10 | OUTPUT | LVCMOS33 | 4 | SLOW |
| `dbg_scope_gt_ready` | AA14 | 10 | OUTPUT | LVCMOS33 | 4 | SLOW |
| `dbg_scope_txusrclk2_div16` | AD15 | 10 | OUTPUT | LVCMOS33 | 4 | SLOW |

`report_drc` 输出文件：

```text
D:/FPGA_Learn/laser_tx/reports/oscilloscope_debug_outputs/drc_oscilloscope_debug_outputs.rpt
```

DRC 结果：

- DRC Error：0；
- UCIO-1：未出现；
- NSTD-1：未出现；
- VREF 冲突：未出现；
- 现有 Warning：`PDCN-1569` 4 条、`RTSTAT-10` 1 条，均非本次新增 J9 GPIO 约束冲突。

## 11. Timing / utilization / debug core 结果

Vivado project flow 已完成：

```text
synth_1_STATUS = synth_design Complete!
impl_1_STATUS  = write_bitstream Complete!
```

Timing summary：

```text
WNS = 7.029 ns
TNS = 0.000 ns
WHS = 0.044 ns
THS = 0.000 ns
All user specified timing constraints are met.
```

Utilization 摘要：

| Resource | Used | Utilization |
|---|---:|---:|
| Slice LUTs | 22804 | 8.22% |
| Slice Registers | 21661 | 3.90% |
| Block RAM Tile | 61 | 8.08% |
| DSPs | 0 | 0.00% |
| BUFGCTRL | 6 | 18.75% |
| MMCME2_ADV | 1 | 12.50% |
| GTXE2_COMMON | 1 | 25.00% |
| GTXE2_CHANNEL | 1 | 6.25% |

Debug core report：

```text
D:/FPGA_Learn/laser_tx/reports/oscilloscope_debug_outputs/debug_cores_oscilloscope_debug_outputs.rpt
```

报告显示 debug cores 仍包含：

- `dbg_hub`
- `ila_laser_axi_cfg`
- `ila_laser_tx`

## 12. 生成的本地 bit/LTX

主工程 impl_1 产物：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

归档复制产物：

```text
D:/FPGA_Learn/laser_tx/reports/oscilloscope_debug_outputs/artifacts/laser_tx_board_top_oscilloscope_debug_outputs.bit
D:/FPGA_Learn/laser_tx/reports/oscilloscope_debug_outputs/artifacts/laser_tx_board_top_oscilloscope_debug_outputs.ltx
```

这些 bit/LTX 为本地生成物，不纳入 Git 提交。

## 13. 示波器接线表

| Oscilloscope channel | Probe tip | Ground |
|---|---|---|
| CH1 | J9 GPIO6 / pin 6 / AE17 / `dbg_scope_rate_req` | J9 pin 10 DGND |
| CH2 | J9 GPIO7 / pin 7 / AH16 / `dbg_scope_tx_mmcm_locked` | J9 pin 10 DGND |
| CH3 | J9 GPIO8 / pin 8 / AA14 / `dbg_scope_gt_ready` | J9 pin 10 DGND |
| CH4 | J9 GPIO9 / pin 9 / AD15 / `dbg_scope_txusrclk2_div16` | J9 pin 10 DGND |

建议 CH4 优先使用短地弹簧或最短可行接地方式，因为它是四路中持续翻转频率最高的信号。

## 14. 尚未执行的 hardware test

Oscilloscope hardware validation was not run.

本轮只完成 RTL/XDC/build/report 收口，尚未在 J9 上使用示波器确认实际电平、频率、上升沿质量或切换过程波形。

## 15. 当前边界声明

本阶段只完成 J9 示波器调试输出能力，不等价于新的动态速率验证。

当前不能声明：

- 示波器实测已经通过；
- 外部同步引脚时序已经示波器验证；
- CPLL/QPLL/10G 新功能已启用；
- 任意速率或宽范围连续调速已完成；
- 外部光口质量、眼图、BER 或长期稳定性已通过。

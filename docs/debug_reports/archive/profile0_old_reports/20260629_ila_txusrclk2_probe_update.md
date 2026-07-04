# ILA TX 数据与同步信号观测增强报告

## 1. 本轮问题现象

当前上板 ILA 已证明 APPLY / ENABLE 控制链路基本跑通：

1. APPLY 后 `cfg_update_pulse_tx` 出现，`pattern_valid_tx` 置 1；
2. ENABLE 后 `engine_start_tx` 出现，`busy_tx` 短暂拉高，`phase_active_tx` / `phase_start_pulse_tx` 出现；
3. `current_state_tx` 从 `00 -> 01 -> 02`，最终 `done_tx=1`。

本轮目标不是修改 `laser_tx_core` 功能逻辑，而是补齐并确认 TX 侧 ILA 对实际输出数据和外部同步信号的观测能力。

## 2. 修改目标

本轮目标：

- 确认 `hw_ila_2` / `ila_laser_tx` 包含 `txdata[63:0]`、`valid_mask[63:0]`、`eom_out`、`soa_gate_out`、`acq_trig_out`、`acq_gate_out`；
- 保留 TX 控制/状态 debug probe，便于同屏对齐；
- 确保这些 probe 由 `txusrclk2` 域 ILA 采样，而不是 `axi_clk` / `FCLK_CLK0`；
- 重新生成同源 bitstream 和 LTX；
- 更新工程报告并创建截图保存目录。

## 3. 修改内容

只修改 Vivado BD / 生成文件 / 报告文档，不修改 RTL 功能逻辑。

关键修改：

```text
ila_laser_tx/clk:
  修改前：processing_system7_0/FCLK_CLK0
  修改后：laser_tx_core_0/txusrclk2
```

执行脚本：

```bat
D:\Vivado\2022.2\bin\vivado.bat -mode batch -source D:\FPGA_Learn\laser_tx\scripts\bd_add_laser_ila.tcl
D:\Vivado\2022.2\bin\vivado.bat -mode batch -source D:\FPGA_Learn\laser_tx\scripts\run_build_bitstream.tcl
```

## 4. ILA probe 列表

`hw_ila_2` / `ila_laser_tx` 中确认存在以下必须 probe：

```text
laser_tx_core_0_txdata[63:0]
laser_tx_core_0_valid_mask[63:0]
laser_tx_core_0_eom_out
laser_tx_core_0_soa_gate_out
laser_tx_core_0_acq_trig_out
laser_tx_core_0_acq_gate_out
```

同时保留以下控制/状态 probe：

```text
laser_tx_core_0_dbg_cfg_update_pulse_tx
laser_tx_core_0_dbg_pattern_valid_tx
laser_tx_core_0_dbg_engine_start_tx
laser_tx_core_0_dbg_busy_tx
laser_tx_core_0_dbg_done_tx
laser_tx_core_0_dbg_phase_active_tx
laser_tx_core_0_dbg_phase_start_pulse_tx
laser_tx_core_0_dbg_phase_offset_tx[7:0]
laser_tx_core_0_dbg_current_state_tx[7:0]
```

## 5. 时钟域说明

生成后的 `system.v` 中确认：

```verilog
system_ila_laser_tx_0 ila_laser_tx
     (.clk(txusrclk2_1),
      .probe0(laser_tx_core_0_txdata),
      .probe1(laser_tx_core_0_valid_mask),
      ...);

assign txusrclk2_1 = txusrclk2;
...
.txusrclk2(txusrclk2_1)
```

因此：

```text
ila_laser_tx 采样时钟 = txusrclk2
laser_tx_core 工作时钟 = txusrclk2
TX ILA 不是 axi_clk / FCLK_CLK0 域 ILA
```

`ila_laser_axi_cfg` 仍保持 `processing_system7_0/FCLK_CLK0` / `axi_clk` 域，用于配置侧观察。

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| TX ILA 时钟 | `processing_system7_0/FCLK_CLK0` | `laser_tx_core_0/txusrclk2` | TX 数据/同步信号按真实 TX 域采样 |
| TX ILA probe | 已包含数据、mask、同步与状态信号 | 保持不变并确认完整 | 未新增功能逻辑 |
| AXI/config ILA | FCLK/axi_clk 域 | 不变 | 配置侧观察不受影响 |
| RTL 功能逻辑 | 原设计 | 未修改 | 发送功能语义不变 |
| BD 外部端口 | 原端口 | 未新增/删除/重命名 | 板级接口不变 |
| AXI 地址 | 原地址 | 未修改 | 软件地址映射不变 |
| bit/LTX | 旧实现 | 已重新生成同源 bit/LTX | Hardware Manager 必须使用新 pair |

## 7. 构建与验证记录

### 7.1 Vivado BD / output products / wrapper

已执行：

```text
validate_bd_design
save_bd_design
generate_target all
make_wrapper
```

结果：

```text
BD validation completed with warnings only.
Output products regenerated.
Wrapper checked and retained under board top build.
```

主要已知 warning：

- SPI EMIO SSIN 提示；
- BRAM address width mismatch 提示；
- SmartConnect / unconnected optional ports；
- debug hub 相关 bitgen DRC warning。

本轮未发现 Vivado ERROR。

### 7.2 Synthesis / Implementation / bitstream

已执行 clean rebuild：

```text
synth_1 complete
impl_1 complete through write_bitstream
```

生成文件：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
D:/FPGA_Learn/laser_tx/laser_tx.xsa
```

文件时间：

```text
laser_tx_board_top.bit: 2026-06-29 16:34:12
laser_tx_board_top.ltx: 2026-06-29 16:34:12
laser_tx.xsa:           2026-06-29 16:34:24
```

Timing summary：

```text
WNS = 7.029 ns
TNS = 0.000 ns
TNS failing endpoints = 0
WHS = 0.044 ns
THS = 0.000 ns
All user specified timing constraints are met.
```

Utilization placed 摘要：

```text
Slice LUTs      = 18818 / 277400 = 6.78%
Slice Registers = 16616 / 554800 = 2.99%
Slice           = 7050  / 69350  = 10.17%
```

## 8. 报告与图片更新

已更新工程报告：

```text
D:/FPGA_Learn/laser_tx/reports/board_validation/profile0_final/laser_tx_profile0_effective_tx_ila_closure_report.md
```

新增章节：

```text
ILA 上板验证阶段记录：APPLY 与 ENABLE 控制链路
```

已创建图片目录：

```text
D:/FPGA_Learn/laser_tx/docs/images/
```

已检测到 / 约定使用以下 Vivado GUI 截图路径：

```text
D:/FPGA_Learn/laser_tx/docs/images/phase1_static_ila/500m_profile0/ila_apply_config_update.png
D:/FPGA_Learn/laser_tx/docs/images/phase1_static_ila/500m_profile0/ila_enable_engine_start.png
D:/FPGA_Learn/laser_tx/docs/images/phase1_static_ila/500m_profile0/ila_apply_with_txdata_validmask.png
D:/FPGA_Learn/laser_tx/docs/images/phase1_static_ila/500m_profile0/ila_enable_txdata_validmask.png
```

如后续重新抓取波形，可覆盖同名 PNG 文件，报告引用路径无需修改。

## 9. 上板验证记录

本轮未执行新的 hardware capture。

```text
Hardware test was not run after the new bit/LTX generation.
```

不能把“bit/LTX 生成通过”写成“TX 数据与同步输出已上板通过”。下一步需要用户用新 bit/LTX 下载板卡后重新抓 ILA。

## 10. 当前分层结论

| 层级 | 当前结论 |
|---|---|
| PS -> GPIO -> PL APPLY 控制链路 | 用户已有 ILA 证据表明基本跑通 |
| ENABLE -> TX engine 启动链路 | 用户已有 ILA 证据表明基本跑通 |
| TX ILA probe 完整性 | 已确认包含数据、mask、同步输出和状态信号 |
| TX ILA 采样时钟 | 已改为 `txusrclk2` |
| bit/LTX 同源生成 | 已完成 |
| `txdata/valid_mask` 新 ILA 上板抓取 | 已完成初步观察：ENABLE 后 `txdata` 非零，`valid_mask=0xffffffffffffffff` |
| `eom/soa/acq` 新 ILA 上板抓取 | 本轮截图暂未观察到有效变化，待 GAP 或同步门控测试 |
| 外部同步引脚示波器验证 | 未执行 |

## 11. ILA 触发建议

APPLY 阶段：

```text
Trigger: dbg_cfg_update_pulse_tx == 1
Observe:
  dbg_cfg_update_pulse_tx
  dbg_pattern_valid_tx
  dbg_current_state_tx
  dbg_phase_offset_tx
```

ENABLE 阶段：

```text
Trigger: dbg_engine_start_tx == 1
Alternative: dbg_phase_start_pulse_tx == 1
Observe:
  txdata[63:0]
  valid_mask[63:0]
  eom_out
  soa_gate_out
  acq_trig_out
  acq_gate_out
  busy_tx
  done_tx
  phase_active_tx
  current_state_tx
```

## 12. 风险说明

1. 本轮改动了 BD ILA 时钟连接，因此必须使用新生成的 `laser_tx_board_top.bit` 和 `laser_tx_board_top.ltx`，不能混用旧 LTX。
2. 新 XSA 已由构建脚本导出，但本轮不涉及 Vitis 软件重建；若后续 Vitis platform 需要同步硬件文件，应基于新 XSA 重建。
3. TX ILA 改接 `txusrclk2` 后，debug hub / ILA 发现依赖 GT TX user clock 正常运行；上板时需确保 GT Profile 0 clocking ready。
4. 本轮不声明外部同步引脚电气波形已通过，因为未用示波器实测。

## 13. 硬件接口一致性说明

```text
未修改 laser_tx_core 功能逻辑
未修改 txdata / valid_mask 生成逻辑
未修改 PRBS / direct pattern 逻辑
未修改 GPIO / BRAM / GT status 地址映射
未修改外部同步引脚定义
未做 GTX 动态改速率
未改变固定 Profile 0 发送链路业务语义
```
如后续重新抓取波形，可覆盖同名 PNG 文件，报告引用路径无需修改。

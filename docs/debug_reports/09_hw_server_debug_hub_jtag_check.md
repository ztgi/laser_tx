# Hardware Manager / JTAG / debug hub 排查报告

## 1. 本轮问题现象

Vivado Hardware Manager 上板调试时报错：

```text
Reading intermittently wrong data from core. Try slower target speed.
is not a valid CseXsdb Slave core.
hw_server failed during internal command.
The debug hub core was not detected.
```

本轮只排查 Hardware Manager / JTAG / debug core，不修改 RTL、BD、XDC、Vitis、rate controller，也不继续执行 `rate set 500/1000`。

## 2. 当前检查结论

通过打开当前 GUI/project flow 的 `impl_1` implemented design 检查：

```tcl
open_run impl_1
get_debug_cores
get_cells -hier -filter {NAME =~ "*ila*"}
get_cells -hier -filter {NAME =~ "*dbg_hub*"}
```

结果显示当前 implemented design 内包含 debug cores：

```text
DEBUG_CORE_COUNT=3
DEBUG_CORE=dbg_hub
DEBUG_CORE=u_system_wrapper/system_i/ila_laser_axi_cfg
DEBUG_CORE=u_system_wrapper/system_i/ila_laser_tx
```

因此，当前不是“impl_1 bit 中完全没有 ILA/debug hub”的问题。

## 3. debug hub 时钟检查

`report_debug_core` 显示：

```text
dbg_hub/clk = gt_txusrclk2
```

这意味着当前 debug hub 仍依赖 GT TX user clock。如果 `gt_txusrclk2` 在上板时未稳定、GT/MMCM reset/lock 状态异常，或者 JTAG 读写不稳定，Hardware Manager 可能出现 debug hub 检测失败、waveform upload 失败或 Xicom/XSDB 内部读数错误。

本轮不修改 debug hub 时钟，只把它作为当前排查结论记录。后续若 JTAG 降速和 bit-only program 仍无法稳定识别 debug hub，需要单独安排一次硬件 debug 结构修复，使 `dbg_hub/clk` 使用稳定 `gt_ctrl_clk / PS FCLK`。

## 4. 本轮执行的 Vivado 检查与导出

执行命令：

```powershell
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source scripts\check_impl1_debug_cores_and_export_ltx.tcl -notrace"
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source scripts\check_impl1_debug_cores_summary.tcl -notrace"
```

因为 `get_debug_cores` 非空，已从同一个 `impl_1` 重新导出 debug probes：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

同时将当前 `impl_1` bit 同步到 dynamic artifacts 目录，避免出现旧 bit 与新 LTX 混用：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
```

## 5. 当前 bit / LTX 文件记录

| 文件 | Size | LastWriteTime | SHA256 |
|---|---:|---|---|
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit` | 17416462 | 2026-07-01 15:43:44 | `232215346DE7394A59185E526EA8308058EFE789A279832AFDE11D8DD4575FF5` |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx` | 76260 | 2026-07-01 16:20:01 | `49FB1D1E7ABFCE8C93845D7BF623397207006CCEA0B441703456AD4E7A1F9321` |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 17416462 | 2026-07-01 15:43:44 | `232215346DE7394A59185E526EA8308058EFE789A279832AFDE11D8DD4575FF5` |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 76260 | 2026-07-01 16:20:01 | `49FB1D1E7ABFCE8C93845D7BF623397207006CCEA0B441703456AD4E7A1F9321` |

推荐上板使用 artifacts 目录中的同源文件：

```text
Bitstream:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit

Debug probes:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

## 6. 推荐上板排查顺序

### 6.1 先只 Program bit，不加载 LTX

目的：先确认 JTAG 下载链路是否稳定，不让 LTX/debug hub 识别过程混入判断。

操作：

```text
Open Hardware Manager
Open Target
Program Device
Bitstream file 只选择 dynamic bit
Debug probes file 留空或不选择
Program
```

如果只 Program bit 都失败，问题优先看 JTAG/hw_server/板卡供电/下载器/USB 线，不应继续分析 LTX 或 UDP。

### 6.2 JTAG 降速

在 Vivado Tcl Console 中执行：

```tcl
set_property PARAM.FREQUENCY 3000000 [current_hw_target]
```

如果仍然出现间歇性读错或 debug hub 检测失败，再降到：

```tcl
set_property PARAM.FREQUENCY 1000000 [current_hw_target]
```

然后重新 Program Device。

### 6.3 bit-only 成功后再加载同源 LTX

确认 bit-only program 成功后，再使用同一 implemented design 导出的 LTX：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

如果此时仍报 debug hub not detected，需要重点确认：

```text
1. JTAG speed 是否已经降到 3 MHz 或 1 MHz；
2. hw_server/cs_server 是否需要重启；
3. 板卡是否需要断电重上电；
4. USB/JTAG 线、USB 口、Hub 是否不稳定；
5. 当前 dbg_hub/clk 依赖 gt_txusrclk2，GT/MMCM/txusrclk2 是否稳定。
```

## 7. 如果 bit-only program 也失败

建议按顺序执行：

```text
1. 关闭 Vivado Hardware Manager；
2. 结束或重启 hw_server / cs_server；
3. 板卡断电重上电；
4. 更换 USB/JTAG 线；
5. 避免 USB Hub，直连 PC；
6. 降低 JTAG 频率到 3 MHz，必要时 1 MHz；
7. 重新 Open Target；
8. 只 Program bit，不加载 LTX。
```

## 8. 当前分层结论

| 层级 | 当前结论 |
|---|---|
| UDP 通信 | 用户已反馈 `PING -> OK PONG`，说明 UDP 基础链路可用 |
| rate status | 用户已反馈可读到 `mode=dynamic_500m_1000m current_rate=500 rate_state=RATE_IDLE` |
| impl_1 debug cores | 已确认存在 `dbg_hub`、`ila_laser_axi_cfg`、`ila_laser_tx` |
| LTX 导出 | 已从同一个 `impl_1` 重新导出 |
| artifacts bit/LTX 配对 | 已同步为当前 `impl_1` bit + 当前 `impl_1` LTX |
| Hardware Manager debug hub | 当前仍需用户按 bit-only、JTAG 降速、同源 LTX 顺序上板确认 |
| 动态 rate set | 本轮未执行，不能声明动态切换通过 |

## 9. 硬件接口一致性说明

本轮未修改：

```text
RTL
BD
XDC
Vitis
BSP
rate controller
GTX DRP / MMCM DRP 逻辑
AD9528
GPIO / BRAM / GT status 地址
```

本轮只做：

```text
impl_1 debug core 结构检查；
从 impl_1 重新导出 LTX；
同步 artifacts 目录中的 dynamic bit，保证 bit/LTX 来自同一 implemented design；
生成排查脚本与调试报告。
```

## 10. 风险与后续建议

1. 当前 `dbg_hub/clk = gt_txusrclk2`。如果 GT/MMCM/txusrclk2 不稳定，Hardware Manager 可能无法可靠识别 debug hub。这是当前 debug 结构风险。
2. 在 debug hub 未稳定识别前，不建议继续执行 `rate set 1000` 或 `rate set 500`。
3. 如果 JTAG 降速、bit-only program、同源 LTX 加载后仍失败，应先修复 debug hub 时钟结构，而不是继续扩大动态速率功能。
4. 本轮未执行硬件上板验证；Hardware test was not run by Codex。当前结论基于 implemented design inspection、Vivado debug report 和本地文件检查。


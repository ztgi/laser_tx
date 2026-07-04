# 500M↔1000M 最小真实动态切换实现与 Vivado build 收口报告

生成时间：2026-06-30  
工程目录：`D:/FPGA_Learn/laser_tx`

> 2026-07-01 补充说明：本报告早期版本中关于 `gtwizard_0_synth_1/gtwizard_0.dcp` “保留在工程源中”的表述已被后续 GUI/project flow 收口修正取代。当前主工程采用 `gtwizard_0.xci` 保留、官方 generated HDL 进入 `synth_1` compile order、`gtwizard_0.dcp` 不作为普通 source、无手写 blackbox stub、无手动 `read_checkpoint -cell` 的方式。详见 `docs/debug_reports/10_gtwizard_project_flow_cleanup_report.md`。

## 1. 本轮目标与边界

本轮目标是把当前 `dynamic_500m_1000m` Vivado build 收口到稳定生成 bit/LTX，先不继续扩大功能。

当前阶段仍属于：

```text
500M↔1000M 最小真实动态切换实现
```

但本轮实际收口重点是：

```text
1. 固定 GT Wizard 接入方式；
2. 避免 generated HDL / blackbox stub / OOC DCP / read_checkpoint -cell 混用；
3. 重新生成 dynamic_500m_1000m bit/LTX；
4. 明确 timing、debug hub clock、bit/LTX 路径和未上板状态。
```

本轮未做：

```text
未新增其它速率；
未接 AD9528；
未做 QPLL/CPLL 泛化；
未修改未确认的 GT DRP 字段；
未扩大 UDP 协议；
未重写 rate controller；
未做上板验证；
未声明 500M↔1000M 动态切换已经通过硬件验证。
```

## 2. 状态恢复记录

按用户要求先执行：

```powershell
git status --short
git diff --stat
```

实际结果：

```text
git 命令在当前 Windows PowerShell 环境中不可用：
git : 无法将“git”项识别为 cmdlet、函数、脚本文件或可运行程序的名称。
```

因此本轮无法通过 `git status` / `git diff` 生成变更清单。后续文件变更依据为本轮命令输出、Vivado 日志、工程文件检查和人工列举。

## 3. 当前最新第一条 ERROR

最终一次 dynamic build 日志路径：

```text
D:/FPGA_Learn/laser_tx/vivado.log
```

最终一次 build 结果：

```text
无 ERROR；
write_bitstream completed successfully；
write_debug_probes completed；
bit/LTX 已生成。
```

在 build 方式清理前，最新阻塞类问题曾是：

```text
ERROR: [Vivado 12-12243] Command is only supported on a black-box instance.
Cell u_laser_gt_tx_profile0/u_gtwizard_0 is not a black-box.
```

原因是工程已经把 `gtwizard_0` 作为 Project/IP 源解析，脚本又尝试 `read_checkpoint -cell` 绑定 OOC DCP，导致目标不再是 blackbox。

该问题已经通过选择单一 build 方案解决。

## 4. 最终采用的 GT Wizard 接入方式

最终采用：

```text
方案 A：Project/IP/OOC DCP 方式
```

最终规则：

```text
1. Vivado 工程按 IP / Project 文件集管理 `gtwizard_0`；
2. `gtwizard_0.xci` 保留在 IP 文件集；
3. `gtwizard_0_synth_1/gtwizard_0.dcp` 保留在工程源中，由工程/IP 管理；
4. 不手动 include `gtwizard_0_blackbox_stub.v`；
5. 不手动 `read_checkpoint -cell`；
6. dynamic build 脚本如果发现 `u_laser_gt_tx_profile0/u_gtwizard_0` 仍是 blackbox，会直接报错，而不是兜底混用方案 B。
```

当前工程检查结果：

```text
laser_tx.xpr 中保留：
- laser_tx.runs/gtwizard_0_synth_1/gtwizard_0.dcp
- laser_tx.srcs/sources_1/ip/gtwizard_0/gtwizard_0.xci

laser_tx.xpr 中不再包含：
- gtwizard_0_blackbox_stub.v

磁盘上也已删除：
- laser_tx.srcs/sources_1/new/gtwizard_0_blackbox_stub.v

dynamic build 脚本不再执行：
- read_checkpoint -cell u_laser_gt_tx_profile0/u_gtwizard_0 ...
```

说明：Vivado 日志中仍可见：

```text
CRITICAL WARNING: [Synth 8-9873] overwriting previous definition of module 'gtwizard_0'
```

该 warning 的 “previous definition” 来自 Vivado 在 `.Xil/.../realtime/gtwizard_0_stub.v` 生成的临时 stub，随后由工程 IP 生成的 `laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.v` 覆盖。当前不再包含用户手写 blackbox stub，也不再手动 `read_checkpoint -cell`。因此这不再是 A/B 手工混用。

## 5. 本轮修改内容

### 5.1 RTL / Verilog

| 文件 | 修改内容 | 目的 |
| --- | --- | --- |
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 删除末尾对 `gtwizard_0_blackbox_stub.v` 的手动 include | 选择方案 A，避免 blackbox stub 与工程 IP 重复定义 |
| `laser_tx.srcs/sources_1/new/gtwizard_0_blackbox_stub.v` | 删除临时 blackbox stub 文件 | 避免后续误加入工程导致 GT Wizard 接入方式再次混用 |

本轮未修改 `laser_tx_core` 功能逻辑。

### 5.2 Vivado / XDC / build 脚本

| 文件 | 修改内容 | 目的 |
| --- | --- | --- |
| `scripts/build_dynamic_500m_1000m_direct.tcl` | 输出目录改为 `reports/dynamic_rate_500m_1000m/artifacts/` | 固定 dynamic build 产物路径 |
| `scripts/build_dynamic_500m_1000m_direct.tcl` | 删除手动 `read_checkpoint -cell` 路线；若 GT cell 仍为 blackbox 则报错 | 保持方案 A，不再混用方案 B |
| `scripts/build_dynamic_500m_1000m_direct.tcl` | 在 synthesis 后强制 `dbg_hub/clk` 连接 `gt_ctrl_clk`，并设置 `C_CLK_INPUT_FREQ_HZ=50000000` | debug hub 不再依赖 `txusrclk2` |
| `constraints/laser_tx_gt_profile0.xdc` | 增加 `GTXE2_CHANNEL_X0Y8` 显式 LOC；移除 XDC 不支持的 Tcl `if` 语句 | 修复 GT channel LOC DRC，避免 XDC 解析 warning |

### 5.3 Vitis / BSP / 软件

本轮 build 方式收口没有继续修改 Vitis 源码、BSP、platform 或 XSA。

注意：前序阶段已存在 Vitis `rate set 500/1000` 相关代码修改，但本轮没有重新 clean/build Vitis app，因此软件 ELF 与上板运行状态不在本轮结论范围内。

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| GT Wizard 接入方式 | generated HDL、blackbox stub、OOC DCP、`read_checkpoint -cell` 存在混用风险 | 方案 A：Project/IP/OOC DCP 管理；无手写 stub；无手动 `read_checkpoint -cell` | build 路径收敛 |
| `gtwizard_0_blackbox_stub.v` | 工程文件集中曾存在，RTL 末尾曾 include | 已从工程移除，磁盘文件删除，RTL include 删除 | 避免重复定义 |
| `read_checkpoint -cell` | direct 脚本曾按 blackbox 兜底绑定 DCP | 已删除；若 GT 仍 blackbox 则直接报错 | 避免黑盒/非黑盒状态歧义 |
| GTXE2_CHANNEL LOC | 直接 DCP/生成源路径下可能缺 GT primitive LOC | `GTXE2_CHANNEL_X0Y8` 显式约束 | 修复 bitstream 前 DRC |
| MMCM `CLKIN1_PERIOD` | Vivado 曾将输入频率识别异常，触发 `MMCM_adv_ClkFrequency_clkin1` | `laser_gt_usrclk_profile0.v` 中 `.CLKIN1_PERIOD(64.000)` | 修复 MMCM 输入周期 DRC |
| debug hub clock | 曾被自动接到 `gt_txusrclk2` | build 脚本强制接 `gt_ctrl_clk` | bring-up debug 不依赖 GT/MMCM lock |
| 输出目录 | `reports/dynamic_rate_500m_1000m/` | `reports/dynamic_rate_500m_1000m/artifacts/` | 产物归档更清晰 |
| 上板验证 | 未执行 | 未执行 | 不能声明动态切换通过 |

## 7. RTL 结构说明

前序阶段已经实现的最小动态切换 RTL 结构如下，本轮未扩大功能：

```text
laser_gt_rate_switch_500m_1000m
  - 工作时钟：ctrl_clk / gt_ctrl_clk / AXI FCLK 域；
  - 仅支持 RATE_ID_500M 和 RATE_ID_1000M；
  - 通过 GPIO 控制位触发请求；
  - 切换前检查 busy/done；
  - assert GT TX reset / MMCM reset；
  - 写 GTX TXOUT_DIV DRP；
  - 写 TX user clock MMCM DRP；
  - release reset；
  - 等待 cplllock / tx_mmcm_locked / txresetdone / gt_ready；
  - 检查 txusrclk2_alive 与 txusrclk2_freq_counter 窗口；
  - 成功后更新 current_rate；
  - 失败后进入 RATE_ERROR 并输出 error_code。
```

状态机包含：

```text
RATE_IDLE
RATE_REQUEST
RATE_VALIDATE
RATE_QUIESCE_TX
RATE_ASSERT_RESET
RATE_PROGRAM_GT_DRP
RATE_PROGRAM_MMCM_DRP
RATE_RELEASE_RESET
RATE_WAIT_LOCK
RATE_VERIFY_RATE
RATE_DONE
RATE_ERROR
```

本轮没有修改 `laser_tx_core` 的 pattern / gap / PRBS / direct 数据路径，没有修改 BRAM 配置格式。

## 8. 硬件接口一致性说明

本轮保持以下接口不变：

```text
未修改外部同步输出端口；
未修改 GT TXDATA 外部宽度；
未修改 `laser_tx_core` 数据路径宽度；
未修改 BRAM 配置格式；
未修改 AXI GPIO 基地址；
未修改 BRAM 基地址；
未修改 GT status GPIO 基地址；
未修改 AD9528；
未新增其它 GT profile；
未新增其它速率。
```

本轮涉及的硬件可见变化：

```text
GT status word 中前序阶段已加入 rate_state / error_code / current_rate_id 等状态位；
GPIO control word 中前序阶段已使用 bit[15] rate request toggle 与 bit[14:13] target rate id；
dynamic build 脚本强制 debug hub clock 使用 gt_ctrl_clk。
```

XSA / Platform / BSP：

```text
本轮未导出新 XSA；
本轮未重新生成 Vitis platform；
本轮未重新生成 BSP；
本轮未重新 build Vitis ELF。
```

## 9. XDC / clock / reset 说明

### 9.1 GTXE2_CHANNEL LOC

约束文件：

```text
D:/FPGA_Learn/laser_tx/constraints/laser_tx_gt_profile0.xdc
```

约束内容：

```tcl
set_property LOC GTXE2_CHANNEL_X0Y8 [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL && NAME =~ *u_laser_gt_tx_profile0*}]
```

目的：

```text
直接 build / 工程 IP 管理组合下，确保 GTXE2_CHANNEL primitive 位置固定到当前已验证单光口 lane。
```

### 9.2 MMCM CLKIN1_PERIOD

文件：

```text
D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile0.v
```

参数：

```verilog
.CLKIN1_PERIOD (64.000)
```

目的：

```text
明确 500M Profile0 下 GT TXOUTCLK 输入 TX user clock MMCM 的周期为 64 ns，避免 Vivado DRC 将 MMCM 输入频率识别为异常值。
```

### 9.3 debug hub clock

最终 debug report 证明：

```text
dbg_hub/clk = gt_ctrl_clk
C_CLK_INPUT_FREQ_HZ = 50000000
```

报告路径：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/debug_cores_dynamic_500m_1000m.rpt
```

相关摘录：

```text
Debug Core "dbg_hub":
clk -> gt_ctrl_clk
C_CLK_INPUT_FREQ_HZ = 50000000
```

因此当前 dynamic build 的 debug hub 不再依赖 `txusrclk2`。

## 10. GTX / MMCM DRP 连接检查

基于代码结构检查：

```text
GTX DRP:
- gt0_drpaddr_in  <= gt_drpaddr
- gt0_drpclk_in   <= ctrl_clk
- gt0_drpdi_in    <= gt_drpdi
- gt0_drpdo_out   => gt_drpdo
- gt0_drpen_in    <= gt_drpen
- gt0_drprdy_out  => gt_drprdy
- gt0_drpwe_in    <= gt_drpwe

MMCM DRP:
- DADDR <= mmcm_daddr_in
- DCLK  <= mmcm_dclk_in
- DEN   <= mmcm_den_in
- DI    <= mmcm_di_in
- DO    => mmcm_do_out
- DRDY  => mmcm_drdy_out
- DWE   <= mmcm_dwe_in
```

结论：

```text
GTX DRP 端口已连接到 rate switch controller；
MMCM DRP 端口已连接到 rate switch controller；
该结论基于 RTL 结构检查和综合实现通过，不等于上板 readback/切换验证通过。
```

## 11. ILA / debug probe 列表

本次 dynamic build 中实现的 debug cores：

```text
dbg_hub
ila_laser_axi_cfg
ila_laser_tx
```

`dbg_hub`：

```text
clk = gt_ctrl_clk
```

`ila_laser_axi_cfg`：

```text
clk = gt_ctrl_clk
probe0 = axi_gpio_0_gpio_io_o[31:0]
probe1 = laser_tx_core_0_gpio_status[31:0]
probe2 = laser_tx_core_0_dbg_bram_en
probe3 = laser_tx_core_0_dbg_bram_addr[31:0]
probe4 = laser_tx_core_0_dbg_bram_dout[31:0]
```

`ila_laser_tx`：

```text
clk = txusrclk2
probe0  = laser_tx_core_0_txdata[63:0]
probe1  = laser_tx_core_0_valid_mask[63:0]
probe2  = laser_tx_core_0_eom_out
probe3  = laser_tx_core_0_soa_gate_out
probe4  = laser_tx_core_0_acq_trig_out
probe5  = laser_tx_core_0_acq_gate_out
probe6  = laser_tx_core_0_dbg_busy_tx
probe7  = laser_tx_core_0_dbg_done_tx
probe8  = laser_tx_core_0_dbg_phase_active_tx
probe9  = laser_tx_core_0_dbg_phase_start_pulse_tx
probe10 = laser_tx_core_0_dbg_phase_offset_tx[7:0]
probe11 = laser_tx_core_0_dbg_current_state_tx[7:0]
probe12 = laser_tx_core_0_dbg_cfg_update_pulse_tx
probe13 = laser_tx_core_0_dbg_pattern_valid_tx
probe14 = laser_tx_core_0_dbg_engine_start_tx
```

rate controller 的详细 `rate_state / target_rate / current_rate / error_code` 目前主要通过 `gt_status_out` 字段和 mark_debug 保留信号观察。当前 dynamic build 未新增独立 AXI/FCLK rate ILA core；若上板调试中需要更细粒度内部状态，建议下一轮只增 ILA probe，不扩大速率功能。

## 12. Vivado build 验证记录

执行命令：

```bat
call "D:\Vitis\2022.2\settings64.bat"
cd /d D:\FPGA_Learn\laser_tx
vivado -mode batch -source scripts\build_dynamic_500m_1000m_direct.tcl
```

结果：

```text
synth_design：通过
opt_design：通过
place_design：通过
phys_opt_design：通过
route_design：通过
report_timing_summary：已生成
report_clocks：已生成
report_utilization：已生成
report_debug_core：已生成
write_bitstream：通过
write_debug_probes：通过
```

bit/LTX：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

主要报告：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/timing_summary_dynamic_500m_1000m.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/clocks_dynamic_500m_1000m.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/debug_cores_dynamic_500m_1000m.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/utilization_dynamic_500m_1000m.rpt
```

## 13. Timing / QoR 结果

`timing_summary_dynamic_500m_1000m.rpt` 摘要：

| Metric | Result |
| --- | ---: |
| Setup WNS | 7.029 ns |
| Setup TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| Hold WHS | 0.055 ns |
| Hold THS | 0.000 ns |
| Hold failing endpoints | 0 |
| Timing summary | All user specified timing constraints are met |

注意：

```text
Vivado timing report 仍提示存在 set_bus_skew constraint，建议后续上板前补跑 report_bus_skew 作为补充检查。
```

## 14. 当前 warning 说明

最终 build 无 ERROR，但仍有若干 warning / critical warning：

### 14.1 OOC DCP 作为工程源的 Vivado critical warning

```text
CRITICAL WARNING: [Project 1-863]
The design checkpoint file .../gtwizard_0.dcp was generated for ... OOC synthesis run ...
```

解释：

```text
当前采用方案 A，保留工程/IP 管理的 `gtwizard_0.xci` 与 OOC DCP。该 warning 来自 Vivado 对 DCP 源使用方式的通用提醒。当前不再手动 `read_checkpoint -cell`，也不再使用手写 blackbox stub。
```

### 14.2 Vivado 临时 stub 与 IP 生成 HDL 的重复定义 warning

```text
CRITICAL WARNING: [Synth 8-9873] overwriting previous definition of module 'gtwizard_0'
```

解释：

```text
previous definition 来自 `.Xil/.../realtime/gtwizard_0_stub.v`；
最终综合使用工程 IP 生成的 `laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.v`。
本轮已删除用户手写 `gtwizard_0_blackbox_stub.v`，因此这不是手写 stub 与 DCP 的混用。
```

### 14.3 DRC PDCN-1569 / RTSTAT-10 warning

```text
write_bitstream 前 DRC 有 PDCN-1569 和 RTSTAT-10 warning；
DRC finished with 0 Errors；
bitgen completed successfully。
```

这些 warning 当前不阻塞 bitstream，但建议后续 signoff 时继续审查。

## 15. Vitis / XSA / BSP 影响

本轮没有：

```text
导出 XSA；
重建 platform；
重建 BSP；
clean/build bringup.elf；
运行 UDP rate set 命令。
```

因此：

```text
Vitis build was not run in this build-method closure round.
Hardware test was not run.
```

前序 Vitis 源码中 `rate set 500/1000` 的真实动态切换命令仍需后续用新 bit/LTX 和对应 ELF 一起上板验证。

## 16. 功能等价性说明

本轮 build 方式清理本身不改变 `laser_tx_core` 的业务功能逻辑：

```text
Direct / PRBS / gap / phase / valid_mask / txdata 生成逻辑未修改；
BRAM 配置格式未修改；
GPIO/BRAM/GT status 地址未修改；
外部同步输出端口未修改；
AD9528 未修改；
未新增速率。
```

前序动态切换 RTL 属于有意新增功能：

```text
Functional behavior changed intentionally
```

变化范围：

```text
新增 500M/1000M rate switch controller；
新增 GTX DRP / MMCM DRP 控制；
GT status 增加 rate state/error/current rate 字段；
GPIO control 增加 rate request/target rate 字段。
```

当前功能正确性结论只基于代码结构检查和 Vivado build 通过。未做板级切换验证，不能声明动态切换功能已经硬件通过。

## 17. 当前分层结论

| 层级 | 当前结论 |
| --- | --- |
| 500M Profile0 static 回退 | 未在本轮重测；未故意覆盖原 static bitstream |
| 1000M Profile1 static 回退 | 未在本轮重测；未故意覆盖原 static bitstream |
| dynamic_500m_1000m RTL 实现 | 已完成代码级实现并通过 Vivado 综合/实现/bitgen |
| GT Wizard build 方式 | 已收敛为方案 A：Project/IP/OOC DCP；无手写 stub；无手动 `read_checkpoint -cell` |
| GTXE2_CHANNEL LOC | 已约束到 `GTXE2_CHANNEL_X0Y8` |
| MMCM CLKIN1_PERIOD | 已设置为 64.000 ns |
| dbg_hub/clk | 已确认 `gt_ctrl_clk` |
| timing | 通过，WNS=7.029 ns，TNS=0 |
| bit/LTX | 已生成 |
| Vitis ELF | 本轮未 build |
| 上板动态切换 | Hardware test was not run |
| 外部光口闭环 | 未验证，不得声明通过 |

## 18. 风险与后续建议

### 18.1 残留风险

1. 当前 Vivado build 使用 Project/IP 管理的 GT Wizard 生成源与 OOC DCP，日志仍有 Vivado 对 OOC DCP 的 critical warning；虽然不再手动混用方案 B，但后续最好用常规 `launch_runs synth_1/impl_1` 或进一步整理 IP 文件集，减少 Vivado 对 DCP 源的提醒。
2. `rate_state / error_code` 目前可通过 GT status word 观察；若上板调试需要内部 DRP handshaking 的单周期细节，建议新增 AXI/FCLK ILA probe。
3. `set_bus_skew` 相关 warning 建议补跑 `report_bus_skew`。
4. 当前只完成 build，不代表 GTX DRP/MMCM DRP 的实际上板切换 sequence 已经验证。

### 18.2 下一步建议

建议下一轮只做上板验证，不扩大功能：

```text
1. 用本报告 bit/LTX Program FPGA；
2. 使用匹配的 Vitis ELF；
3. 先 READ_GT_STATUS，确认 current_rate=500、gt_ready=1；
4. 执行 rate set 1000；
5. 观察返回是否 OK RATE_SET target=1000 current_rate=1000；
6. READ_GT_STATUS 确认 rate_state / error_code / current_rate；
7. 用 ILA 观察 GPIO 控制、GT status、txusrclk2 alive/freq counter；
8. 再执行 rate set 500；
9. 完成 500->1000->500 往返后再进入多次循环验证。
```

若任何一步失败，应记录：

```text
rate_state；
rate_error_code；
GT DRP write/readback 标志；
MMCM DRP write/done 标志；
cplllock / txresetdone / tx_mmcm_locked / gt_ready；
txusrclk2_alive / txusrclk2_freq_counter。
```

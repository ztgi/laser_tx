# Phase A dry-run rate controller 工程调试报告

本报告记录动态速率切换 Phase A 的实现结果。Phase A 只实现 dry-run rate controller、500M/1000M 参数表、状态回读和 AXI/FCLK ILA 可观测信号，不实现真实 GTX/MMCM 动态切换。

## 1. 本阶段目标

本阶段目标是搭建动态速率切换的控制骨架，但不真正改变 GT/MMCM 速率。

已实现目标：

```text
rate status
rate plan 500
rate plan 1000
rate set 500
rate set 1000
非法 rate 报错
AXI/FCLK ILA 可观察 dry-run rate_state / target_rate / error_code
```

本阶段明确不做：

```text
不写 GTX DRP；
不写 MMCM DRP；
不改 TXOUT_DIV；
不改 TXUSRCLK/TXUSRCLK2；
不改真实 line rate；
不重新生成 bit/LTX。
```

## 2. 为什么 Phase B 合并进 Phase A

前期已经通过 compare/build/ILA 报告确认 500M 与 1000M static 参数。因此本轮没有再单独做“500M/1000M 静态参数表与状态寄存器”阶段，而是把它并入 Phase A：

```text
Phase A1：rate command/status/dry-run 状态机；
Phase A2：500M/1000M 参数表与只读状态寄存器；
Phase A3：AXI/FCLK ILA rate_state/target/current/error probe。
```

这样做的原因是：当前需要把已确认参数固化到 dry-run 框架中，用于后续 DRP 集成前验证控制面，而不是重新证明 static 参数。

## 3. 修改了哪些文件

| 文件 | 修改内容 |
| --- | --- |
| `laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v` | 新增 AXI/FCLK 域 dry-run rate FSM 与 mark_debug probe；不增加端口，不改变 `gpio_status` 位定义 |
| `vitis_bringup/bringup/src/laser_gpio.h` | 新增 GPIO spare bit 定义：rate id 与 request toggle |
| `vitis_bringup/bringup/src/laser_gpio.c` | 新增 `laser_gpio_rate_dryrun_request()`，通过 GPIO spare bits 触发硬件 dry-run FSM |
| `vitis_bringup/bringup/src/gt_rate_plan.h` | 扩展 500M/1000M 参数表字段：TXOUTCLK/TXUSRCLK/MMCM/window |
| `vitis_bringup/bringup/src/gt_rate_plan.c` | 收敛为 500M/1000M 两档 Phase A 参数表 |
| `vitis_bringup/bringup/src/laser_udp_server.c` | 完善 `rate status/plan/set` dry-run 命令行为 |
| `vitis_bringup/bringup/src/main.c` | 更新启动打印，明确 Phase A 为 dry-run only |
| `vitis_bringup/bringup/Debug/bringup.elf` | Vitis app 重新 build 生成 |
| `vitis_bringup/bringup/Debug/bringup.elf.size` | 更新 ELF size |
| `docs/udp_protocol.md` | 更新 UDP/rate 命令说明，删除旧的 `rate set` unsupported 口径，改为 Phase A dry-run 口径 |
| `docs/debug_reports/00_current_validation_status.md` | 更新当前分层状态，增加 Phase A dry-run 状态 |
| `docs/debug_reports/README_validation_report_reading_order.md` | 增加 Phase A dry-run 报告入口 |

## 4. 是否修改 RTL

是，修改了：

```text
laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v
```

新增结构：

```text
AXI/FCLK 域 dry-run rate FSM；
gpio_ctrl[15] 作为 rate_req_toggle_axi；
gpio_ctrl[14:13] 作为 target_rate_id；
mark_debug rate_state / target_rate / current_rate / error_code；
gt_drp_write_attempted 固定为 0；
mmcm_drp_write_attempted 固定为 0。
```

未修改：

```text
txusrclk2 数据路径；
config_loader；
BRAM 配置格式；
pattern_tx_engine 功能；
sync_signal_gen；
gpio_status 位定义；
GT Wizard；
GT/MMCM clocking。
```

## 5. 是否修改 BD

否。

```text
未修改 system.bd；
未新增 AXI 外设；
未新增 AXI 地址；
未修改 AXI GPIO IP；
未修改 HDL wrapper；
未导出 XSA。
```

本轮选择复用现有 AXI GPIO control spare bits，不需要 BD/address map 变化。

## 6. 是否修改 Vitis

是，修改了 bringup app 源码：

```text
laser_gpio.h/c
gt_rate_plan.h/c
laser_udp_server.c
main.c
```

软件行为变化：

```text
rate status 返回 dry-run 状态；
rate plan 500/1000 返回固定参数表；
rate set 500/1000 执行 dry-run 流程并触发 GPIO request toggle；
非法 rate 返回 ERROR unsupported_rate；
current_rate 不因 dry-run target 被虚假改写；
gt_drp_written/mmcm_drp_written 始终为 0。
```

## 7. 是否重新 build

是，只重新 build 了 Vitis bringup app。

执行命令：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && cd /d D:\FPGA_Learn\laser_tx\vitis_bringup\bringup\Debug && make all"
```

结果：

```text
Build passed
```

ELF size：

```text
text    = 145071
data    = 3472
bss     = 3201088
dec     = 3349631
hex     = 331c7f
file    = bringup.elf
```

## 8. 是否重新生成 bit/LTX

否。

```text
Synthesis was not run；
Implementation was not run；
Bitstream was not regenerated；
LTX was not regenerated。
```

注意：虽然 RTL 已修改并通过 `xvlog` 语法检查，但这些 RTL debug probe 需要后续 synthesis/implementation/bit/LTX 后才能在板上 ILA 中出现。

## 9. 新增 rate command 行为

### 9.1 `rate status`

返回格式：

```text
OK RATE_STATUS mode=dry-run current_static_rate=<500/1000> current_rate=<500/1000> target_rate=none|500|1000 rate_state=<STATE> dry_run=1 gt_drp_written=0 mmcm_drp_written=0 error_code=<code>
```

说明：

```text
current_static_rate / current_rate 来自编译期 LASER_STATIC_RATE_MBPS；
默认 LASER_STATIC_RATE_MBPS=1000；
如需用于 500M Profile0 app，可编译时覆盖为 500；
dry-run 不会把 current_rate 虚假更新为 target_rate。
```

### 9.2 `rate plan 500`

返回包含：

```text
target_rate=500
TXOUT_DIV=8
TXOUTCLK=15625000Hz
TXUSRCLK=15625000Hz
TXUSRCLK2=7812500Hz
requires_gt_drp=1
requires_mmcm_drp=1
executed=0
dry_run_only=1
```

### 9.3 `rate plan 1000`

返回包含：

```text
target_rate=1000
TXOUT_DIV=4
TXOUTCLK=31250000Hz
TXUSRCLK=31250000Hz
TXUSRCLK2=15625000Hz
requires_gt_drp=1
requires_mmcm_drp=1
executed=0
dry_run_only=1
```

### 9.4 `rate set 500` / `rate set 1000`

返回格式：

```text
OK RATE_SET_DRY_RUN target=<500/1000> actual_rate_unchanged=1 current_rate=<static_rate> gt_drp_written=0 mmcm_drp_written=0
```

软件 dry-run 流程：

```text
解析目标 rate；
检查是否为 500/1000；
检查 busy/done，模拟 QUIESCE_TX；
检查 gt_ready；
通过 GPIO spare bits 触发硬件 AXI dry-run FSM；
更新软件 dry-run 状态；
不改变 current_rate；
不写 GTX/MMCM DRP。
```

### 9.5 非法速率

示例：

```text
rate set 750
```

返回：

```text
ERROR unsupported_rate target=750
```

并设置软件 `error_code=1`。

## 10. 新增参数表

当前 Phase A 只保留两档参数：

| 参数 | 500M | 1000M |
| --- | ---: | ---: |
| `rate_id` | 1 | 2 |
| `line_rate_mbps` | 500 | 1000 |
| `txout_div` | 8 | 4 |
| `txoutclk_hz` | 15625000 | 31250000 |
| `txusrclk_hz` | 15625000 | 31250000 |
| `txusrclk2_hz` | 7812500 | 15625000 |
| `mmcm_clkfbout_mult_x1000` | 12188 | 20000 |
| `mmcm_divclk_divide` | 1 | 1 |
| `mmcm_clkout1_divide` | 39 | 20 |
| `mmcm_clkout0_divide` | 78 | 40 |
| `expected_txusrclk2_freq_min` | 7700000 | 15400000 |
| `expected_txusrclk2_freq_max` | 7950000 | 15900000 |

说明：

```text
该参数表只用于 plan/status/dry-run；
不得用于真实 DRP 写入；
MMCM 精确 DRP 参数仍需 Phase B 单元级确认。
```

## 11. 新增状态寄存器 / 状态变量

软件 dry-run 状态：

```text
current_static_rate_mbps
current_rate_mbps
target_rate_mbps
target_rate_id
state
error_code
dry_run_active
dry_run_done
gt_drp_written
mmcm_drp_written
```

硬件 AXI/FCLK dry-run debug 状态：

```text
dbg_axi_rate_state[7:0]
dbg_axi_target_rate_id[1:0]
dbg_axi_target_rate_mbps[15:0]
dbg_axi_current_rate_mbps[15:0]
dbg_axi_dry_run_active
dbg_axi_dry_run_done
dbg_axi_rate_error
dbg_axi_rate_error_code[7:0]
dbg_axi_gt_drp_write_attempted
dbg_axi_mmcm_drp_write_attempted
dbg_axi_tx_quiesce_req
dbg_axi_tx_idle_seen
```

## 12. ILA probe 列表

新增/建议观察的 AXI/FCLK probe：

```text
dbg_axi_rate_req_toggle
dbg_axi_rate_state[7:0]
dbg_axi_target_rate_id[1:0]
dbg_axi_target_rate_mbps[15:0]
dbg_axi_current_rate_mbps[15:0]
dbg_axi_dry_run_active
dbg_axi_dry_run_done
dbg_axi_rate_error
dbg_axi_rate_error_code[7:0]
dbg_axi_gt_drp_write_attempted
dbg_axi_mmcm_drp_write_attempted
dbg_axi_tx_quiesce_req
dbg_axi_tx_idle_seen
```

继续保留既有 AXI/FCLK 观察：

```text
cplllock_sync
txresetdone_sync
tx_mmcm_locked_sync
gt_ready_ctrl
txusrclk2_alive_axi
txusrclk2_freq_counter_axi
cfg_valid
cfg_error
cfg_update_seen
engine_start_seen
```

必须保持：

```text
dbg_hub/clk = gt_ctrl_clk / clk_fpga_0
```

禁止恢复为：

```text
dbg_hub/clk = txusrclk2
```

## 13. 如何证明没有 GTX DRP 写

RTL 侧：

```text
dbg_axi_gt_drp_write_attempted = 1'b0
```

Vitis 侧：

```text
gt_drp_written = 0
```

代码搜索显示本阶段只出现 dry-run 字段和字符串，没有新增 GTX DRP 写端口、写寄存器或 DRP transaction。

## 14. 如何证明没有 MMCM DRP 写

RTL 侧：

```text
dbg_axi_mmcm_drp_write_attempted = 1'b0
```

Vitis 侧：

```text
mmcm_drp_written = 0
```

本阶段未新增 MMCM DRP 端口、MMCM DRP 写函数或 MMCM reconfiguration sequence。

## 15. dry-run 验证步骤

上板后建议按以下顺序验证：

```text
1. 下载当前匹配 bit/LTX；
2. 运行新 bringup.elf；
3. UDP 执行 rate status；
4. UDP 执行 rate plan 500；
5. UDP 执行 rate plan 1000；
6. UDP 执行 rate set 500；
7. UDP 执行 rate status，确认 target_rate=500、current_rate 仍为 static baseline；
8. UDP 执行 rate set 1000；
9. UDP 执行 rate status，确认 target_rate=1000、current_rate 仍为 static baseline；
10. UDP 执行 rate set 750，确认 ERROR unsupported_rate；
11. AXI/FCLK ILA 观察 rate_state / target_rate / error_code；
12. 确认 gt_drp_written=0、mmcm_drp_written=0；
13. 确认 WRITE_CONFIG / SELECT_CONFIG / APPLY / ENABLE 仍保持原功能。
```

注意：当前 RTL 已修改但未重新生成 bit/LTX，因此新 ILA probe 需要后续 synthesis/implementation/bit/LTX 后才可在硬件中观察。

## 16. 当前仍未实现真实动态切换

仍未实现：

```text
GTX TXOUT_DIV DRP；
MMCM DRP；
TX reset sequence 集成控制；
500M <-> 1000M 真实动态切换；
切换失败 rollback；
外部光口动态切换验证。
```

不能写成：

```text
动态 rate set 已完成；
GTX/MMCM DRP 已完成；
真实 line rate 已改变。
```

## 17. 下一阶段建议

下一阶段建议进入 Phase B：

```text
DRP 参数确认与单元级验证；
确认 GTX TXOUT_DIV DRP address/bitfield；
确认 MMCM DRP 参数；
定义 readback/timeout/error_code；
仍不要把单元级 MMCM DRP 或 GTX DRP 写成有效速率切换。
```

进入 Phase B 前建议先完成：

```text
重新 synthesis/implementation/bit/LTX；
在 AXI/FCLK ILA 中确认 Phase A 新 probe；
上板验证 rate status/plan/set dry-run；
确认 current_rate 不被 dry-run 误改。
```

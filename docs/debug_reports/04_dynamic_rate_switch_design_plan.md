# 500M / 1000M 动态速率切换设计评审与实施计划

本文是从当前 500M Profile0 static 与 1000M Profile1 static 过渡到 `500M <-> 1000M` 动态速率切换的设计评审和实施计划。

本轮仅做设计文档，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX；不实现 GTX DRP；不实现 MMCM DRP；不把设计计划写成已经完成。

## 1. 当前已验证基础

### 1.1 500M Profile0 static 验证结论

当前 Profile0 固定 500M 阶段已完成有效发送 case 的上板 ILA 阶段性验证：

```text
Direct63
Direct127
PRBS6
PRBS7
APPLY
ENABLE
txdata / valid_mask
```

可以保留的阶段性结论：

```text
Profile0 500M 有效发送 case 已完成上板 ILA 阶段性验证；
Direct63 / Direct127 / PRBS6 / PRBS7 有效发送 case 通过；
repeat_cycles=0、insert_after>repeat_cycles、非法 prbs_order 已被拒绝；
seed=0 和 PRBS/direct_len mismatch 属于需求边界未收敛项。
```

来源主报告：

```text
docs/debug_reports/01_profile0_500m_ila_validation_summary.md
```

### 1.2 1000M Profile1 static build 结论

当前 Profile1 1000M static 已完成独立 static bitstream 路径：

```text
1000M Profile1 static bit/LTX 已生成；
timing 已通过；
TXOUT_DIV=4；
TXUSRCLK=31.25 MHz；
TXUSRCLK2=15.625 MHz；
Profile0 500M 回退路径未被覆盖。
```

bit/LTX 路径：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

Timing 结果：

```text
Setup WNS = 7.029 ns
Setup TNS = 0.000 ns
Timing constraints met
```

来源主报告：

```text
docs/debug_reports/02_profile1_1000m_static_build_and_debug_fix.md
```

### 1.3 1000M AXI/FCLK bring-up ILA 结论

1000M Profile1 static 下，AXI/FCLK bring-up ILA 已观察到：

```text
cplllock_sync = 1；
txresetdone_sync = 1；
tx_mmcm_locked_sync = 1；
gt_ready_ctrl = 1；
txusrclk2_alive_axi = 1；
txusrclk2_freq_counter_axi 持续递增；
APPLY 后 cfg_update_seen = 1；
cfg_valid = 1；
cfg_error = 0；
ENABLE 后 engine_start_seen = 1。
```

可以写为：

```text
1000M Profile1 static 的 GT/MMCM/txusrclk2 alive、配置加载和发送启动链路已经通过 AXI/FCLK ILA 阶段性验证。
```

来源主报告：

```text
docs/debug_reports/03_profile1_1000m_static_ila_validation_summary.md
```

### 1.4 当前不具备动态 rate set

当前仍未实现：

```text
rate set 500/1000；
GTX DRP；
MMCM DRP；
运行时 GT reset/relock 状态机；
运行时 TXUSRCLK/TXUSRCLK2 重配置；
外部光口动态切换闭环验证。
```

因此当前不能写成：

```text
1000M 动态调速已经完成；
500M <-> 1000M 运行时切换已经完成；
GTX DRP/MMCM DRP 已完成。
```

## 2. 500M 与 1000M 参数对比

下表基于当前 500M Profile0、1000M Profile1 static 报告和 1000M compare XCI/实现记录整理。GTX DRP address/bitfield 仍需后续按 UG476 / GT Wizard 生成结果最终确认。

| 参数 | 500M Profile0 static | 1000M Profile1 static | 动态切换影响 |
| --- | --- | --- | --- |
| TX line rate | 0.500 Gb/s | 1.000 Gb/s | 目标速率翻倍 |
| TXDATA width | 64 bit | 64 bit | 上层 `laser_tx_core` 保持 64-bit |
| encoding | None | None | 无 8b/10b 开销 |
| internal datawidth | 32 | 32 | GT 内部 32-bit 语义保持 |
| CPLL_FBDIV | 4 | 4 | 当前对比未观察到变化 |
| CPLL_FBDIV_45 | 4 | 4 | 当前对比未观察到变化 |
| CPLL_REFCLK_DIV | 1 | 1 | 当前对比未观察到变化 |
| TXOUT_DIV | 8 | 4 | 必须动态控制或切换 |
| TXOUTCLK | 15.625 MHz | 31.25 MHz | 随 TXOUT_DIV 变化 |
| TXUSRCLK | 15.625 MHz | 31.25 MHz | 必须与对应 TXOUTCLK/MMCM 输出一致 |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz | `laser_tx_core` 工作频率翻倍 |
| TXUSRCLK:TXUSRCLK2 | 2:1 | 2:1 | 比例保持 |

MMCM 参数对比：

| MMCM 参数 | 500M Profile0 | 1000M Profile1 | 说明 |
| --- | ---: | ---: | --- |
| `CLKIN1_PERIOD` | 64.0 ns | 32.0 ns | 输入 TXOUTCLK 周期 |
| `CLKFBOUT_MULT_F` | 12.1875 | 20.0 | VCO 配置不同 |
| `DIVCLK_DIVIDE` | 1 | 1 | 输入分频不变 |
| `CLKOUT1_DIVIDE` | 39 | 20 | TXUSRCLK |
| `CLKOUT0_DIVIDE_F` | 78.0 | 40.0 | TXUSRCLK2 |
| TXUSRCLK | 15.625 MHz | 31.25 MHz | GT `txusrclk` |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz | GT `txusrclk2` 与 `laser_tx_core` |

关键结论：

```text
500M <-> 1000M 动态切换不能只写 GTX TXOUT_DIV；
必须同步处理 TX user clock MMCM，使 TXUSRCLK/TXUSRCLK2 与目标速率自洽。
```

## 3. 动态切换必须控制的对象

动态速率切换至少需要同一个受控状态机管理以下对象。

### 3.1 GTX TXOUT_DIV / CPLL 相关 DRP

必须控制或确认：

```text
GTXE2_CHANNEL TXOUT_DIV；
必要的 CPLL 相关参数；
DRP address；
DRP bitfield；
读改写 RMW 掩码；
写后 readback；
CPLL reset / lock 依赖。
```

当前已知：

```text
500M: TXOUT_DIV=8
1000M: TXOUT_DIV=4
CPLL_FBDIV=4、CPLL_FBDIV_45=4、CPLL_REFCLK_DIV=1 当前未观察到变化。
```

仍需确认：

```text
TXOUT_DIV 对应 GTXE2_CHANNEL DRP address/bitfield；
是否还需要同步写 RXOUT_DIV 或其他 companion field；
是否需要完整 CPLL reset sequence；
是否存在 GT Wizard wrapper 内部 reset helper 依赖。
```

### 3.2 TX user clock MMCM DRP

必须控制：

```text
MMCM 动态重配置；
MMCM reset；
MMCM locked；
TXUSRCLK / TXUSRCLK2 输出频率；
BUFG 输出稳定性；
切换期间 debug hub 不依赖 txusrclk2。
```

推荐方向：

```text
优先评估单 MMCM + MMCM DRP；
避免在多个 TXUSRCLK/TXUSRCLK2 之间做未经充分验证的 glitch-sensitive mux；
MMCM DRP 参数必须来自 500M/1000M 官方或 Vivado 生成值。
```

### 3.3 GT TX reset sequence

动态切换过程中必须控制：

```text
TX datapath 停止；
GT TX reset assert；
GT/CPLL/MMCM 重新配置；
GT TX reset release；
等待 CPLL lock；
等待 TX MMCM lock；
等待 txresetdone；
等待 gt_ready；
验证 txusrclk2 alive。
```

### 3.4 laser_tx_core 停机保护

切换前必须保证：

```text
不在 busy_tx=1 时直接切速率；
先 DISABLE 或 stop；
等待 busy_tx=0 或 done_tx=1；
必要时 soft_reset；
冻结或忽略 APPLY/ENABLE 新请求；
切换完成并 VERIFY_RATE 通过后才允许重新 ENABLE。
```

### 3.5 gt_ready/status 回读

软件/控制寄存器必须能看到：

```text
current_rate；
target_rate；
rate_state；
error_code；
cplllock；
txresetdone；
tx_mmcm_locked；
gt_ready；
txusrclk2_alive；
txusrclk2_freq_counter_axi；
last_switch_result。
```

### 3.6 txusrclk2_alive / freq counter 验证

动态切换后不能只看 lock 信号，必须验证：

```text
txusrclk2_alive_axi = 1；
txusrclk2_freq_counter_axi 在 AXI/FCLK 域持续变化；
freq counter 或窗口计数符合目标速率范围；
500M 目标约 7.8125 MHz；
1000M 目标约 15.625 MHz。
```

## 4. 建议的 rate switch 状态机

建议使用 AXI/FCLK / gt_ctrl_clk 域中的 rate controller 状态机。状态机本身不要跑在 txusrclk2 域。

| 状态 | 动作 | 退出条件 | 错误条件 |
| --- | --- | --- | --- |
| `IDLE` | 当前速率稳定，等待请求 | 收到有效 rate request | 非法目标速率 |
| `REQUEST` | 锁存 `target_rate`，检查当前状态 | 请求合法且当前非 busy | 当前已有切换进行中 |
| `QUIESCE_TX` | 禁止新的 APPLY/ENABLE，要求发送链路静默 | `busy_tx=0` 或 `done_tx=1` | 超时 |
| `DISABLE_TX` | 拉低/屏蔽 TX enable，必要时 soft stop | TX 侧确认停止 | 停机失败 |
| `GT_RESET_ASSERT` | assert GT TX reset / MMCM reset 相关控制 | reset 已生效 | reset ack 超时 |
| `PROGRAM_GT_DRP` | 写 GTX TXOUT_DIV / 必要 GT DRP | DRP done + readback OK | DRP timeout/readback mismatch |
| `PROGRAM_MMCM_DRP` | 写 MMCM DRP 参数 | DRP done + 参数确认 | MMCM DRP timeout/readback mismatch |
| `RELEASE_RESET` | 释放 MMCM/GT TX reset | 进入等待 lock | reset release 超时 |
| `WAIT_LOCK` | 等待 CPLL/MMCM/TX reset done/gt_ready | 全部 ready | lock timeout |
| `VERIFY_RATE` | 检查 txusrclk2_alive / freq counter | 频率落入目标窗口 | 频率不匹配 |
| `READY` | 更新 `current_rate`，允许重新 ENABLE | 回到 IDLE | 无 |
| `ERROR_ROLLBACK` | 记录错误，尝试回退上一个已知 static rate | 回退成功或进入 fail-safe | 回退失败 |

建议伪流程：

```text
if request_rate != current_rate:
    latch target_rate
    block new enable/apply
    wait laser_tx_core idle
    assert tx/gt/mmcm reset as required
    program GT DRP
    program MMCM DRP
    release reset
    wait cplllock, tx_mmcm_locked, txresetdone, gt_ready
    verify txusrclk2_alive and freq_counter
    update current_rate
    unblock enable/apply
```

## 5. 必须保留的 debug 结构

动态切换阶段必须保留当前已修复的稳定 debug 架构。

### 5.1 debug hub clock

必须继续保持：

```text
dbg_hub/clk = gt_ctrl_clk / clk_fpga_0
```

禁止恢复为：

```text
dbg_hub/clk = txusrclk2
```

原因：

```text
动态切换期间 txusrclk2 可能停止、丢 lock 或频率变化；
debug hub 必须在 GT/MMCM 未稳定时仍可 arm/trigger/upload waveform。
```

### 5.2 AXI/FCLK ILA

必须保留或扩展：

```text
ila_1000m_bringup_axi
```

采样时钟：

```text
gt_ctrl_clk / clk_fpga_0
```

必须保留 probe：

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

动态切换阶段建议新增 probe：

```text
rate_state
target_rate
current_rate
requested_rate
error_code
drp_busy
drp_done
drp_error
mmcm_drp_busy
mmcm_drp_done
mmcm_drp_error
rollback_active
switch_timeout
```

### 5.3 txusrclk2 域 ILA

txusrclk2 域 ILA 可以保留为二级观察：

```text
txdata[63:0]
valid_mask[63:0]
busy_tx
done_tx
pattern_valid_tx
engine_start_tx
eom_out / soa_gate_out / acq_trig_out / acq_gate_out
```

但它不能作为动态切换 bring-up 的首要 debug 入口。

## 6. ???????

### Phase A?dry-run rate controller + ??? + ????? + ILA probe

Phase A ??????????????????? GTX DRP??? MMCM DRP?????? line rate????? TXUSRCLK/TXUSRCLK2??????????????????????? ILA ?????????

#### Phase A1?rate command/status/dry-run ???

???

```text
????? rate controller ??????
?? target_rate ?????
?? current_rate / target_rate / rate_state / error_code?
?? dry-run?????? DRP?
??????? dry-run / unsupported runtime change?
???????????????????
```

???

```text
rate plan 500/1000 ????
rate request ??? dry-run ????
????????? error_code?
current_rate ???????
???? GT/MMCM/txusrclk2?
???? laser_tx_core ???????
```

#### Phase A2?500M/1000M ???????????

??????????? 500M/1000M ????????????????????????? Phase A???? 500M/1000M static ???????? compare/build/ILA ??????????????????? dry-run ????????????????????????

???????

```text
rate_id
line_rate
TXDATA width
encoding
internal datawidth
CPLL_FBDIV
CPLL_FBDIV_45
CPLL_REFCLK_DIV
TXOUT_DIV
TXOUTCLK_Hz
TXUSRCLK_Hz
TXUSRCLK2_Hz
MMCM parameters
expected txusrclk2_freq_counter window
```

??/????????????

```text
current_rate
target_rate
requested_rate
rate_state
error_code
last_switch_result
expected_txusrclk2_min
expected_txusrclk2_max
observed_txusrclk2_counter
cplllock
txresetdone
tx_mmcm_locked
gt_ready
```

#### Phase A3?AXI/FCLK ILA rate_state/target/current/error probe

???

```text
??? AXI/FCLK ? ILA ??? rate controller ???
?? dbg_hub/clk = gt_ctrl_clk / clk_fpga_0?
?? txusrclk2_alive / txusrclk2_freq_counter_axi?
?? rate_state / target_rate / current_rate / error_code ? probe?
```

???

```text
AXI/FCLK ILA ??? dry-run ??????
rate_state ???????
target_rate/current_rate/error_code ???
???? txusrclk2 ? ILA ???? bring-up ???
```

### Phase B?DRP ??????????

Phase B ?? DRP ???????????????????????? laser_tx_core ?????

#### Phase B1?GTX TXOUT_DIV DRP bitfield ??

???

```text
?? GTXE2_CHANNEL TXOUT_DIV ?? DRP address/bitfield?
?????? companion field?
?? RMW mask?
?? readback ???
?? timeout/error_code ???
```

?????

```text
UG476 / GT Wizard generated HDL / ?? DRP map?
500M/1000M generated HDL parameter delta?
?? Profile0/Profile1 ??? bitstream?
```

#### Phase B2?MMCM DRP ????

???

```text
?? 500M ? 1000M MMCM DRP ???
?? Vivado ?????????????
?? MMCM reset/locked ???
?? readback/timeout/error_code?
```

???????

```text
???? MMCM DRP????? MMCM DRP ??????
????????????
???? laser_tx_core ?????
??? txdata/valid_mask ?????????
```

???

```text
???? MMCM??? GTX TXOUT_DIV?GT line rate ? TXUSRCLK/TXUSRCLK2 ??????
???????? MMCM DRP ?????? GT ???????
```

#### Phase B3?DRP ???????

???

```text
?? DRP busy/done/error?
?? readback mismatch?
?? timeout?
?? rollback_needed?
?? unsupported_rate?
?? unsafe_busy_tx?
```

???

```text
??? DRP ???????? dry-run ???
??????
???? static 500M/1000M ???
?????????????
```

### Phase C?500M <-> 1000M ?????????

???????????????????? GTX DRP ??? MMCM DRP?

???????

```text
laser_tx_core quiesce / disable?
GT TX reset sequence?
GTX TXOUT_DIV DRP?
TX user clock MMCM DRP?
MMCM reset/lock?
CPLL lock?
txresetdone?
gt_ready?
txusrclk2_alive / freq counter verify?
error rollback?
```

?????

```text
500M -> 1000M ???????
1000M -> 500M ???????
????? current_rate ???
????? txusrclk2_freq_counter ???????
????? gt_ready/cplllock/txresetdone/tx_mmcm_locked ???
??????? ERROR_ROLLBACK?
```

???

```text
?? Phase C ????????? 500M<->1000M ?????
Phase B ? GTX DRP ? MMCM DRP ?????????????????
```

### Phase D??????? 500 -> 1000 -> 500?????

???

```text
????? 500M -> 1000M -> 500M?
???????
??????? laser_tx_core?
??????? cplllock?tx_mmcm_locked?txresetdone?gt_ready?
??????? txusrclk2_alive/freq_counter?
??? APPLY/ENABLE?
?? txdata/valid_mask?
```

?????

```text
??? current_rate?
??? current_rate?
rate_state?
error_code?
?????
txusrclk2 ?????
?? rollback?
?????
?????????
```

???????????????????????????????

### Phase E???????????

?? Phase D ????????

```text
2.5G / 5G / 10G?
? profile?
QPLL/CPLL ???
AD9528/refclk ???
?????? bitstream??? profile ??? DRP ?????
???????????
???? timing/XDC/ILA ???
```

## 7. 风险清单

| 风险 | 说明 | 建议 |
| --- | --- | --- |
| GTX DRP address/bitfield 未完全确认 | 错写 GT DRP 可能导致 GT 无法恢复 | 未确认前禁止写 GTX DRP |
| MMCM DRP 参数未完全确认 | 错误 MMCM 参数会导致 TXUSRCLK/TXUSRCLK2 不正确 | 必须从官方生成值或 Vivado 可靠流程确认 |
| reset sequence 错误 | 可能导致 txusrclk2 停止、txresetdone 不回来 | 状态机必须有 timeout/error/rollback |
| Vitis 自动下载旧 bit | 软件运行在旧硬件上会误判 | 上板流程必须明确 Program FPGA 使用匹配 bit/LTX，Vitis 不自动下载旧 bit |
| debug hub 时钟误接回 txusrclk2 | 切换失败时可能无法抓 ILA | dbg_hub 必须保持 AXI/FCLK |
| laser_tx_core 未停机就切换 | 可能破坏发送状态机和外部输出 | 必须 QUIESCE_TX 并等待 idle |
| txusrclk2 only lock 不足 | lock=1 不等于频率正确 | 必须验证 txusrclk2_alive/freq counter |
| rollback 不完整 | 切换失败后无法恢复 | 必须能回退到 static 500M 或 static 1000M |
| Profile0/1 静态基线被破坏 | 失去可回退参考 | 动态实现必须保留 static 500M/1000M bitstream 和报告 |

## 8. 禁止事项

本轮禁止：

```text
不要修改 RTL；
不要修改 BD；
不要修改 XDC；
不要修改 Vitis；
不要重新 build；
不要重新生成 bit/LTX；
不要实现 GTX DRP；
不要实现 MMCM DRP；
不要把本设计计划写成已经完成；
不要把 1000M static 写成动态 rate set；
不要把 AXI/FCLK ILA 状态验证写成外部光口闭环通过。
```

后续进入实现前仍需用户确认：

```text
是否先做 Phase A dry-run rate controller；
动态控制寄存器地址/软件协议是否扩展；
GTX DRP address/bitfield 依据；
MMCM DRP 参数生成与验证方式；
切换失败 rollback 策略；
是否保留独立 static 500M/1000M bitstream 作为强制回退方案。
```

## 9. ??????

??????? Phase A?????? A1/A2/A3?

```text
Phase A1?rate command/status/dry-run ????
Phase A2?500M/1000M ????????????
Phase A3?AXI/FCLK ILA rate_state/target/current/error probe?
```

Phase A ?????

```text
?? GTX DRP?
?? MMCM DRP?
????? line rate?
??? TXUSRCLK/TXUSRCLK2?
????????????
?? dry-run ???????????
```

???

```text
500M/1000M static ???????? compare/build/ILA ?????
?????????expected txusrclk2 frequency window?current_rate/target_rate/error_code/status register ??? dry-run ????
?????????????????????? ILA ?????
?????? 500M/1000M static ???
????????? GT/MMCM ???????
```

?? Phase B ??????

```text
GTX TXOUT_DIV DRP bitfield ??????
MMCM DRP ?????
readback/timeout/error code ???
Phase B ???????????????????
```

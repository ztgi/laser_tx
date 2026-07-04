# 1000M Profile1 static ILA/debug 自检报告

## 1. 当前现象复述

当前用户已在 Vivado Hardware Manager 中成功 Program FPGA，GUI 显示：

```text
Device xc7z100 is programmed with a design that has 3 ILA core(s).
```

但上板调试出现：

```text
hw_ila_3 可以 armed；
run_hw_ila -trigger_now 后 upload waveform 报错：
ERROR: [Labtools 27-3312] Data read from hw_ila hw_ila_3 is corrupted. Unable to upload waveform.
另外两个 ILA 没有有效可观察内容；
串口程序可以运行；
当前 ILA 调试链路不可用。
```

本轮只做 ILA/debug 自检、implemented design 结构检查和报告输出。未修改 RTL、BD、XDC、Vitis，不推进动态 `rate set`，不写 GTX DRP，不写 MMCM DRP。

## 2. bit / ltx 检查

期望使用同一次 1000M Profile1 静态构建生成的 bit/LTX：

```text
BIT path:
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit

LTX path:
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

文件检查结果：

| 文件 | 存在 | 大小 | 时间戳 |
| --- | --- | ---: | --- |
| `laser_tx_board_top_profile1_1000m.bit` | 是 | 17416477 bytes | 2026-06-29 20:51:27 |
| `laser_tx_board_top_profile1_1000m.ltx` | 是 | 114853 bytes | 2026-06-29 20:51:28 |

LTX 解析结果：

```text
LTX 中包含 3 个 labtools_ila_v6 core。
Hardware Manager GUI 也显示 3 个 ILA core。
```

因此，从文件和 LTX 结构看，当前 bit/LTX 大概率没有混用 500M 主工程文件。由于 CLI 侧没有成功打开 hw_target，本轮未能从 batch Tcl 读取 Hardware Manager 当前实际加载的 PROBES.FILE；GUI 中仍需人工确认当前 device properties 里的 probes file 是上述 1000M LTX。

本轮 CLI log 未出现 `Dropping logic core` warning；但由于 CLI 没有枚举到 hw_target，该项不能完全替代 GUI log 检查。

## 3. 三个 ILA 的 CELL_NAME / probe 数量 / probe 摘要

以下信息来自 1000M static LTX 与 implemented design 结构检查。

### 3.1 `u_laser_gt_tx_profile1_1000m/u_ila_gt_profile1_1000m`

LTX core location：

```text
user_chain=1
slave_index=0
bscan_switch_index=0
```

Probe 数量：8

| Probe | Width | Net |
| --- | ---: | --- |
| probe0 | 1 | `u_laser_gt_tx_profile1_1000m/gt_ready_tx` |
| probe1 | 1 | `u_laser_gt_tx_profile1_1000m/cplllock_sync` |
| probe2 | 1 | `u_laser_gt_tx_profile1_1000m/txresetdone_sync` |
| probe3 | 1 | `u_laser_gt_tx_profile1_1000m/tx_mmcm_locked_sync` |
| probe4 | 1 | `u_laser_gt_tx_profile1_1000m/txusrclk2_divided_debug` |
| probe5 | 24 | `u_laser_gt_tx_profile1_1000m/tx_word_count` |
| probe6 | 64 | `u_laser_gt_tx_profile1_1000m/txdata_in` |
| probe7 | 64 | `u_laser_gt_tx_profile1_1000m/valid_mask_in` |

### 3.2 `u_system_wrapper/system_i/ila_laser_axi_cfg`

LTX core location：

```text
user_chain=1
slave_index=1
bscan_switch_index=0
```

Probe 数量：6

| Probe | Width | Net |
| --- | ---: | --- |
| probe0 | 32 | `u_system_wrapper/system_i/axi_gpio_0_gpio_io_o` |
| probe1 | 32 | `u_system_wrapper/system_i/laser_tx_core_0_gpio_status` |
| probe2 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_bram_en` |
| probe3 | 32 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_bram_addr` |
| probe4 | 32 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_bram_dout` |
| probe5 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_bram_rst` |

### 3.3 `u_system_wrapper/system_i/ila_laser_tx`

LTX core location：

```text
user_chain=1
slave_index=2
bscan_switch_index=0
```

Probe 数量：15

| Probe | Width | Net |
| --- | ---: | --- |
| probe0 | 64 | `u_system_wrapper/system_i/laser_tx_core_0_txdata` |
| probe1 | 64 | `u_system_wrapper/system_i/laser_tx_core_0_valid_mask` |
| probe2 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_eom_out` |
| probe3 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_soa_gate_out` |
| probe4 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_acq_trig_out` |
| probe5 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_acq_gate_out` |
| probe6 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_busy_tx` |
| probe7 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_done_tx` |
| probe8 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_phase_active_tx` |
| probe9 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_phase_start_pulse_tx` |
| probe10 | 8 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_phase_offset_tx` |
| probe11 | 8 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_current_state_tx` |
| probe12 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_cfg_update_pulse_tx` |
| probe13 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_pattern_valid_tx` |
| probe14 | 1 | `u_system_wrapper/system_i/laser_tx_core_0_dbg_engine_start_tx` |

注意：由于本轮 batch Tcl 未能打开 hw_target，不能严格确认 GUI 中的 `hw_ila_1/2/3` 与上述 `slave_index=0/1/2` 的一一对应关系。按 LTX 顺序推断，`hw_ila_3` 很可能对应 `ila_laser_tx`，但最终映射需以 Vivado GUI 的 `CELL_NAME` 显示为准。

## 4. implemented design 中 ILA 时钟连接

脚本：

```text
scripts/check_1000m_ila_impl_clocks.tcl
```

报告：

```text
reports/gt_profile1_1000m_static/ila_debug_check/check_1000m_ila_impl_clocks.rpt
```

Clock summary：

```text
clk_fpga_0          period = 20.000 ns
TXOUTCLK            period = 32.000 ns
clkout1_txusrclk    period = 32.000 ns
clkout0_txusrclk2   period = 64.000 ns
```

ILA clock table：

| ILA | CELL_NAME | clk source | clock frequency | 是否 free-running | 风险 |
| --- | --- | --- | --- | --- | --- |
| `ila_laser_axi_cfg` | `u_system_wrapper/system_i/ila_laser_axi_cfg` | `processing_system7_0/FCLK_CLK0` via `gt_ctrl_clk` | `clk_fpga_0`, 20 ns / 50 MHz | PS init 后应稳定 | 低 |
| `ila_laser_tx` | `u_system_wrapper/system_i/ila_laser_tx` | `u_txusrclk2_bufg/O` via `txusrclk2` | `clkout0_txusrclk2`, 64 ns / 15.625 MHz | 依赖 GT TXOUTCLK 和 TX MMCM lock | 高 |
| `ila_gt_profile1_1000m` | `u_laser_gt_tx_profile1_1000m/u_ila_gt_profile1_1000m` | `u_txusrclk2_bufg/O` via `txusrclk2_out` | `clkout0_txusrclk2`, 64 ns / 15.625 MHz | 依赖 GT TXOUTCLK 和 TX MMCM lock | 高 |

## 5. debug hub 时钟来源

implemented design 结构检查显示：

```text
dbg_hub/clk: net=gt_txusrclk2; clocks=clkout0_txusrclk2 period=64.000ns
```

这点是本轮最关键发现：即使 `ila_laser_axi_cfg` 自身的采样时钟是 PS FCLK，整个 debug hub 的主时钟却接在 `txusrclk2` 上。因此当 `txusrclk2` 未稳定、停止、抖动、或 GT/MMCM 处在 reset/unlock 过程中时，不仅 TX 域 ILA 有风险，debug hub 数据上传链路本身也有风险。

这解释了“另外两个 ILA 没有有效可观察内容”的现象：不是只有某个 probe 不好，而是 debug hub 入口时钟本身不是稳定 bring-up 时钟。

## 6. 三个 ILA 的 `trigger_now + upload` 结果

硬件自检脚本：

```text
scripts/check_1000m_ila_debug.tcl
```

脚本输出 log：

```text
reports/gt_profile1_1000m_static/ila_debug_check/check_1000m_ila_debug.log
```

本轮 batch Tcl 运行结果：

```text
HW_TARGET_COUNT = 0
ERROR: no hw_target found after connect_hw_server.
```

因此 CLI 未能执行到：

```text
run_hw_ila -trigger_now
wait_on_hw_ila
upload_hw_ila_data
```

实际 `trigger_now + upload` 结果表：

| ILA | batch Tcl 结果 | 用户 GUI 现象 | 说明 |
| --- | --- | --- | --- |
| `hw_ila_1` | 未执行，CLI 未枚举到 hw_target | 无有效可观察内容 | CLI 侧无法确认 upload OK/corrupted |
| `hw_ila_2` | 未执行，CLI 未枚举到 hw_target | 无有效可观察内容 | CLI 侧无法确认 upload OK/corrupted |
| `hw_ila_3` | 未执行，CLI 未枚举到 hw_target | armed 后 upload corrupted | 结合结构检查，更偏向 debug clock / txusrclk2 风险 |

说明：CLI 未枚举到 hw_target 可能与当前 Vivado GUI/hw_server/cable 占用、目标未暴露给新 batch Vivado、或本机硬件服务器状态有关。该现象不能证明 ILA 正常，也不能替代用户 GUI 中已经看到的 `hw_ila_3 corrupted`。

## 7. 1000M clock/reset/status 可观测性

基于 HDL 和 implemented design：

```text
TXOUTCLK period  = 32 ns
TXUSRCLK period  = 32 ns
TXUSRCLK2 period = 64 ns
```

状态信号存在：

| 信号 | 来源 | 当前可观测位置 | 风险 |
| --- | --- | --- | --- |
| `cplllock_sync` | GT CPLL lock 同步后 | `ila_gt_profile1_1000m` probe1 | 该 ILA 在 txusrclk2 域，debug hub 也在 txusrclk2，bring-up 风险高 |
| `txresetdone_sync` | GT TX reset done 同步后 | `ila_gt_profile1_1000m` probe2 | 同上 |
| `tx_mmcm_locked_sync` | TX user clock MMCM lock 同步后 | `ila_gt_profile1_1000m` probe3 | 同上 |
| `gt_ready_tx` | GT ready 同步后 | `ila_gt_profile1_1000m` probe0 / `gt_status_out` | ILA 观测风险高；软件 MMIO 读回相对更可靠 |
| `txusrclk2_divided_debug` | txusrclk2 域分频 debug | `ila_gt_profile1_1000m` probe4 | 如果该 ILA corrupted，无法作为首要 bring-up 证据 |

当前没有一个专门的稳定 AXI/FCLK 域 bring-up ILA 来观测上述 GT/MMCM 状态和 `txusrclk2_alive`。

## 8. 原因判断：clock / probe mapping / JTAG 哪个更可疑

当前证据判断：

| 假设 | 证据 | 判断 |
| --- | --- | --- |
| LTX/probe 映射错误 | LTX 中 3 个 ILA core 与 implemented design CELL_NAME 一致；probe 数量和信号名合理；bit/LTX 时间戳相邻 | 不是首要嫌疑 |
| JTAG/hw_server 总体问题 | 用户 GUI 能 Program FPGA，并能看到 3 个 ILA，`hw_ila_3` 可 armed；但 CLI batch 未枚举到 hw_target | 不能完全排除，但不是解释 `hw_ila_3` corrupted 的最强证据 |
| ILA/debug clock 问题 | `ila_laser_tx` 和 `ila_gt_profile1_1000m` 均接 `txusrclk2`；更关键的是 `dbg_hub/clk` 也接 `txusrclk2`；该时钟依赖 GT TXOUTCLK 和 TX MMCM lock | 最可能 |

结论：`hw_ila_3 upload waveform corrupted` 更可能是 debug hub / ILA 采样时钟使用了非 bring-up 稳定的 `txusrclk2`，而不是 UDP/APPLY 命令问题。`trigger_now` 不依赖 UDP APPLY；如果 trigger_now 后 upload corrupted，问题在 ILA/debug/clock/JTAG 链路，不在 UDP 命令解析。

## 9. 是否存在 ILA clock 非 free-running 风险

存在。

风险点如下：

1. `txusrclk2` 来自 GT TXOUTCLK -> 1000M TX MMCM -> BUFG；
2. GT TXOUTCLK 依赖 CPLL / GT reset sequence；
3. TXUSRCLK2 依赖 TX MMCM lock；
4. 当前 `dbg_hub/clk` 接到 `gt_txusrclk2`；
5. 当 GT/MMCM 未稳定时，debug hub 可能无法可靠完成 waveform upload。

因此当前 ILA/debug 结构不适合作为 1000M static bring-up 的首要观测链路。

## 10. 当前 1000M static debug 是否可继续用于上板

不建议继续依赖当前 ILA 结构做 1000M static bring-up 收口。

原因：

```text
GT/MMCM 状态最需要在 bring-up 初期观测；
但当前 GT/MMCM 状态主要在 txusrclk2 域 ILA 中；
debug hub 本身也由 txusrclk2 驱动；
如果 txusrclk2 未稳定，就无法可靠观察导致 txusrclk2 未稳定的原因。
```

这形成了调试闭环上的“鸡生蛋”问题：需要 ILA 判断 txusrclk2 是否活着，但 ILA/debug hub 又依赖 txusrclk2 活着。

## 11. 是否需要新增 AXI/FCLK 域 bring-up ILA

需要。

建议新增一个稳定 AXI/FCLK 域 ILA，例如：

```text
ila_1000m_bringup_axi
```

其 `clk` 必须接稳定 `axi_clk / PS FCLK`，不要接 `txusrclk2`。至少观测以下同步到 AXI 域的信号：

```text
cplllock
txresetdone
tx_mmcm_locked
gt_ready
txusrclk2_alive
txusrclk2_freq_counter
cfg_update_seen_axi
engine_start_seen_axi
busy_tx_sync
done_tx_sync
cfg_valid_sync
cfg_error_sync
gpio_apply_toggle_axi
gpio_enable_axi
```

同时建议将 debug hub 时钟改为稳定 AXI/FCLK，使即使 GT/MMCM 未 lock，也能可靠上传 AXI 域 bring-up ILA 波形。

可以保留 txusrclk2 域 ILA，但不要把它作为 1000M bring-up 必需观察手段。

## 12. 本轮修改内容

本轮新增/修改文件：

| 文件 | 变更 |
| --- | --- |
| `scripts/check_1000m_ila_debug.tcl` | 新增硬件 ILA 自检脚本；只连接/刷新/列举/尝试 trigger_now + upload，不 Program FPGA |
| `scripts/check_1000m_ila_impl_clocks.tcl` | 新增 implemented design ILA clock 连接检查脚本 |
| `docs/debug_reports/20260629_gt_profile1_1000m_ila_debug_check.md` | 新增本报告 |

本轮未修改：

```text
未修改 RTL 功能逻辑
未修改 BD
未修改 XDC
未修改 Vitis
未修改 GT Wizard
未修改 500M Profile0
未重新生成 bitstream
未重新生成 LTX
未实现动态 rate set
未写 GTX DRP
未写 MMCM DRP
```

## 13. 构建 / 运行记录

implemented design clock check：

```powershell
& 'D:\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'D:\FPGA_Learn\laser_tx\scripts\check_1000m_ila_impl_clocks.tcl'
```

结果：完成，生成：

```text
reports/gt_profile1_1000m_static/ila_debug_check/check_1000m_ila_impl_clocks.rpt
```

hardware ILA debug check：

```powershell
& 'D:\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'D:\FPGA_Learn\laser_tx\scripts\check_1000m_ila_debug.tcl'
```

结果：未能进入 ILA trigger/upload，原因：

```text
HW_TARGET_COUNT = 0
ERROR: no hw_target found after connect_hw_server.
```

Hardware test was partially attempted but not completed from batch Tcl。用户 GUI 中已观察到 `hw_ila_3` upload corrupted，但本轮 CLI 没有复现到 upload 阶段。

## 14. 当前分层结论

| 项目 | 结论 |
| --- | --- |
| 1000M bit 已 Program | 用户 GUI 已确认 |
| Hardware Manager ILA 数量 | 用户 GUI 显示 3；LTX 也包含 3 |
| bit/LTX 文件匹配 | 文件时间戳相邻，LTX core 与 implemented design 一致；仍需 GUI 确认 PROBES.FILE |
| ILA probe 结构 | 合理，非首要嫌疑 |
| `ila_laser_axi_cfg` 采样时钟 | AXI/FCLK |
| `ila_laser_tx` 采样时钟 | `txusrclk2`，高风险 |
| `ila_gt_profile1_1000m` 采样时钟 | `txusrclk2`，高风险 |
| debug hub 时钟 | `txusrclk2`，高风险 |
| `hw_ila_3 corrupted` 最可能原因 | debug hub / ILA clock 依赖不稳定或未确认稳定的 `txusrclk2` |
| UDP/APPLY 是否相关 | 否，`trigger_now` 不依赖 UDP APPLY |
| 当前 1000M static ILA debug 是否可继续用于收口 | 不建议 |
| 是否需要 AXI/FCLK bring-up ILA | 需要 |
| 是否已修改 RTL 修复 | 否，本轮只做自检与报告 |

## 15. 下一步建议

建议下一轮按以下最小修复方案执行：

1. 新增稳定 AXI/FCLK 域 bring-up ILA：`ila_1000m_bringup_axi`。
2. 将 debug hub 时钟改为稳定 `axi_clk / PS FCLK`。
3. 在 `txusrclk2` 域增加自由运行计数器或 toggle。
4. 将 `txusrclk2_alive / txusrclk2_freq_counter` 通过 CDC 同步到 AXI 域。
5. 将 `cplllock / txresetdone / tx_mmcm_locked / gt_ready` 同步或锁存到 AXI 域供 ILA 观察。
6. 保留原 txusrclk2 域 ILA，但只作为 GT/MMCM 稳定后的二级观察手段。
7. 重新生成 1000M static bit/LTX。
8. 上板先用 AXI ILA 证明：

   ```text
   debug hub 可稳定上传；
   cplllock=1；
   tx_mmcm_locked=1；
   txresetdone=1；
   gt_ready=1；
   txusrclk2_alive 正在变化；
   ```

9. 再进入 APPLY / ENABLE / txdata / valid_mask 的 1000M static 功能验证。

在完成上述稳定 bring-up debug 结构前，不建议继续推进动态速率切换。

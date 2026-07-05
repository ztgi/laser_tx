# 2.000G dynamic profile 上板 bring-up 计划

## 1. 目标

本计划用于验证 500M/1000M/2000M 三档固定 profile 的动态切换。当前目标不是宽范围速率控制，而是确认新增 2G profile 在现有 125MHz REFCLK、CPLL、GT DRP + MMCM DRP + reset/lock/ready 闭环中可用。

## 2. 上板前准备

使用同源 bit/LTX：

```text
Bitstream:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m_2000m/artifacts/laser_tx_board_top_dynamic_500m_1000m_2000m.bit

Debug probes:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m_2000m/artifacts/laser_tx_board_top_dynamic_500m_1000m_2000m.ltx
```

使用重新 build 后的 ELF：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf
```

注意：Program bit/LTX 后需要 `rst -processor` 并重新 run ELF，避免 PS/PL 状态不同步。

## 3. 基础启动流程

1. Vivado Hardware Manager Program Device；
2. Bitstream file 选择 dynamic 500M/1000M/2000M bit；
3. Debug probes file 选择同目录同名 LTX；
4. Program 后 Refresh Device，确认不出现 bit/LTX mismatch；
5. XSCT 执行 `rst -processor`；
6. 下载并运行 `bringup.elf`；
7. 串口确认 app 模式为 `MINIMAL_DYNAMIC_500M_1000M_2000M`；
8. UDP 执行 `PING`，期望返回 `OK PONG`；
9. UDP 执行 `rate status`，确认当前状态可读。

## 4. UDP 验证顺序

建议先确认原 500M/1000M 功能不退化，再验证 2G。

```text
PING
rate status
rate set 1000
rate status
rate set 500
rate status
rate set 2000
rate status
rate set 1000
rate status
rate set 2000
rate status
rate set 500
rate status
```

循环验证建议：

```text
500 -> 1000 -> 2000 -> 1000 -> 500
```

每一步期望：

```text
state=DONE
error_code=NONE
current_rate=<target>
gt_drp_written=1
mmcm_drp_written=1
gt_ready=1
```

如果 `rate set` 返回 ERROR，不要继续循环，先记录 `rate_state/error_code/raw status` 并抓 AXI/FCLK ILA。

## 5. AXI/FCLK ILA 观察重点

AXI/FCLK ILA 用于判断 rate controller、GT/MMCM DRP、reset/lock/ready 和频率窗口。

重点 probe：

```text
rate_state
rate_error_code
target_rate_mbps
current_rate_mbps
gt_drp_write_attempted
gt_drp_done
gt_drp_error
mmcm_drp_write_attempted
mmcm_drp_done
mmcm_drp_error
tx_mmcm_reset_rate
tx_mmcm_reset_wizard
tx_mmcm_reset
txoutclk_alive_axi
tx_mmcm_locked_raw
tx_mmcm_locked_sync
rate_gt_tx_reset
gt0_gttxreset_effective
rate_txuserrdy_block
gt0_txuserrdy_effective
txresetdone_sync
gt_ready
txusrclk2_alive_axi
txusrclk2_freq_counter_axi
```

2G 预期：

```text
target_rate_mbps = 2000
current_rate_mbps = 2000
rate_error_code = NONE
gt_ready = 1
tx_mmcm_locked_raw = 1
tx_mmcm_locked_sync = 1
txusrclk2_freq_counter_axi ≈ 30800..31800 初始窗口
```

## 6. TX 域 ILA 观察重点

完成 2G `rate set` 后，再用 TX 域 ILA 验证发送侧没有退化：

```text
cfg_update_pulse_tx
pattern_valid_tx
engine_start_tx
busy_tx
done_tx
txdata[63:0]
valid_mask[63:0]
eom_out
soa_gate_out
acq_trig_out
acq_gate_out
```

建议先用短 direct case 触发：

```text
SOFT_RESET
WRITE_CONFIG ...
SELECT_CONFIG ...
APPLY
ENABLE
```

注意：短序列下 `busy_tx` 和有效 `txdata/valid_mask` 窗口可能很短，TX 域 ILA 需要在 `engine_start_tx` 或 `busy_tx` 附近触发。

## 7. 推荐截图命名

如果本轮上板通过，建议保存以下真实 Vivado GUI / UDP 截图：

```text
docs/images/dynamic_rate/dynamic_2g_profile/udp_dynamic_2g_rate_set_2000_done.png
docs/images/dynamic_rate/dynamic_2g_profile/udp_dynamic_500_1000_2000_loop_pass.png
docs/images/dynamic_rate/dynamic_2g_profile/ila_dynamic_500_to_2000_overview_state_sequence.png
docs/images/dynamic_rate/dynamic_2g_profile/ila_dynamic_2000_done_lock_ready_freq.png
docs/images/dynamic_rate/dynamic_2g_profile/ila_dynamic_500_1000_2000_loop_representative.png
```

这些路径只是截图归档建议。当前文档不引用不存在的图片。

## 8. 通过标准

2G dynamic profile 初步通过标准：

- UDP `rate set 2000` 返回 DONE；
- `current_rate=2000`；
- `error_code=NONE`；
- `gt_ready=1`；
- `gt_drp_written=1`；
- `mmcm_drp_written=1`；
- AXI/FCLK ILA 看到 MMCM lock、GT ready 和 TXUSRCLK2 frequency counter 落入 2G 预期窗口；
- 500M/1000M 原路径仍能 DONE；
- 至少完成一次 `500 -> 1000 -> 2000 -> 1000 -> 500` 循环；
- 如需发送链路证据，TX 域 ILA 捕获到 `txdata/valid_mask` 活动。

## 9. 失败时优先定位表

| 现象 | 优先怀疑 | 建议动作 |
|---|---|---|
| `rate set 2000` 返回 unsupported | Vitis parser 或 PL profile_supported 未加入 2000 | 查 `laser_udp_server.c`、`laser_gpio.h`、RTL profile decode |
| GT DRP done=0 | GT DRP transaction timeout | 查 `gt_drp_addr/di/en/we/rdy` |
| MMCM DRP done=0 | MMCM DRP transaction timeout | 查 `mmcm_drp_addr/di/en/we/rdy` |
| MMCM_LOCK_TIMEOUT | MMCM reset / TXOUTCLK / DRP data / lock CDC | 查 `tx_mmcm_reset_*`、`txoutclk_alive_axi`、`locked_raw/sync` |
| GT_READY_TIMEOUT | TXUSERRDY / GTTXRESET / txresetdone | 查 `rate_txuserrdy_block`、`gt0_txuserrdy_effective`、`txresetdone_sync` |
| VERIFY_RATE 失败 | 2G frequency window 候选不匹配 | 查 `txusrclk2_freq_counter_axi`，必要时调整窗口 |
| DONE 但 TX ILA 无有效数据 | 发送触发窗口太短或配置未 APPLY/ENABLE | 以 `engine_start_tx` / `busy_tx` 重新触发 |

## 10. 当前边界

本计划只覆盖 500M/1000M/2000M 固化 profile 的上板 bring-up。即使 2G dynamic 通过，也仍不证明：

- 任意速率动态控制；
- 156.25MHz refclk / AD9528 动态输出；
- QPLL profile；
- 外部光口闭环质量；
- 长期稳定性或误码率。


# 2.000G Static Profile 上板 Bring-up 计划

## 1. 目标与边界

本计划用于后续对 `Profile2 / 2.000Gbps static TX` bitstream 做第一轮上板 bring-up。该 bitstream 的目标是验证 2.000Gbps TX profile 在当前板卡、125MHz REFCLK、CPLL 架构下能否独立工作。

本阶段不是动态速率切换验证：

- 不执行 `rate set 2000`；
- 不修改 UDP 协议；
- 不修改 Vitis；
- 不启用 AD9528 动态输出；
- 不切换 156.25MHz REFCLK；
- 不声明 2.000G 已加入 500M/1000M dynamic profile table。

## 2. 使用产物

推荐使用同一次 build 生成的一对 bit/LTX：

| 类型 | 路径 |
| --- | --- |
| Bitstream | `D:/FPGA_Learn/laser_tx/reports/gt_profile2_2000m_static/artifacts/laser_tx_board_top_profile2_2000m.bit` |
| Debug probes | `D:/FPGA_Learn/laser_tx/reports/gt_profile2_2000m_static/artifacts/laser_tx_board_top_profile2_2000m.ltx` |

## 3. Vivado Hardware Manager 操作

1. 打开 Vivado Hardware Manager。
2. 连接板卡 JTAG。
3. Program Device：
   - Bitstream file 选择 `laser_tx_board_top_profile2_2000m.bit`；
   - Debug probes file 选择 `laser_tx_board_top_profile2_2000m.ltx`。
4. Program 后 Refresh Device，确认 ILA/debug hub 正常识别。
5. 如果出现 bit/LTX mismatch，不要继续测试 UDP，先确认加载的是同一目录下的匹配 bit/LTX。

## 4. PS / Vitis 启动

1. 如需要，先用 XSCT 执行 `ps7_init` / `ps7_post_config`。
2. 运行现有 Vitis bringup ELF。
3. 本阶段继续使用现有 UDP 控制程序；该软件不会新增 `rate set 2000`。
4. 先验证基础通信：
   - `PING`
   - `READ_GT_STATUS`
   - `rate status`

## 5. AXI/FCLK ILA 首要观察项

优先使用 AXI/FCLK 域 bring-up ILA，确认 GT/MMCM/clock alive 状态：

- `cplllock_sync`
- `tx_mmcm_locked_sync`
- `txresetdone_sync`
- `gt_ready`
- `txoutclk_alive_axi`
- `txusrclk2_alive_axi`
- `txusrclk2_freq_counter_axi`

预期：

- `cplllock_sync = 1`
- `tx_mmcm_locked_sync = 1`
- `txresetdone_sync = 1`
- `gt_ready = 1`
- `txoutclk_alive_axi = 1`
- `txusrclk2_alive_axi = 1`
- `txusrclk2_freq_counter_axi` 对应 31.25MHz TXUSRCLK2 的统计窗口。

## 6. TX 域 ILA 观察项

在 AXI/FCLK 状态稳定后，再观察 txusrclk2 域 ILA：

- `cfg_valid`
- `engine_start`
- `busy`
- `done`
- `pattern_valid`
- `txdata[63:0]`
- `valid_mask[63:0]`

建议流程：

1. 写入一个已知 Direct pattern 配置。
2. `APPLY` 后观察 `cfg_valid/pattern_valid`。
3. `ENABLE` 后观察 `engine_start/busy/done`。
4. 确认 `txdata` 非零，`valid_mask` 在发送窗口内有效。

## 7. 建议截图归档路径

如果上板验证通过，请保存真实 Vivado GUI / UDP 截图到：

| 证据 | 建议路径 |
| --- | --- |
| GT/MMCM ready 与频率计数 | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_gt_mmcm_ready_freq.png` |
| TX data / valid_mask | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_txdata_validmask.png` |
| UDP ping/status | `docs/images/dynamic_rate/third_rate_2g_static/udp_2g_static_ping_status.png` |

## 8. 通过标准

2.000G static 上板 bring-up 的最低通过标准：

- bit/LTX 匹配且 Hardware Manager 无 mismatch；
- debug hub 和 ILA 可正常 arm / trigger / upload；
- `cplllock_sync = 1`；
- `tx_mmcm_locked_sync = 1`；
- `txresetdone_sync = 1`；
- `gt_ready = 1`；
- `txusrclk2_freq_counter_axi` 符合 31.25MHz 预期；
- APPLY 后配置有效；
- ENABLE 后 `txdata/valid_mask` 有效。

## 9. 不通过时的定位顺序

1. bit/LTX 是否同源。
2. debug hub 是否可用。
3. `cplllock_sync` 是否为 1。
4. `txoutclk_alive_axi` 是否为 1。
5. `tx_mmcm_locked_sync` 是否为 1。
6. `txusrclk2_alive_axi` 与频率计数是否符合预期。
7. `gt_ready` / `txresetdone_sync` 是否恢复。
8. APPLY/ENABLE 控制链路是否进入 PL。

## 10. 当前状态

截至本计划生成时，2.000G static profile 已完成 build/timing/bit/LTX 生成，但尚未执行上板验证。不能将 build 通过写成 2.000G 上板通过，也不能将 2.000G static 写成 dynamic rate set 已实现。

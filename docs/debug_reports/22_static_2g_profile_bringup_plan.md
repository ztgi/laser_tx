# 2.000G Static Profile 上板 Bring-up 计划与初测记录

## 1. 目标与边界

本计划用于对 `Profile2 / 2.000Gbps static TX` bitstream 做上板 bring-up。该 bitstream 的目标是验证 2.000Gbps TX profile 在当前板卡、125MHz REFCLK、CPLL 架构下能否独立工作。

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

优先使用 AXI/FCLK 域 bring-up ILA，确认 GT/MMCM/clock alive 状态。本次 2.000G static 上板初测已观察到：

- `cplllock_sync = 1`
- `tx_mmcm_locked_sync = 1`
- `txresetdone_sync = 1`
- `gt_ready_tx = 1`
- `txusrclk2_divided_debug` 有周期性跳变

注意：本次 static ILA 没有 `txoutclk_alive_axi`、`txusrclk2_alive_axi`、`txusrclk2_freq_counter_axi`，因此当前只能写成 GT/MMCM ready 已恢复、TXUSRCLK2 divided debug 有跳变，不能声明已精确验证 `TXUSRCLK2 = 31.25MHz`。

后续如果要作为加入 dynamic profile table 前的更强证据，建议补充以下任一类证明：

- AXI/FCLK 域 `txusrclk2_freq_counter_axi`；
- 等价的低速 divided clock 频率测量；
- 示波器测量；
- Vivado ILA 中稳定可复核的频率计数窗口。

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
4. 重新 trigger 捕获发送窗口，确认 `txdata` 非零，`valid_mask` 在发送窗口内有效。

## 7. 截图归档路径

本次已有截图：

| 证据 | 路径 |
| --- | --- |
| UDP config/apply/enable | `docs/images/dynamic_rate/third_rate_2g_static/udp_2g_static_config_apply_enable_ok.png` |
| AXI/FCLK APPLY/ENABLE/done | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_axi_cfg_apply_enable_done.png` |
| GT/MMCM ready 与 txusrclk2 divided debug | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_gt_mmcm_ready_txusrclk2_divided_toggle.png` |
| TX 域未捕获发送窗口说明 | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_tx_domain_idle_after_enable_need_retrigger.png` |

后续建议新增截图：

| 证据 | 建议路径 |
| --- | --- |
| TX data / valid_mask 有效窗口 | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_txdata_validmask.png` |
| TXUSRCLK2 精确频率计数或等价证明 | `docs/images/dynamic_rate/third_rate_2g_static/ila_2g_static_txusrclk2_freq_counter.png` |

## 8. 完整通过标准

2.000G static 上板 bring-up 的完整通过标准：

- bit/LTX 匹配且 Hardware Manager 无 mismatch；
- debug hub 和 ILA 可正常 arm / trigger / upload；
- `cplllock_sync = 1`；
- `tx_mmcm_locked_sync = 1`；
- `txresetdone_sync = 1`；
- `gt_ready = 1`；
- APPLY 后配置有效；
- ENABLE 后启动事件可见；
- `txusrclk2_freq_counter_axi` 或等价证据符合 31.25MHz 预期；
- ENABLE 后 `txdata/valid_mask` 有效。

本次初测已满足 GT/MMCM ready 与配置链路初步验证，但尚未满足精确频率计数和 `txdata/valid_mask` 有效窗口捕获这两项完整通过标准。

## 9. 不通过时的定位顺序

1. bit/LTX 是否同源。
2. debug hub 是否可用。
3. `cplllock_sync` 是否为 1。
4. `tx_mmcm_locked_sync` 是否为 1。
5. `gt_ready` / `txresetdone_sync` 是否恢复。
6. `txusrclk2_divided_debug` 是否有跳变。
7. `txusrclk2_alive_axi` 与频率计数是否符合预期。
8. APPLY/ENABLE 控制链路是否进入 PL。
9. TX 域 ILA 是否抓到发送窗口。

## 10. 本次上板初测记录

本次 2.000G static 上板已有以下证据：

![UDP SOFT_RESET / WRITE_CONFIG / SELECT_CONFIG / APPLY / ENABLE 返回 OK](../images/dynamic_rate/third_rate_2g_static/udp_2g_static_config_apply_enable_ok.png)

该图证明 UDP 控制命令链路已进入本次 2.000G static 测试流程，`SOFT_RESET`、`WRITE_CONFIG`、`SELECT_CONFIG`、`APPLY`、`ENABLE` 均返回 OK。

![AXI/FCLK ILA 显示配置有效、启动事件已见并完成](../images/dynamic_rate/third_rate_2g_static/ila_2g_static_axi_cfg_apply_enable_done.png)

该图显示 `cfg_valid=1`、`cfg_error=0`、`cfg_update_seen=1`、`engine_start_seen=1`、`pattern_valid=1`、`done_tx=1`，说明配置加载与 ENABLE 启动事件链路可用。

![GT/MMCM ready 与 txusrclk2 divided debug 周期性跳变](../images/dynamic_rate/third_rate_2g_static/ila_2g_static_gt_mmcm_ready_txusrclk2_divided_toggle.png)

该图显示 `cplllock_sync=1`、`tx_mmcm_locked_sync=1`、`txresetdone_sync=1`、`gt_ready_tx=1`，且 `txusrclk2_divided_debug` 有周期性跳变。该证据支持“GT/MMCM ready 已恢复，TXUSRCLK2 域存在活动”的判断，但不等同于精确验证 `TXUSRCLK2 = 31.25MHz`。

![TX 域窗口未捕获到 txdata / valid_mask，有待重新 trigger](../images/dynamic_rate/third_rate_2g_static/ila_2g_static_tx_domain_idle_after_enable_need_retrigger.png)

该图只用于说明当前 TX 域 ILA 窗口未捕获到有效 `txdata/valid_mask`。它不能作为发送有效证据；后续应重新 trigger 捕获有效发送窗口。

## 11. 当前结论

2G static build 已通过，2G static 上板初测显示 GT/MMCM ready 和配置链路可用；但尚未完成 txusrclk2 频率计数精确验证，也尚未捕获 txdata/valid_mask 有效发送窗口。当前证据支持继续后续 bring-up，但 2G 加入 dynamic profile table 前建议补充频率计数或等价证明。

本文仍不证明：

- `rate set 2000` 可用；
- 2G dynamic 切换通过；
- 2G 完整发送链路通过；
- 外部光口闭环、示波器或误码率验证完成。

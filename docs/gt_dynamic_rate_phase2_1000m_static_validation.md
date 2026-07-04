# GT 动态速率阶段二补充：1000M 单速率静态验证

> Superseded notice:
> 本报告保留为 1000M Profile1 static build 与早期 ILA 验证的详细历史记录。
> 当前正式阅读入口请优先查看：
> `docs/debug_reports/README_validation_report_reading_order.md`、
> `docs/debug_reports/00_current_validation_status.md`、
> `docs/debug_reports/02_profile1_1000m_static_build_and_debug_fix.md`、
> `docs/debug_reports/03_profile1_1000m_static_ila_validation_summary.md`。
> 本报告中的 1000M static 结论不得解释为动态 `rate set`、GTX DRP/MMCM DRP 或外部光口闭环已经完成。

## 1. 为什么先做 1000M 静态验证

阶段二前置设计包已经确认：500M 到 1000M 并不是只改 GTX `TXOUT_DIV=8 -> 4`。由于当前 64-bit 外部 TXDATA、无 8b/10b、内部 datapath 为 32-bit，1000M 静态配置下还必须同步改变 TX user clocking：

| 项目 | 500M Profile 0 | 1000M 静态 Profile 1 |
| --- | --- | --- |
| Line rate | 0.500 Gb/s | 1.000 Gb/s |
| TXDATA width | 64 bit | 64 bit |
| TX internal datawidth | 32 | 32 |
| Encoding | None | None |
| TXOUT_DIV | 8 | 4 |
| TXUSRCLK | 15.625 MHz | 31.25 MHz |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz |
| TXUSRCLK:TXUSRCLK2 | 2:1 | 2:1 |

因此本阶段先建立一个可独立综合、实现、出 bit/LTX 的 1000M 单速率静态分支，用于验证 1000M GT 参数、TX user clocking、timing、ILA 与现有 PS/Vitis 控制链路是否能独立工作。该阶段不是动态速率切换，不写 GTX DRP，不写 MMCM DRP，不接入 `laser_gt_rate_ctrl`。

## 2. 1000M GT Wizard 参数

1000M 对比 XCI 在隔离目录生成，未直接覆盖主工程 500M Profile 0 XCI：

```text
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/copied_ip/gtwizard_0.xci
```

已记录的 GT Wizard 关键属性如下：

| 参数 | 值 | 说明 |
| --- | --- | --- |
| `identical_val_tx_line_rate` | 1.0 | TX line rate 目标 1.000 Gb/s |
| `gt0_val_tx_line_rate` | 1.0 | TX line rate 1.000 Gb/s |
| `gt0_val_tx_data_width` | 64 | 外部 TXDATA 为 64 bit |
| `gt0_val_tx_int_datawidth` | 32 | GT 内部 TX datapath 为 32-bit 语义 |
| `gt0_val_encoding` | None | 无 8b/10b |
| `gt0_val_tx_reference_clock` | 125.000 | 使用本地 125 MHz REFCLK |
| `gt0_val_cpll_fbdiv_45` | 4 | CPLL 参数 |
| `gt0_val_cpll_fbdiv` | 4 | CPLL 参数 |
| `gt0_val_cpll_refclk_div` | 1 | CPLL 参数 |
| `gt0_val_cpll_txout_div` | 4 | 1000M TX 关键差异 |
| `gt0_val_cpll_rxout_div` | 4 | 生成结果中 RXOUT_DIV 也为 4 |
| `gt0_val_txusrclk` | TXOUTCLK | TX user clock 来源 |
| `gt0_val_port_tx8b10ben` | false | 无 8b/10b |

注意：属性报告中 `gt0_val_rx_line_rate` 读回仍显示为 `0.5`，但生成后的 `gtwizard_0_gt.v` 中 `RXOUT_DIV=4`、`TXOUT_DIV=4`。本阶段只声明并验证 TX 静态路径，不声明 RX 或全双工 1000M 已完成。

## 3. 1000M user clocking 参数

新增 1000M 专用 user clocking：

```text
laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile1_1000m.v
```

MMCM 参数按 1000M 静态目标设置：

| 参数 | 值 | 结果 |
| --- | --- | --- |
| `CLKIN1_PERIOD` | 32.0 ns | 输入 TXOUTCLK = 31.25 MHz |
| `CLKFBOUT_MULT_F` | 20.0 | VCO = 625 MHz |
| `DIVCLK_DIVIDE` | 1 | 输入分频不变 |
| `CLKOUT1_DIVIDE` | 20 | TXUSRCLK = 31.25 MHz |
| `CLKOUT0_DIVIDE_F` | 40.0 | TXUSRCLK2 = 15.625 MHz |

实现后 Vivado `report_clocks` 确认：

```text
TXOUTCLK          period = 32.000 ns, freq = 31.25 MHz
clkout1_txusrclk  period = 32.000 ns, freq = 31.25 MHz
clkout0_txusrclk2 period = 64.000 ns, freq = 15.625 MHz
```

## 4. 500M / 1000M clocking 对比

| 项目 | 500M Profile 0 | 1000M 静态 Profile 1 | 影响 |
| --- | --- | --- | --- |
| GT XCI | 主工程原始 `gtwizard_0.xci` | 隔离工程复制并改为 1000M | 500M 不被覆盖 |
| `TXOUT_DIV` | 8 | 4 | line rate 从 0.5G 到 1.0G |
| `TXOUTCLK` | 15.625 MHz | 31.25 MHz | MMCM 输入频率翻倍 |
| `TXUSRCLK` | 15.625 MHz | 31.25 MHz | GT 内部 32-bit 语义所需用户时钟 |
| `TXUSRCLK2` | 7.8125 MHz | 15.625 MHz | `laser_tx_core` 每拍 64-bit 运行频率翻倍 |
| `laser_tx_core` 数据宽度 | 64 bit | 64 bit | 不改业务数据通路 |
| 每拍发送语义 | 64 bit / TXUSRCLK2 | 64 bit / TXUSRCLK2 | 语义保持，节拍变快 |

## 5. 是否修改主工程 XCI

未直接覆盖当前已验证的 500M Profile 0 XCI。构建脚本使用 `save_project_as` 创建隔离 Vivado 工程，并在隔离工程中替换本地 `gtwizard_0.xci`。

Profile 0 回退保护检查结果：

```text
laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v:
RXOUT_DIV = 8
TXOUT_DIV = 8

主工程 XML:
gt0_val_tx_line_rate = 0.5
gt0_val_cpll_txout_div = 8
```

1000M 隔离工程检查结果：

```text
reports/gt_profile1_1000m_static/vivado_project/laser_tx_profile1_1000m.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v:
RXOUT_DIV = 4
TXOUT_DIV = 4
```

## 6. 是否生成 bitstream / ltx

已生成 1000M 静态 bitstream 与 LTX：

```text
reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

`impl_1/runme.log` 中记录：

```text
INFO: [Vivado 12-1842] Bitgen Completed Successfully.
write_bitstream completed successfully
```

说明：外层 PowerShell 调用曾因等待时间限制返回超时，但 Vivado 子进程继续完成 implementation/bitgen。最终结论以 `impl_1/runme.log`、生成的 bit/LTX 和 report 文件为准。

## 7. Timing 结果

已生成 timing summary：

```text
reports/gt_profile1_1000m_static/reports/timing_summary.rpt
```

关键结果：

| Metric | 1000M 静态实现结果 |
| --- | ---: |
| Setup WNS | 7.029 ns |
| Setup TNS | 0.000 ns |
| TNS failing endpoints | 0 |
| Hold WHS | 0.042 ns |
| Hold THS | 0.000 ns |
| THS failing endpoints | 0 |
| Timing summary | All user specified timing constraints are met |

利用率报告：

| Resource | Used | Utilization |
| --- | ---: | ---: |
| Slice LUTs | 20011 | 7.21% |
| Slice Registers | 18629 | 3.36% |
| Block RAM Tile | 43.5 | 5.76% |
| DSP | 0 | 0.00% |
| GTXE2_CHANNEL | 1 | 6.25% |
| BUFGCTRL | 5 | 15.63% |
| MMCME2_ADV | 1 | 12.50% |

## 8. bit / ltx 路径

推荐上板下载路径：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
```

隔离 Vivado 工程路径：

```text
D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/vivado_project/laser_tx_profile1_1000m.xpr
```

## 9. ILA probe

1000M 静态分支保留原有系统 ILA，并新增 GT Profile1 专用 ILA：

```text
ila_gt_profile1_1000m
```

新增 GT ILA 采样时钟为 1000M Profile1 的 `TXUSRCLK2 = 15.625 MHz`。probe 如下：

| Probe | 信号 | 宽度 | 目的 |
| --- | --- | ---: | --- |
| probe0 | `gt_ready_tx` | 1 | GT ready 状态 |
| probe1 | `cplllock_sync` | 1 | CPLL lock 状态 |
| probe2 | `txresetdone_sync` | 1 | TX reset done 状态 |
| probe3 | `tx_mmcm_locked_sync` | 1 | TX user clock MMCM lock |
| probe4 | `txusrclk2_divided_debug` | 1 | TXUSRCLK2 分频调试信号 |
| probe5 | `tx_word_count[23:0]` | 24 | TXUSRCLK2 域 word 计数 |
| probe6 | `txdata_in[63:0]` | 64 | GT 输入侧 64-bit TXDATA |
| probe7 | `valid_mask_in[63:0]` | 64 | 64-bit valid mask |

原有 `hw_ila_2 / ila_laser_tx` 仍用于观察 `laser_tx_core` 的 TX 域控制、`txdata[63:0]`、`valid_mask[63:0]`、`eom_out`、`soa_gate_out`、`acq_trig_out`、`acq_gate_out` 等信号。若上板时只看到新增 GT ILA 而未看到原有 ILA，应优先确认 bit/LTX 是否来自同一次实现。

## 10. 上板验证步骤

1. 在 Vivado Hardware Manager 下载 1000M 静态 bit/LTX：

   ```text
   D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.bit
   D:/FPGA_Learn/laser_tx/reports/gt_profile1_1000m_static/artifacts/laser_tx_board_top_profile1_1000m.ltx
   ```

2. 启动现有 Vitis app。软件协议不需要改变，仍使用固定 Profile 控制流程。

3. 执行 `READ_GT_STATUS`，确认：

   ```text
   cplllock=1
   txresetdone=1
   gt_ready=1
   tx_mmcm_locked=1
   ```

4. 执行 `WRITE_CONFIG` 写入 Direct63 / Direct127 / PRBS6 / PRBS7 任一有效发送配置。

5. 执行 `SELECT_CONFIG`。

6. 执行 `APPLY`。

7. 在 ILA 中触发 `cfg_update_pulse_tx == 1`，确认 `pattern_valid_tx=1` 且无 `cfg_error`。

8. 执行 `ENABLE`。

9. 在 ILA 中触发 `engine_start_tx == 1` 或 `busy_tx == 1`。

10. 观察：

    ```text
    txdata[63:0] 非零
    valid_mask[63:0] 有效
    busy_tx 拉高
    done_tx 最终置位
    eom_out / soa_gate_out / acq_trig_out / acq_gate_out 按测试场景变化
    ```

11. 用 ILA 或示波器观察 `txusrclk2_divided_debug`。该信号每 16 个 TXUSRCLK2 周期翻转一次，1000M 静态模式下：

    ```text
    TXUSRCLK2 = 15.625 MHz
    txusrclk2_divided_debug 方波频率约 15.625 MHz / 32 = 488.28125 kHz
    ```

## 10A. 1000M AXI/FCLK bring-up ILA 上板截图证据

本节补充用户本轮新增的 AXI/FCLK bring-up ILA 截图证据。该组截图用于证明 1000M Profile1 static 下 debug hub 已稳定、GT/MMCM/txusrclk2 alive 状态可在稳定 AXI/FCLK 域观察，并确认 APPLY / ENABLE 控制事件进入 PL。它与 txusrclk2 域 ILA 的作用不同：

```text
AXI/FCLK ILA：证明系统状态和控制链路；
txusrclk2 ILA：证明发送数据路径和 valid_mask 输出。
```

本次 ILA 波形对应的 UDP 配置命令为：

```text
SOFT_RESET
WRITE_CONFIG 0 0x5A 4 8 2 7 0 0 0x89ABCDEF 0x01234567 0x76543210 0x52A55AA5
SELECT_CONFIG 0 1 1
APPLY
ENABLE
```

![1000M UDP Direct127 gap8 repeat4 配置]()

配置含义如下：

```text
index = 0
seed = 0x5A
repeat_cycles = 4
gap_len_bits = 8
insert_after = 2
prbs_order = 7
phase_shift_en = 0
loop_en = 0
direct_source = 1
direct_len_127 = 1
```

即：127bit direct pattern，重复 4 次，第 2 次 pattern 后插入 8bit gap，不循环。实际 pattern 字段为：

```text
pattern_low  = 0x89ABCDEF
pattern_mid  = 0x01234567
pattern_high = 0x76543210
pattern_top  = 0x52A55AA5
```

### 10A.1 APPLY 前：GT ready 与 txusrclk2 alive

![APPLY 前 GT ready 与 txusrclk2 alive]()

图中对应 `SOFT_RESET + WRITE_CONFIG + SELECT_CONFIG` 后、`APPLY` 前。可以看到 GT/MMCM/txusrclk2 已经处于可工作状态：

```text
cplllock_sync = 1
txresetdone_sync = 1
tx_mmcm_locked_sync = 1
gt_ready_ctrl = 1
txusrclk2_alive_axi = 1
txusrclk2_freq_counter_axi 持续递增
```

此时 BRAM 配置已写入并已选择 index=0/direct127，但尚未 APPLY，因此 PL 发送域尚未加载新配置，这属于预期状态。

### 10A.2 APPLY 后：cfg_update_seen 与配置校验

![APPLY 后 cfg_update_seen]()

图中对应发送 `APPLY` 后。可以看到：

```text
APPLY toggle 已进入 PL
dbg_axi_cfg_update_seen = 1
dbg_axi_cfg_valid = 1
dbg_axi_cfg_error = 0
dbg_axi_pattern_valid = 1
dbg_axi_engine_start_seen = 0
```

结论是 `WRITE_CONFIG / SELECT_CONFIG / APPLY` 控制链路有效，配置已经被 PL 接收并校验通过。因为此时尚未 ENABLE，所以 `engine_start_seen = 0` 是正常现象。

### 10A.3 ENABLE 后：engine_start_seen 与启动链路

![ENABLE 后 engine_start_seen]()

图中对应发送 `ENABLE` 后。可以看到：

```text
GPIO enable bit 已置 1
dbg_axi_engine_start_seen = 1
dbg_axi_cfg_valid = 1
dbg_axi_cfg_error = 0
dbg_axi_pattern_valid = 1
GT/MMCM/txusrclk2 状态仍保持正常
```

结论是 ENABLE 控制已经进入 PL，`laser_tx_core` 的发送启动事件已经发生，PS/UDP -> AXI GPIO -> PL -> txusrclk2 域发送启动链路有效。

如果截图中 `busy_tx` 当前值为 0，不应判定失败。本次配置 `loop_en=0`，且 direct127 repeat4 gap8 是有限短序列，发送窗口很短，ILA cursor 位置可能已经落在发送结束后。因此 `busy_tx` 为瞬态状态，当前 cursor 位置为 0 不影响 `engine_start_seen=1` 的启动链路结论。

已有 txusrclk2 域图片：

```text
ila_apply_config_update.png
ila_apply_with_txdata_validmask.png
ila_enable_engine_start.png
ila_enable_txdata_validmask.png
```

其中 `ila_enable_txdata_validmask2.png` 仅作为后续建议命名/待归档项，当前未检测到实际文件，不在本报告中作为已有截图证据引用。

继续用于说明 txusrclk2 域 `txdata / valid_mask / engine_start / pattern_valid` 的进一步观察；本节新增的 3 张 AXI/FCLK 图只用于说明 bring-up 状态与控制链路，不扩大为外部光口闭环结论。

## 11. Profile 0 回退保护

本阶段采用隔离工程策略：

```text
reports/gt_profile1_1000m_static/vivado_project/
```

保护原则与检查结果：

| 项目 | 结果 |
| --- | --- |
| 是否覆盖主工程 500M XCI | 否 |
| 是否覆盖主工程 500M bit/LTX | 否 |
| 是否修改已验证 500M top | 否 |
| 是否修改 500M `laser_gt_usrclk_profile0.v` | 否 |
| 是否修改 `laser_tx_core` 功能逻辑 | 否 |
| Profile0 `TXOUT_DIV=8` | 已确认保持 |
| Profile1 `TXOUT_DIV=4` | 已确认生成 |

## 12. 当前仍未实现动态 rate set 的说明

本阶段只完成 1000M 单速率静态验证分支的构建与 timing/bitstream 生成。以下功能仍未实现：

```text
rate set 500/1000
GTX DRP 动态修改 TXOUT_DIV
MMCM DRP 动态重配置
laser_gt_rate_ctrl 接入
运行时 GT reset/lock/relock 状态机
多 profile 在线切换
```

现有 `rate status`、`rate plan <Mbps>` 仍可作为 dry-run / 规划查询；`rate set` 应继续返回不支持或保持禁用。

## 13. 当前验证结论

基于 Vivado 构建与报告文件，本轮完成了 1000M 单速率静态分支的工程搭建、综合、实现、timing 检查和 bit/LTX 生成。实现后确认：

```text
TXOUT_DIV = 4
TXOUTCLK  = 31.25 MHz
TXUSRCLK  = 31.25 MHz
TXUSRCLK2 = 15.625 MHz
Timing met
Bitstream generated
LTX generated
```

后续补充的 AXI/FCLK bring-up ILA 上板截图显示，1000M Profile1 static 在稳定 AXI/FCLK 域下已确认：

```text
GT/MMCM ready
txusrclk2 alive
APPLY 进入 PL
配置校验通过
ENABLE 进入 PL
发送启动事件发生
```

因此，本阶段可以分层写为：1000M Profile1 static 的 AXI/FCLK bring-up 状态与 APPLY/ENABLE 控制链路已获得 ILA 截图证据支撑。该结论不等价于 1000M 动态调速已经实现，也不表示 GTX DRP/MMCM DRP 已完成，更不声明外部光口链路已经闭环验证通过。

下一步应继续结合 txusrclk2 域 ILA 观察 `txdata[63:0] / valid_mask[63:0]`，并在需要时用示波器或外部链路手段验证外部同步/光口实际输出。1000M 静态上板验证失败前，不应继续动态速率切换。

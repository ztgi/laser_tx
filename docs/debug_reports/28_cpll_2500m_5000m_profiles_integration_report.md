# 125MHz REFCLK + CPLL：2500M / 5000M classic profile 集成报告

## 1. 本阶段目标与边界

本阶段继续推进 125MHz REFCLK + CPLL classic profile 扩展，但不一次性加入所有经典速率。基于当前已经完成的 500M / 1000M / 1250M / 2000M 动态切换基础，本轮优先评估并集成与 1250M 同一 CPLL 参数组的 2500M / 5000M 候选。

本轮实际集成结果为：

- 2500M 已加入 dynamic profile table；
- 5000M 未加入 supported profile，原因见第 4 节；
- 未引入 QPLL；
- 未引入 156.25MHz REFCLK；
- 未修改 AD9528 动态输出；
- 未修改 GT refclk 动态切换；
- 未修改 `laser_tx_core` 数据宽度或 `pattern_tx_engine` 功能逻辑。

## 2. 当前已验证基础

本轮修改建立在以下已有基础上：

| 已有基础 | 当前状态 |
|---|---|
| 500M / 1000M / 2000M dynamic profile | 已完成上板 UDP/ILA 阶段性验证 |
| 1250M CPLL 参数变化 profile | 已完成初步上板验证 |
| CPLL divider restore | 已修复并验证 0x1003 -> 0x1002 回切路径 |
| active/target CPLL 比较 | 已用于决定是否执行 CPLL DRP |
| reset / MMCM lock / GT ready sequence | 沿用已修复流程 |

因此，本轮不再复制 static board 工程，而是在已存在的 dynamic executor 中增加新的固定 profile。

## 3. 2500M / 5000M 候选参数分析

1250M、2500M、5000M 属于同一 125MHz REFCLK + CPLL 参数组：

| Profile | CPLL M/N1/N2 | CPLL DRP value | TXOUT_DIV | TXUSRCLK2 | 1ms counter 预期 |
|---|---:|---:|---:|---:|---:|
| 1250M | 1/4/5 | 0x1003 | 4 | 19.53125 MHz | 约 19531 |
| 2500M | 1/4/5 | 0x1003 | 2 | 39.0625 MHz | 约 39062 |
| 5000M | 1/4/5 | 0x1003 | 1 | 78.125 MHz | 约 78125 |

2500M 使用与 1250M 相同的 CPLL divider DRP value `0x1003`，只需将 TXOUT_DIV 从 4 切换为 2，并使用独立 MMCM DRP sequence 生成 78.125MHz TXUSRCLK 与 39.0625MHz TXUSRCLK2。

## 4. 为什么本轮没有加入 5000M

5000M 的预期 TXUSRCLK2 为 78.125MHz，按当前约 1ms 统计窗口，`txusrclk2_freq_counter_axi` 预期约为 78125，建议窗口为 76800..79500。

当前 RTL 中用于保存 profile 频率窗口的寄存器和函数返回值为 16-bit：

```verilog
reg [15:0] expected_min_count;
reg [15:0] expected_max_count;
function [15:0] profile_freq_min_count;
function [15:0] profile_freq_max_count;
```

虽然 `txusrclk2_freq_counter_axi` 本身是 32-bit，但 5000M 的窗口上限 79500 已超过 16-bit 最大值 65535。按照本阶段“不硬加不确定 profile”的原则，5000M 本轮不加入 `rate list`、不加入 `rate set` 支持，也不生成对应 profile id。

后续如果要支持 5000M，至少需要先有意扩宽 expected window 相关寄存器/函数，并重新评估 VERIFY_RATE、ILA probe、timing 和上板窗口。

## 5. 本轮 RTL 修改内容

修改文件：

```text
laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v
```

新增 2500M 固定 profile：

| 字段 | 2500M 值 |
|---|---:|
| rate_id | 5 |
| rate_mbps | 2500 |
| refclk_id | REFCLK_125M |
| refclk_freq_hz | 125000000 |
| pll_type | CPLL |
| CPLL M/N1/N2 | 1/4/5 |
| CPLL DRP value | 0x1003 |
| TXOUT_DIV | 2 |
| TXOUT_DIV encoding | 3'b001 |
| expected_txusrclk2_hz | 39062500 |
| freq window | 38400..39750 |
| MMCM sequence | `MMCM_DRP_SEQ_PROFILE4_2500M` |

CPLL DRP 是否执行仍然由 active/target CPLL 参数比较决定：

```text
target_cpll_drp_value != active_cpll_drp_value
```

因此：

- 1250M -> 2500M：CPLL value 都是 0x1003，可以跳过 CPLL DRP，仅切 TXOUT_DIV/MMCM；
- 2500M -> 1000M/2000M/500M：target CPLL value 为 0x1002，需要执行 CPLL restore；
- 1000M/2000M/500M -> 2500M：target CPLL value 为 0x1003，需要执行 CPLL DRP。

## 6. 2500M MMCM DRP sequence 来源

2500M 目标 user clocking：

| 项目 | 数值 |
|---|---:|
| TXOUTCLK | 78.125 MHz |
| TXUSRCLK | 78.125 MHz |
| TXUSRCLK2 | 39.0625 MHz |
| CLKFBOUT_MULT | 8 |
| DIVCLK_DIVIDE | 1 |
| CLKOUT0_DIVIDE | 16 |
| CLKOUT1_DIVIDE | 8 |

MMCM DRP 编码按 Xilinx `xvphy_mmcme2.c` 中的 MMCME2 divider/lock/filter 编码方式生成，并与现有 1000M / 1250M / 2000M 表的编码方式交叉核对。

2500M 新增 DRP 数据表：

| index | addr | data |
|---:|---:|---:|
| 0 | 0x28 | 0xffff |
| 1 | 0x14 | 0x1104 |
| 2 | 0x15 | 0x0000 |
| 3 | 0x16 | 0x1041 |
| 4 | 0x08 | 0x1208 |
| 5 | 0x09 | 0x0000 |
| 6 | 0x0a | 0x1104 |
| 7 | 0x0b | 0x0000 |
| 8 | 0x0c | 0x1041 |
| 9 | 0x0d | 0x00c0 |
| 10 | 0x18 | 0x01e8 |
| 11 | 0x19 | 0x5801 |
| 12 | 0x1a | 0x59e9 |
| 13 | 0x4e | 0x0800 |
| 14 | 0x4f | 0x0900 |

## 7. Vitis / UDP 修改内容

修改文件：

```text
vitis_bringup/bringup/src/gt_rate_plan.c
vitis_bringup/bringup/src/laser_gpio.h
vitis_bringup/bringup/src/laser_gt.c
vitis_bringup/bringup/src/laser_udp_server.c
vitis_bringup/bringup/src/main.c
```

软件侧变化：

- 新增 `LASER_RATE_ID_2500M = 5`；
- `rate set 2500` 映射到 profile id 5；
- `rate plan 2500` 返回 2500M 参数；
- `rate list` 输出 `500,1000,1250,2000,2500`；
- `rate status` mode 字符串更新为 `dynamic_500m_1000m_1250m_2000m_2500m`。

UDP 文本命令格式未改变；Vitis 仍只负责下发目标速率/profile id 和回读状态，不直接写 GT/MMCM DRP addr/data。

## 8. 构建结果

Vivado project-flow build 已完成：

```text
synth_1_STATUS = synth_design Complete!
impl_1_STATUS  = write_bitstream Complete!
```

Timing summary：

| Metric | Result |
|---|---:|
| WNS | 7.029 ns |
| TNS | 0.000 ns |
| WHS | 0.013 ns |
| THS | 0.000 ns |
| Timing conclusion | All user specified timing constraints are met |

Utilization：

| Resource | Used |
|---|---:|
| Slice LUTs | 22664 |
| Slice Registers | 21597 |
| Block RAM Tile | 61 |
| DSP | 0 |
| BUFGCTRL | 6 |
| MMCME2_ADV | 1 |

Debug core report 显示：

```text
dbg_hub
ila_laser_axi_cfg
ila_laser_tx
```

其中 `dbg_hub/clk = gt_ctrl_clk`，AXI/FCLK ILA 与 TX 域 ILA 结构保持存在。

## 9. 生成的本地 bit / LTX / report 路径

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_2500m_5000m_profiles/artifacts/laser_tx_board_top_dynamic_cpll_2500m_profile.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_2500m_5000m_profiles/artifacts/laser_tx_board_top_dynamic_cpll_2500m_profile.ltx
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_2500m_5000m_profiles/timing_summary_dynamic_cpll_2500m_profile.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_2500m_5000m_profiles/utilization_dynamic_cpll_2500m_profile.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_2500m_5000m_profiles/debug_cores_dynamic_cpll_2500m_profile.rpt
```

这些 bit/LTX/report 为本地生成产物，不应提交到 Git。

## 10. Vitis build 结果

Vitis bringup app 已通过 `Debug/makefile` clean/build。

```text
bringup.elf:
text = 147687
data = 3432
bss  = 3201088
dec  = 3352207
```

ELF strings 检查确认包含：

```text
LASER_RATE_ID_2500M 5U
OK RATE_LIST supported=500,1000,1250,2000,2500 refclk=125MHz pll=CPLL ad9528_dynamic=0 qpll=0
OK RATE_STATUS mode=dynamic_500m_1000m_1250m_2000m_2500m ...
```

## 11. 尚未完成的上板验证项

Hardware test was not run.

本轮只证明：

- 2500M profile 已完成 RTL/Vitis 集成；
- Vivado synthesis / implementation / bitstream 通过；
- Vitis ELF 已 clean build；
- bit/LTX 已生成。

尚未证明：

- `rate set 2500` 上板 DONE；
- 2500M 下 CPLL/MMCM/GT ready 恢复；
- 2500M 下 `txusrclk2_freq_counter_axi` 落入 38400..39750；
- 2500M 与 500M/1000M/1250M/2000M 之间多路径循环通过；
- 外部光口质量、BER 或长期稳定性。

## 12. 推荐上板验证顺序

Program 新 bit/LTX 后：

```text
rst -processor
run 新 bringup.elf
UDP PING
rate list
rate plan 2500
rate status
rate set 2500
rate status
rate set 1250
rate status
rate set 2500
rate status
rate set 1000
rate status
rate set 2500
rate status
rate set 500
rate status
rate set 2500
rate status
rate set 2000
rate status
```

ILA 重点观察：

- `target_rate_mbps = 2500`；
- `current_rate_mbps = 2500`；
- `rate_error_code = 0`；
- `gt_drp_write_attempted / gt_drp_done`；
- `mmcm_drp_write_attempted / mmcm_drp_done`；
- `target_cpll_drp_value / active_cpll_drp_value`；
- `tx_mmcm_locked_raw / tx_mmcm_locked_sync`；
- `txresetdone_sync`；
- `gt_ready`；
- `txusrclk2_freq_counter_axi` 是否落入 38400..39750。

## 13. 当前边界声明

即使后续 2500M 上板通过，也只能声明：

```text
新增 2500M 这一档 125MHz REFCLK + CPLL 参数变化 profile 的 dynamic 切换完成阶段性验证。
```

不能声明：

- 所有 125MHz CPLL classic profiles 均已支持；
- 5000M 已支持；
- 任意速率动态调速完成；
- 宽范围连续调速完成；
- QPLL 支持完成；
- 156.25MHz REFCLK 支持完成；
- AD9528 动态输出完成；
- 外部光口 BER / 长期稳定性通过。

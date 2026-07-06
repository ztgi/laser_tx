# 3.125G / 6.25G CPLL dynamic profile 集成报告

## 1. 本阶段目标与边界

本阶段在已经完成 500M / 1000M / 1250M / 2000M / 2500M / 5000M dynamic profile 的基础上，新增两个固定 profile：

- 3125M：125MHz REFCLK + CPLL + TXOUT_DIV=2；
- 6250M：125MHz REFCLK + CPLL + TXOUT_DIV=1。

本阶段只扩展固化 CPLL profile table，不实现任意连续速率，不引入 QPLL，不引入 156.25MHz REFCLK，不实现 AD9528 动态输出，不修改 `laser_tx_core` 数据宽度，不修改 `pattern_tx_engine`，也不改变既有 reset / lock / ready / VERIFY_RATE 执行链路。

## 2. 参数确认结果

3.125G 和 6.25G 采用同一组 CPLL 参数：

```text
REFCLK = 125 MHz
PLL    = CPLL
M      = 1
N1     = 5
N2     = 5
CPLLCLKOUT = 3.125 GHz
```

GT DRP 参数来源沿用前序 CPLL DRP map：

- CPLL divider DRP address：`0x05E`；
- CPLL divider mask：`0x1FFF`；
- M=1 编码：`5'h10`；
- N1=5 编码：`1'b1`；
- N2=5 编码：`7'h03`；
- 组合目标值：`0x1083`。

TXOUT_DIV DRP 仍使用 `0x088[6:4]`：

- 3125M：TXOUT_DIV=2，encoding=`3'b001`；
- 6250M：TXOUT_DIV=1，encoding=`3'b000`。

## 3. Profile table 对比

| Profile | rate_id | REFCLK | PLL | CPLL M/N1/N2 | CPLL DRP value | TXOUT_DIV | TXUSRCLK2 expected | freq counter window |
|---|---:|---:|---|---|---:|---:|---:|---:|
| 500M | 1 | 125MHz | CPLL | 1/4/4 | 0x1002 | 8 | 7.8125MHz | 7700..7950 |
| 1000M | 2 | 125MHz | CPLL | 1/4/4 | 0x1002 | 4 | 15.625MHz | 15400..15900 |
| 2000M | 3 | 125MHz | CPLL | 1/4/4 | 0x1002 | 2 | 31.25MHz | 30800..31800 |
| 1250M | 4 | 125MHz | CPLL | 1/4/5 | 0x1003 | 4 | 19.53125MHz | 19200..19850 |
| 2500M | 5 | 125MHz | CPLL | 1/4/5 | 0x1003 | 2 | 39.0625MHz | 38400..39700 |
| 5000M | 6 | 125MHz | CPLL | 1/4/5 | 0x1003 | 1 | 78.125MHz | 76800..79500 |
| 3125M | 7 | 125MHz | CPLL | 1/5/5 | 0x1083 | 2 | 48.828125MHz | 48000..49700 |
| 6250M | 8 | 125MHz | CPLL | 1/5/5 | 0x1083 | 1 | 97.65625MHz | 96000..99500 |

`current_rate` 和 active CPLL 状态仍只在 `VERIFY_RATE` 成功后更新；如果切换失败，保持 last-good 状态。

## 4. MMCM DRP sequence

MMCM DRP 表按工程既有转换方式生成，未手写不可追溯 magic number。

3125M 目标：

```text
TXOUTCLK = 97.65625 MHz
TXUSRCLK = 97.65625 MHz
TXUSRCLK2 = 48.828125 MHz
CLKFBOUT_MULT = 8
DIVCLK_DIVIDE = 1
CLKOUT0_DIVIDE = 16
CLKOUT1_DIVIDE = 8
```

3125M MMCM DRP sequence：

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

6250M 目标：

```text
TXOUTCLK = 195.3125 MHz
TXUSRCLK = 195.3125 MHz
TXUSRCLK2 = 97.65625 MHz
CLKFBOUT_MULT = 4
DIVCLK_DIVIDE = 1
CLKOUT0_DIVIDE = 8
CLKOUT1_DIVIDE = 4
```

6250M MMCM DRP sequence：

| index | addr | data |
|---:|---:|---:|
| 0 | 0x28 | 0xffff |
| 1 | 0x14 | 0x1082 |
| 2 | 0x15 | 0x0000 |
| 3 | 0x16 | 0x1041 |
| 4 | 0x08 | 0x1104 |
| 5 | 0x09 | 0x0000 |
| 6 | 0x0a | 0x1082 |
| 7 | 0x0b | 0x0000 |
| 8 | 0x0c | 0x1041 |
| 9 | 0x0d | 0x00c0 |
| 10 | 0x18 | 0x01e8 |
| 11 | 0x19 | 0x2c01 |
| 12 | 0x1a | 0x2de9 |
| 13 | 0x4e | 0x0800 |
| 14 | 0x4f | 0x9900 |

## 5. RTL 修改说明

修改文件：

- `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v`
- `laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v`

主要修改：

- 新增 `RATE_ID_3125M=7`、`RATE_ID_6250M=8`；
- 新增 profile table 入口；
- 新增 CPLL M/N1/N2 编码选择；
- 新增 3125M / 6250M MMCM DRP sequence；
- 新增 3125M / 6250M `expected_txusrclk2_hz` 与 frequency counter window；
- dry-run/debug rate decode 增加 3125M / 6250M 显示。

未修改：

- `laser_tx_core` 的发送数据路径；
- `pattern_tx_engine`；
- BRAM 配置格式；
- GT/MMCM reset sequence 主流程；
- `VERIFY_RATE` 更新 `current_rate` 的规则；
- GPIO rate_id bitfield 映射。

## 6. Vitis / UDP 修改说明

修改文件：

- `vitis_bringup/bringup/src/laser_gpio.h`
- `vitis_bringup/bringup/src/laser_gt.c`
- `vitis_bringup/bringup/src/gt_rate_plan.c`
- `vitis_bringup/bringup/src/laser_udp_server.c`
- `vitis_bringup/bringup/src/main.c`

主要修改：

- 新增 `LASER_RATE_ID_3125M=7`、`LASER_RATE_ID_6250M=8`；
- `rate set` / `rate plan` / `rate list` / `rate status` 相关显示支持 3125M 和 6250M；
- UDP 文本协议格式未变化；
- Vitis 仍只发送目标速率/profile_id，不直接下发 GT/MMCM DRP addr/data。

ELF 字符串检查已确认包含：

```text
OK RATE_LIST supported=500,1000,1250,2000,2500,3125,5000,6250 refclk=125MHz pll=CPLL ad9528_dynamic=0 qpll=0
Runtime rate set : CPLL_DYNAMIC_500M_1000M_1250M_2000M_2500M_3125M_5000M_6250M
```

## 7. Build / timing / utilization / debug core 结果

Vivado project flow 已执行：

```text
synth_1
impl_1
write_bitstream
write_debug_probes
report_timing_summary
report_utilization
report_debug_core -full_path
```

结果：

| 项目 | 结果 |
|---|---|
| synth_1 | `synth_design Complete!` |
| impl_1 | `write_bitstream Complete!` |
| bit | `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_3125m_6250m_profiles/artifacts/laser_tx_board_top_dynamic_cpll_3125m_6250m_profiles.bit` |
| ltx | `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_3125m_6250m_profiles/artifacts/laser_tx_board_top_dynamic_cpll_3125m_6250m_profiles.ltx` |
| Timing report | `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_3125m_6250m_profiles/timing_summary_dynamic_cpll_3125m_6250m_profiles.rpt` |
| Utilization report | `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_3125m_6250m_profiles/utilization_dynamic_cpll_3125m_6250m_profiles.rpt` |
| Debug core report | `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_3125m_6250m_profiles/debug_cores_dynamic_cpll_3125m_6250m_profiles.rpt` |

Timing：

| Metric | Result |
|---|---:|
| WNS | 7.029 ns |
| TNS | 0.000 ns |
| WHS | 0.046 ns |
| THS | 0.000 ns |

Vivado 报告显示：

```text
All user specified timing constraints are met.
```

Utilization：

| Resource | Used |
|---|---:|
| Slice LUTs | 22689 |
| Slice Registers | 21626 |
| Block RAM Tile | 61 |
| DSPs | 0 |
| GTXE2_CHANNEL | 1 |
| BUFGCTRL | 6 |
| MMCME2_ADV | 1 |

Debug core：

- `dbg_hub/clk = gt_ctrl_clk`；
- `ila_laser_axi_cfg/clk = u_system_wrapper/system_i/gt_ctrl_clk`；
- `ila_laser_tx/clk = u_system_wrapper/system_i/txusrclk2`；
- debug hub 下仍连接 2 个 ILA：`ila_laser_axi_cfg` 和 `ila_laser_tx`。

注意：当前 implemented timing report 中静态 `clkout0_txusrclk2` 仍显示为 128ns 约束模型。6250M 运行时 `TXUSRCLK2=97.65625MHz` 是否满足实际板上动态运行，必须通过上板 ILA frequency counter 和功能切换验证确认。当前 timing 结论只表示本次实现满足工程中已约束的静态 timing。

## 8. Vitis build 结果

Vitis bringup app 已 clean build：

```text
make clean
make all
```

ELF：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf
```

ELF size：

| section | size |
|---|---:|
| text | 148335 |
| data | 3432 |
| bss | 3201088 |
| dec | 3352855 |

`xparameters.h`、XSA、platform、BSP 未因本阶段修改发生接口级变化；本阶段只修改应用层 rate table / parser 文本和 PL 内部 profile table。

## 9. 尚未完成的上板验证

Hardware test was not run in this step.

本报告不能声明：

- `rate set 3125` 上板通过；
- `rate set 6250` 上板通过；
- 6250M 下 `TXUSRCLK2=97.65625MHz` 已经由 ILA 精确验证；
- 6250M 下 `laser_tx_core` 数据路径长期稳定；
- 外部光口链路质量、BER 或长期稳定性通过。

后续上板建议顺序：

```text
Program dynamic CPLL 3125M/6250M bit + ltx
rst -processor
run new ELF
UDP PING
rate list
rate plan 3125
rate set 3125
rate status
rate plan 6250
rate set 6250
rate status
rate set 1000
rate status
```

ILA 重点观察：

- `target_rate_mbps`；
- `current_rate_mbps`；
- `rate_state`；
- `rate_error_code`；
- `gt_drp_addr/di/do/en/we/rdy`；
- `gt_drp_readback_value`；
- `mmcm_drp_addr/di/do/en/we/rdy`；
- `tx_mmcm_locked_raw/sync`；
- `txresetdone_sync`；
- `gt_ready`；
- `txusrclk2_freq_counter_axi`。

建议截图路径：

```text
docs/images/dynamic_rate/cpll_3125m_6250m_profiles/udp_cpll_3125m_6250m_rate_set_pass.png
docs/images/dynamic_rate/cpll_3125m_6250m_profiles/ila_cpll_3125m_done_lock_ready_freq.png
docs/images/dynamic_rate/cpll_3125m_6250m_profiles/ila_cpll_6250m_done_lock_ready_freq.png
```

## 10. 当前边界声明

本阶段新增的是两个固定 CPLL profile，不是宽范围连续动态调速。

仍不支持：

- 任意速率；
- QPLL；
- 156.25MHz REFCLK；
- AD9528 动态输出；
- GT refclk 动态切换；
- 外部光口质量 / BER / 长期稳定性证明。

6250M 是当前 profile 中最高 `TXUSRCLK2` 频率，后续必须优先用 ILA frequency counter 和实际发送窗口验证其运行裕量；若出现 timing 或功能异常，应优先回退到已验证的 500M/1000M/1250M/2000M/2500M/5000M profile。

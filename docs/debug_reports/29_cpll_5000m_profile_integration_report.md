# 5000M CPLL dynamic profile 集成报告

## 1. 本阶段目标与边界

本阶段目标是在已经完成 500M / 1000M / 1250M / 2000M / 2500M dynamic profile 的基础上，将 5000M 作为新的 125MHz REFCLK + CPLL 固化 profile 加入现有 dynamic rate executor。

本阶段只支持固定 profile：

```text
500M / 1000M / 1250M / 2000M / 2500M / 5000M
```

本阶段不实现：

- 任意速率；
- 宽范围连续调速；
- QPLL；
- 156.25MHz REFCLK；
- AD9528 动态输出；
- GT refclk 动态切换；
- laser_tx_core 数据宽度修改；
- pattern_tx_engine 修改；
- 外部光口质量 / BER / 长期稳定性验证。

## 2. 修改前 read-only 核查结果

修改前先检查了当前 RTL / Vitis / 文档中的 5000M 相关阻塞点。

| 项目 | 核查结果 | 结论 |
|---|---|---|
| `txusrclk2_freq_counter_axi` | `laser_gt_tx_profile0.v` 中为 32-bit 计数器，AXI ILA probe 也是 32-bit | 计数器本体可表达 5000M 约 78125 的 1ms 统计值 |
| `expected_min_count` / `expected_max_count` | `laser_gt_rate_switch_500m_1000m.v` 中为 16-bit | 不能表达 5000M 初始窗口 76800..79500 |
| profile accessor 返回宽度 | `profile_freq_min_count()` / `profile_freq_max_count()` 返回 16-bit | 需要扩宽 |
| VERIFY_RATE 比较 | 当前比较为 `{16'd0, expected_*}` | 16-bit 窗口会截断 5000M |
| Vitis plan window 字段 | `GtRatePlan.expected_txusrclk2_freq_min/max` 为 `uint32_t` | 软件侧可表达 >65535 |
| TXOUT_DIV=1 encoding | 既有报告记录 `XVphy_DrpEncodeCpllTxRxD()`：OUT_DIV=1 -> encoding 0 | 可追溯，不是盲猜 |

因此，本轮最小必要修改是：先扩宽硬件 frequency window path，再加入 5000M profile。

## 3. 5000M profile 参数

5000M 使用当前 125MHz REFCLK 与 CPLL，不引入 AD9528、QPLL 或 refclk 切换。

| 字段 | 5000M profile |
|---|---:|
| rate_id | 6 |
| rate_mbps | 5000 |
| REFCLK | 125MHz |
| PLL | CPLL |
| CPLL M / N1 / N2 | 1 / 4 / 5 |
| CPLL divider DRP value | `0x1003` |
| TXOUT_DIV | 1 |
| TXOUT_DIV encoding | `3'b000` |
| TXOUTCLK | 156.25MHz |
| TXUSRCLK | 156.25MHz |
| TXUSRCLK2 | 78.125MHz |
| txusrclk2 1ms counter 预期 | 约 78125 |
| 初始窗口 | 76800..79500 |
| AD9528 dynamic required | 0 |
| QPLL required | 0 |

TXOUT_DIV 编码依据来自已有 DRP 确认报告：

```text
GTXE2_CHANNEL TXOUT_DIV DRP address = 0x088
TXOUT_DIV bitfield = [6:4]
OUT_DIV=1 -> encoding 0
OUT_DIV=2 -> encoding 1
OUT_DIV=4 -> encoding 2
OUT_DIV=8 -> encoding 3
```

## 4. MMCM DRP sequence 来源

5000M 的目标 user clocking 为：

```text
TXOUTCLK  = 156.25MHz
TXUSRCLK  = 156.25MHz
TXUSRCLK2 = 78.125MHz
```

本轮没有手写不可追溯的 magic number，而是沿用当前工程已有的 Xilinx VPHY `MMCME2` DRP encoding 方法。5000M 采用：

| MMCM 参数 | 值 |
|---|---:|
| CLKIN period | 6.4ns |
| CLKFBOUT_MULT | 4 |
| DIVCLK_DIVIDE | 1 |
| CLKOUT0_DIVIDE | 8 |
| CLKOUT1_DIVIDE | 4 |
| CLKOUT2_DIVIDE | 1 |
| VCO | 625MHz |

新增 sequence：

```text
MMCM_DRP_SEQ_PROFILE5_5000M
```

写表如下：

| index | addr | data | 含义 |
|---:|---:|---:|---|
| 0 | `0x28` | `0xffff` | power/config mask |
| 1 | `0x14` | `0x1082` | CLKFBOUT_MULT=4 low word |
| 2 | `0x15` | `0x0000` | CLKFBOUT_MULT=4 high word |
| 3 | `0x16` | `0x1041` | DIVCLK_DIVIDE=1 |
| 4 | `0x08` | `0x1104` | CLKOUT0_DIVIDE=8 |
| 5 | `0x09` | `0x0000` | CLKOUT0 high word |
| 6 | `0x0a` | `0x1082` | CLKOUT1_DIVIDE=4 |
| 7 | `0x0b` | `0x0000` | CLKOUT1 high word |
| 8 | `0x0c` | `0x1041` | CLKOUT2_DIVIDE=1 |
| 9 | `0x0d` | `0x00c0` | CLKOUT2 high word |
| 10 | `0x18` | `0x01e8` | LOCK reg1 for mult=4 |
| 11 | `0x19` | `0x2c01` | LOCK reg2 for mult=4 |
| 12 | `0x1a` | `0x2de9` | LOCK reg3 for mult=4 |
| 13 | `0x4e` | `0x0800` | FILTER reg1 |
| 14 | `0x4f` | `0x9900` | FILTER reg2 for mult=4 |

## 5. RTL 修改内容

修改文件：

- `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v`
- `laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v`

主要修改：

1. 新增 `RATE_ID_5000M = 4'd6`；
2. 新增 `MMCM_DRP_SEQ_PROFILE5_5000M`；
3. 新增 5000M 的 profile accessor：
   - `profile_rate_mbps()`;
   - `profile_mmcm_drp_seq_id()`;
   - `profile_txout_div_enc()`;
   - `profile_cpll_fbdiv_enc()`;
   - `profile_expected_txusrclk2_hz()`;
   - `profile_freq_min_count()` / `profile_freq_max_count()`；
4. 将 `expected_min_count` / `expected_max_count` 从 16-bit 扩展为 24-bit；
5. VERIFY_RATE 比较改为使用 24-bit 窗口扩展到 32-bit 后与 `txusrclk2_freq_counter_axi[31:0]` 比较；
6. 新增 `mmcm_data_5000m()`；
7. `laser_tx_core` 中仅补充 AXI 侧 debug/dry-run rate decode 的 2500M / 5000M 显示与合法 ID 判断，不修改发送数据路径。

## 6. Vitis / UDP 修改内容

修改文件：

- `vitis_bringup/bringup/src/gt_rate_plan.c`
- `vitis_bringup/bringup/src/laser_gpio.h`
- `vitis_bringup/bringup/src/laser_gt.c`
- `vitis_bringup/bringup/src/laser_udp_server.c`
- `vitis_bringup/bringup/src/main.c`

主要修改：

1. 新增 `LASER_RATE_ID_5000M = 6`；
2. `laser_rate_id_from_mbps()` 支持 `rate set 5000`；
3. `laser_gt_rate_id_to_mbps()` 支持 rate_id 6；
4. `rate list` 输出新增 5000；
5. `rate status` mode string 更新为 `dynamic_500m_1000m_1250m_2000m_2500m_5000m`；
6. `gt_rate_plan_table` 新增 5000M plan；
7. UDP 命令格式未改变。

## 7. build / timing / utilization / debug 结果

执行脚本：

```text
scripts/run_dynamic_cpll_5000m_profile_project_flow.tcl
```

Vivado 结果：

| 项目 | 结果 |
|---|---|
| synth_1 | `synth_design Complete!` |
| impl_1 | `write_bitstream Complete!` |
| bitstream | 已生成 |
| LTX | 已生成 |
| timing WNS | 7.029ns |
| timing TNS | 0.000ns |
| WHS | 0.007ns |
| THS | 0.000ns |
| timing summary | `All user specified timing constraints are met.` |

本地 artifact：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_5000m_profile/artifacts/laser_tx_board_top_dynamic_cpll_5000m_profile.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_5000m_profile/artifacts/laser_tx_board_top_dynamic_cpll_5000m_profile.ltx
```

报告文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_5000m_profile/timing_summary_dynamic_cpll_5000m_profile.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_5000m_profile/utilization_dynamic_cpll_5000m_profile.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_5000m_profile/debug_cores_dynamic_cpll_5000m_profile.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_cpll_5000m_profile/clocks_dynamic_cpll_5000m_profile.rpt
```

资源摘要：

| 资源 | 使用量 |
|---|---:|
| Slice LUTs | 22788 |
| Slice Registers | 21607 |
| Block RAM Tile | 61 |
| DSPs | 0 |
| GTXE2_CHANNEL | 1 |
| MMCME2_ADV | 1 |
| BUFGCTRL | 6 |

Debug core 摘要：

| Debug core | clock | 说明 |
|---|---|---|
| `dbg_hub` | `gt_ctrl_clk` | 稳定 AXI/FCLK debug hub clock |
| `ila_laser_axi_cfg` | `u_system_wrapper/system_i/gt_ctrl_clk` | AXI/FCLK 域 rate/debug ILA，包含 `txusrclk2_freq_counter_axi[31:0]` |
| `ila_laser_tx` | `u_system_wrapper/system_i/txusrclk2` | TXUSRCLK2 域发送数据 ILA |

注意：当前 Vivado static timing report 中 `clkout0_txusrclk2` 仍显示为 128ns / 7.8125MHz 静态约束，这是工程初始 500M 配置的静态 clock model。上述 timing 通过表示“当前工程已约束路径满足现有约束”，不等价于已经用 STA 完整证明 5000M runtime `TXUSRCLK2=78.125MHz` 下的长期硬件稳定性。5000M 仍必须通过上板 ILA / `txusrclk2_freq_counter_axi` / 发送链路实测继续确认。

## 8. Vitis build 结果

执行：

```text
cd D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug
make clean
make all
```

结果：

```text
bringup.elf build passed
text=147903 data=3432 bss=3201088 dec=3352423
```

ELF 路径：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf
```

ELF size：

```text
905824 bytes
```

`arm-none-eabi-strings` 已确认 ELF 中包含：

```text
CPLL_DYNAMIC_500M_1000M_1250M_2000M_2500M_5000M
OK RATE_LIST supported=500,1000,1250,2000,2500,5000
OK RATE_PLAN ...
ERROR unsupported_rate ...
LASER_RATE_ID_5000M 6U
```

## 9. 上板验证计划

当前尚未执行 5000M 上板验证。下一步建议：

1. Program matching bit/LTX：
   - `laser_tx_board_top_dynamic_cpll_5000m_profile.bit`
   - `laser_tx_board_top_dynamic_cpll_5000m_profile.ltx`
2. `rst -processor`；
3. run 新 `bringup.elf`；
4. UDP `PING`；
5. UDP `rate list`；
6. UDP `rate plan 5000`；
7. UDP `rate set 5000`；
8. UDP `rate status`；
9. 回切验证：
   - `rate set 2500`
   - `rate set 1250`
   - `rate set 1000`
   - `rate set 500`
   - `rate set 2000`
10. 循环验证：
    - `500 -> 1000 -> 1250 -> 2500 -> 5000 -> 2500 -> 1250 -> 1000 -> 500`

ILA 重点观察：

- `target_rate_mbps=5000`；
- `current_rate_mbps=5000`；
- `rate_state=RATE_DONE`；
- `rate_error_code=NONE`；
- `gt_drp_write_attempted=1`；
- `mmcm_drp_write_attempted=1`；
- `gt_drp_addr=0x05E/0x088`；
- `gt_drp_readback_value`；
- `tx_mmcm_locked_raw/sync=1`；
- `txresetdone_sync=1`；
- `gt_ready=1`；
- `txusrclk2_freq_counter_axi` 进入 76800..79500 初始窗口。

建议截图路径：

```text
docs/images/dynamic_rate/cpll_5000m_profile/udp_cpll_5000m_rate_set_done.png
docs/images/dynamic_rate/cpll_5000m_profile/udp_cpll_5000m_loop_pass.png
docs/images/dynamic_rate/cpll_5000m_profile/ila_cpll_5000m_done_lock_ready_freq.png
docs/images/dynamic_rate/cpll_5000m_profile/ila_cpll_5000m_cpll_mmcm_drp_detail.png
```

## 10. 当前结论

本轮已完成 5000M CPLL dynamic profile 的代码集成、Vivado project-flow build、bit/LTX 生成、timing/util/debug report 导出，以及 Vitis `bringup.elf` clean build。5000M profile 使用 125MHz REFCLK + CPLL，CPLL divider value 为 `0x1003`，TXOUT_DIV=1，MMCM DRP sequence 已按现有 Xilinx VPHY MMCME2 encoding 方法加入。

但当前还没有完成 5000M 上板验证，因此不能声明：

- 5000M dynamic 切换已上板通过；
- 5000M 外部光口链路质量通过；
- 任意速率或宽范围动态调速完成；
- QPLL / 156.25MHz / AD9528 动态输出支持完成；
- 长期稳定性或 BER 通过。

当前可进入下一步 5000M 上板 bring-up，但应以 UDP + AXI/FCLK ILA + TX 域 ILA 证据为准。

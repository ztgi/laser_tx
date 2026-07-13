# AD9528 OUT0 实际频率 ILA 测量路径实现报告

## 1. 修改摘要

本阶段将 AD9528 OUT0 的 Bank110 差分输入接入主工程的只读频率测量路径：

```text
AA8/AA7 (Bank110 MGTREFCLK0)
-> IBUFDS_GTE2.ODIV2
-> BUFG
-> 32-bit 自由运行计数器
-> 源域寄存 Gray code
-> 2FF Gray CDC
-> 50MHz gt_ctrl_clk 域 1ms delta
-> 独立 AXI/FCLK ILA
```

测量逻辑不反馈功能路径，未把 `IBUFDS_GTE2.O` 接入 Bank111 GT，也未修改 GT profile、RATE_ID、supported list、CPLL/QPLL/MMCM DRP 或普通 `rate set` 行为。

## 2. 修改前问题

此前只有 AD9528 candidate 寄存器 readback，可证明配置值已经写入，却不能证明 OUT0 引脚实际存在 122.88MHz 时钟。隔离 route probe 也没有形成可下载主工程 bit/LTX 和 ILA 观测链路，因此 `measured_out0_hz` 必须保持 UNKNOWN。

## 3. 修改后结构

### 3.1 输入和专用时钟路径

顶层新增 `ad9528_ref0_clk_p/n`，分别约束到 AA8/AA7。差分输入使用 `IBUFDS_GTE2`；`ODIV2` 经 BUFG 形成 fabric 测量时钟，直通 `O` 只接未使用网，不接 Bank111。未使用普通 IBUFDS，也未设置 `CLOCK_DEDICATED_ROUTE FALSE`。

根据 7-series `IBUFDS_GTE2` 语义，ODIV2 为输入频率的二分频。candidate 配置为 OUT0=122.88MHz 时，预期 ODIV2=61.44MHz。

### 3.2 计数和 CDC

ODIV2 域运行 32-bit 自由计数器，并在源域寄存下一计数值对应的 Gray code，避免组合 XOR 毛刺直接进入 CDC。Gray bus 经带 `ASYNC_REG` 属性的两级寄存器同步到 50MHz `gt_ctrl_clk` 域，再解码为二进制。

`gt_ctrl_clk` 域每 50,000 周期取一次 delta，窗口为 1ms。第一次窗口只用于建立基线，从第二个完整窗口开始置 `ad9528_measure_valid_axi=1`。

### 3.3 测量判定

预期计数和初始窗口为：

| 项目 | 数值 |
| --- | ---: |
| OUT0 配置目标 | 122,880,000Hz |
| ODIV2 预期 | 61,440,000Hz |
| gt_ctrl_clk | 50,000,000Hz |
| 测量窗口 | 1ms（50,000周期） |
| 预期 delta | 61,440 |
| 初始有效窗口 | 60,000～62,900 |

RTL 不执行频率除法；ILA 直接显示 ODIV2 delta，OUT0 频率按两倍换算。

### 3.4 ILA

通过 implementation pre-hook 插入独立 `ila_ad9528_out0_measure`，不修改 BD 内原有 ILA。ILA 时钟保持稳定的 `gt_ctrl_clk`，深度 2048，probe 为：

| Probe | 信号 | 位宽 |
| --- | --- | ---: |
| probe0 | `ad9528_odiv2_alive_axi` | 1 |
| probe1 | `ad9528_odiv2_toggle_axi` | 1 |
| probe2 | `ad9528_odiv2_count_axi` | 32 |
| probe3 | `ad9528_odiv2_in_range_axi` | 1 |
| probe4 | `ad9528_measure_valid_axi` | 1 |

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| Bank110 OUT0 输入 | 主工程未接入 | AA8/AA7 顶层差分输入 | 新增只读输入 |
| 时钟 buffer | 无 | IBUFDS_GTE2 ODIV2 + BUFG | 专用合法路径 |
| 频率测量 | 无 | 32-bit Gray CDC、1ms delta | 只读 debug |
| CDC | 无主工程路径 | 源域寄存 Gray + 2FF | AXI/FCLK 域观测 |
| ILA | 无 OUT0 计数 probe | 独立 5-probe ILA | 原 BD ILA 不变 |
| Bank111 GT refclk | 原有 125MHz结构 | 未修改 | 功能不变 |
| GT profile / rate | 现有11档 | 未修改 | 功能不变 |
| pipeline/接口延迟 | 不适用 | 功能数据路径未增加 pipeline | 无功能影响 |

## 5. 接口、BD、时钟与板级一致性

- 新增顶层输入：`ad9528_ref0_clk_p/n`；没有删除、重命名或改变其他端口。
- `report_io` 确认 P/N 分别为 AA8/AA7、`MGTREFCLK0P_110/MGTREFCLK0N_110`。
- 未设置普通 IO `IOSTANDARD`，由专用 MGT reference-clock input primitive 接收。
- BD 未修改，HDL wrapper 未重新生成，AXI 地址映射未修改。
- XSA / Platform / BSP dependency unchanged。
- Clock/reset behavior changed intentionally：仅新增独立 ODIV2 测量时钟域；功能 GT 时钟、复位和速率执行器不变。
- 新增时钟只与 `gt_ctrl_clk` 通过明确 Gray CDC 相交；pre-hook 对这两个具体时钟域设置 asynchronous clock group，没有添加宽泛 false path。

## 6. 功能等价性说明

Expected system behavior unchanged。该结论基于代码结构检查和 Vivado build：测量结果只连接 debug ILA，不参与 GT refclk 选择、reset、DRP、rate controller、TX data/valid 或 Vitis 状态路径。

- 数据/valid 对齐：未修改；
- start/end、trigger、reset sequence：未修改；
- rate state/current/target：未修改；
- CPLL/QPLL 和 MMCM：未修改；
- GPIO/AXI/UDP：未修改；
- Bank111 GT 输入结构：实现检查未发现新增 `GTNORTHREFCLK0` 网络。

## 7. Build、实现和调试核查

执行：

```text
vivado -mode batch -source scripts/run_ad9528_out0_measurement_build.tcl
```

结果：

- `synth_1`: complete；
- `impl_1`: `write_bitstream Complete!`；
- bitstream 和 debug probes 成功生成；
- route status：0 routing errors；
- DRC：0 errors，未出现 UCIO-1、NSTD-1、Bank/VCCO 或 MGT refclk routing error；
- `IBUFDS_GTE2=u_ad9528_out0_ibufds_gte2`；
- `ODIV2_BUFG=u_ad9528_out0_odiv2_bufg`；
- `ila_ad9528_out0_measure` 为 implemented/inserted，时钟为 `gt_ctrl_clk`；
- build 中仍有既有/工具生成的 PDCN-1569 和 RTSTAT-10 warnings，本阶段未将其误写为 AD9528 路由错误。

本地生成物：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

bit/LTX 不提交 Git。

## 8. QoR / timing

| Metric | 首轮（CDC未分组） | 最终 | 说明 |
| --- | ---: | ---: | --- |
| Setup WNS | -4.531ns | 7.029ns | 首轮唯一违例为异步 ODIV2→FCLK CDC |
| Setup TNS | -144.550ns | 0.000ns | 最终通过 |
| Setup failing endpoints | 33 | 0 | 最终通过 |
| Hold WHS | 0.054ns | 0.044ns | 通过 |
| Hold THS | 0.000ns | 0.000ns | 通过 |
| LUT | 未作为正式基线 | 23,927 | 当前实现 |
| FF | 未作为正式基线 | 23,290 | 当前实现 |
| IBUFDS_GTE2 | 1个GT基线输入 | 2 | 新增Bank110测量输入 |
| BUFG | 6 | 7 | 新增ODIV2 BUFG |

首轮负 WNS 来自把异步 Gray CDC 当同步路径分析；最终只对 ODIV2 与 FCLK 两个具体域设置异步关系，域内路径继续正常计时。当前 122.88MHz 输入约束为本 candidate 的目标约束，不代表以后任意 OUT0 profile 的最终约束。

## 9. 上板测量结果

用户已在 2026-07-13 执行：

```text
ad9528 candidate set vcxo_122p88
```

UDP返回：

```text
OK AD9528_CANDIDATE_SET profile=VCXO_122P88
state=READY_UNMEASURED
configured_out0_hz=122880000
runtime_active_likely=1
measured_out0_hz=UNKNOWN
vcxo_status_ok=1
readback_ok=1
config_writes=7
io_update_writes=1
board_verified=0
```

该结果说明 candidate 的七项寄存器写入、IO_UPDATE、masked readback 和 VCXO status 均已通过。但 ILA 中 `ad9528_odiv2_count_axi` 显示为：

```text
82883
```

按当前 RTL 的 1ms 统计窗口换算：

| 项目 | 预期 | 实测/推算 | 说明 |
| --- | ---: | ---: | --- |
| ODIV2 count | 61,440 | 82,883 | 未落入 60,000～62,900 窗口 |
| ODIV2 frequency | 61.44MHz | 82.883MHz | 假设窗口为1ms |
| OUT0 frequency | 122.88MHz | 165.766MHz | 假设 ODIV2=OUT0/2 |

因此，本轮上板结果不是 `OUT0=122.88MHz` 的通过证据。它只证明：AD9528 candidate 写入状态已经到达 `READY_UNMEASURED`，同时 FPGA 侧确实通过 Bank110 `IBUFDS_GTE2.ODIV2` 观测到了一个持续时钟，但该时钟频率与 `VCXO_122P88` 目标不一致。

当前必须保持：

```text
measured_out0_hz=UNKNOWN
board_verified=0
```

不得将该 candidate 接入 Bank111 GT，也不得将其作为 GT 细步进参考时钟来源。

## 9.1 失败定位建议

下一步不应修改 GT profile 或 Bank111 参考时钟。建议先补三项最小证据：

1. 在同一 ILA 窗口确认 `ad9528_measure_valid_axi=1`、`ad9528_odiv2_alive_axi=1`、`ad9528_odiv2_in_range_axi=0`，并确认 count 是否稳定在约 82883。
2. 执行 `ad9528 candidate restore` 后再次抓取 ILA，确认 count 是否离开约 82883；如果 restore 后仍稳定为 82883，说明当前 OUT0 测量点可能没有被该 candidate profile 控制，或OUT0原本已有其它时钟源。
3. 在 candidate set 后保存 `ad9528 dump` 中 `0x0108/0x0109/0x0300/0x0301/0x0302/0x0500/0x0501/0x0503/0x0508/0x0509` 的真实值，用于复核 source/divider/power/status 位域。

若 82883 稳定复现，后续应优先复核 AD9528 OUT0 source encoding、divider encoding、VCXO input/source path 和 `IBUFDS_GTE2.ODIV2` 换算关系。不能仅凭 `configured_out0_hz=122880000` 继续推进。

## 10. 修改文件

| 文件 | 修改 |
| --- | --- |
| `rtl/laser_tx_board_top.v` | Bank110输入、IBUFDS_GTE2/BUFG、Gray CDC计数器 |
| `constraints/laser_tx_board_io.xdc` | AA8/AA7和122.88MHz输入约束 |
| `scripts/add_ad9528_out0_measurement_ila.tcl` | 插入独立5-probe ILA |
| `scripts/gt_profile0_impl_pre.tcl` | 精确CDC分组并调用ILA插入脚本 |
| `scripts/run_ad9528_out0_measurement_build.tcl` | clean build和报告输出 |
| `docs/debug_reports/ad9528_out0_frequency_measurement_report.md` | 本报告 |

## 11. 风险与边界

Oscilloscope hardware validation was not run。ILA measurement was run, but did not match the expected 122.88MHz candidate result。

因此当前只能声明测量路径 build、routing、DRC、timing 和 bit/LTX 生成通过，且 ILA 已观测到一个与预期不一致的 OUT0/ODIV2 时钟。不能声明：

- OUT0 已实测为122.88MHz；
- ODIV2 上板计数已经约61440；
- candidate 已成为 `board_verified`；
- `measured_out0_hz` 已知；
- OUT0 已接入 Bank111 GT；
- 新的 GT line-rate profile 已支持。

下一步必须先闭环 82883 这一异常计数的来源。只有实际 ODIV2 计数与预期一致，或重新定义并验证正确的 AD9528 OUT0 profile 后，才能进入测量值回读或 Bank110→Bank111 GTNORTHREFCLK0 的后续独立阶段。

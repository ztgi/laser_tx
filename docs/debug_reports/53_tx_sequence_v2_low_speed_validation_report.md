# 53. TX Sequence V2 低速功能验证报告

## 1. 本阶段目标

本阶段对协议不兼容的 TX Sequence V2 做低速功能收口，重点检查：

- 16-word record、CRC32 与 header-last 原子提交；
- `WRITE_CONFIG` 可变 gap 参数和 `SELECT_CONFIG <index>`；
- 每 phase 的 HEAD；
- N 个 pattern 与 N-1 个独立 gap；
- repeat 每次从 phase 初始 offset 重新开始；
- phase 扫描和 global pattern index；
- 每个任务最多一次 EOM，loop 不重复 EOM；
- 500M/1000M/2000M 的 EOM clock、K 和 tick；
- reset/abort/clock unsafe 时 EOM 安全拉低。

本阶段不进行 timing closure，不把当前结果作为 release/signoff，也不执行
hardware test。

## 2. Git 与 refresh 前快照

分支为 `feature/tx-sequence-v2`，基线 HEAD 为
`f1cd83e39911baf2485f8b884be2dbc3464eb66d`。V2 开发修改已在工作区内，
因此报告明确记录 `git_dirty=true`。

refresh 前保存：

- `reports/pre_refresh_status.txt`
- `reports/pre_refresh_diff_stat.txt`
- `reports/pre_refresh_name_status.txt`
- `reports/pre_refresh_route/laser_tx_board_top_routed.dcp`
- `reports/pre_refresh_route/laser_tx_board_top_timing_summary_routed.rpt`
- `reports/pre_refresh_route/laser_tx_board_top_route_status.rpt`
- `reports/pre_refresh_route/laser_tx_board_top_drc_routed.rpt`

这些 routed 文件只代表 refresh 前的历史实现结果，不代表当前 refreshed
source 已重新实现。

## 3. Module Reference refresh 与 BD 验证

使用 `scripts/refresh_tx_sequence_v2_bd_module_refs.tcl` 对实际 module
reference `system_laser_tx_core_0_0` 执行 `update_module_reference`，然后：

1. 确认 `tx_eom_geometry_precompute.v` 与
   `tx_eom_window_generator.v` 已进入 `sources_1`；
2. 执行 `validate_bd_design`；
3. 保存 BD；
4. 更新 sources_1/sim_1 compile order；
5. 强制生成 wrapper 并核对与 tracked wrapper 的 SHA-256。

结果为 `TX_SEQUENCE_V2_REFRESH_PASS`。`validate_bd_design` 无 error；存在
SPI1 EMIO SSIN tie-high、BRAM Port B/Data2Mem、BRAM address width、
reset/clock association 等既有 warning。未执行 IP upgrade，未改变 AXI
地址、板级端口、时钟频率或 reset 极性。

wrapper 生成前后内容哈希相同，说明 wrapper 接口与当前 BD 一致。refresh
后的文件名集合未出现额外 production 文件；XPR/BDA/XCI 中仍包含 Vivado
自动元数据变化，提交前需单独审查，不应笼统视为功能修改。

## 4. V2 record 与软件行为

配置 BRAM 采用 16-word/64-byte record，8 KiB BRAM 可容纳 128 条，
index 为 0..127。详细逐 word/bit 定义见
`docs/tx_phase_repeat_gap_global_eom.md`。

`WRITE_CONFIG` 的 gap 参数个数由 `repeat-1` 决定。PS 先写 invalid header，
再写 payload/metadata/CRC，回读后执行 DMB，最后提交 valid header。PL 对
record 做 header 双读和 CRC/metadata 校验，失败时保留 last-good active
config。

这是有意的协议不兼容升级：

```text
Functional behavior changed intentionally
```

旧 8-word record、旧 `insert_after`、旧单 gap 语义、旧 ELF、旧 bitstream
和旧 UDP 命令均不兼容。

## 5. 低速时钟与时长核对

| Rate | TXUSRCLK2 | EOM clock | K | EOM tick | 63-bit pattern | 127-bit pattern |
|---:|---:|---:|---:|---:|---:|---:|
| 500M | 7.8125 MHz | 125 MHz | 16 | 8 ns | 126 ns | 254 ns |
| 1000M | 15.625 MHz | 125 MHz | 8 | 8 ns | 63 ns | 127 ns |
| 2000M | 31.25 MHz | 125 MHz | 4 | 8 ns | 31.5 ns | 63.5 ns |

HEAD 和 gap 以 serial bits 配置，实际持续时间为：

```text
duration = configured_bits / line_rate
```

例如 500M 时 1 bit=2 ns，1000M 时 1 bit=1 ns，2000M 时
1 bit=0.5 ns。EOM 的 lead/trail 与起止边界在 8 ns tick 域内表达。

EOM pulse 数量规则：

- `eom_enable=0` 或 global index 非法：0；
- 合法 index：每个被接受任务最多 1；
- loop 只循环数据，不重新 arm EOM；
- 新任务才允许产生下一次 EOM。

## 6. 功能回归

### 6.1 Host-side 协议测试

命令：

```text
python scripts/test_tx_sequence_v2_protocol.py
```

结果：7/7 PASS，覆盖字段范围、独立 gaps、phase/global EOM、V2-only、
record/CRC/reserved、repeat=1 和 repeat=16。

### 6.2 RTL self-checking regression

命令：

```text
vivado.bat -mode batch -source scripts/run_tx_sequence_v2_regression.tcl -notrace
```

结果：

```text
PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS
TX_EOM_V2_REGRESSION_PASS
CONFIG_LOADER_V2_REGRESSION_PASS
```

覆盖：

- repeat=1、2、5、16；
- head=0/64 与 mixed gaps；
- direct 63/127 全 phase；
- runtime clock period change；
- loop 不重 arm、新任务重新 arm；
- EOM K=1/2/4/8/16；
- clock-safe abort 立即拉低且不 stale reopen；
- invalid index/disabled suppression；
- valid record、CRC error、半写/commit、double-header change；
- bad magic/version/metadata/sequence mirror/reserved；
- 所有错误均保留 active config。

### 6.3 Vitis managed clean build

在原 managed application 中执行 `make clean` 与 `make all`。16 个
production C source 各编译一次，link PASS，未观察到 compiler warning。

生成 ELF：

```text
vitis_bringup/bringup/Debug/bringup.elf
SHA-256=4A39F79AA74331894D31BB4C2EDBF9A0CE3ED031E8A61F0CE6192C8F023E4E7D
text=264815 data=3536 bss=3201088
```

ELF 只证明软件编译通过；由于本阶段拒绝生成配套的新 bit/XSA，它不是可用于
当前 V2 上板的成套 release artifact。

## 7. refresh 前 routed DCP 分析

分析脚本：`scripts/analyze_tx_sequence_v2_pre_refresh_route.tcl`。

| Metric | 结果 |
|---|---:|
| Setup WNS | -2.912 ns |
| Setup TNS | -412.729 ns |
| Setup failing endpoints | 270 |
| Hold WHS | -0.117 ns |
| Hold THS | -0.276 ns |
| Hold failing endpoints | 3 |
| Fully routed nets | 46990 |
| Routing errors | 0 |
| DRC errors | 0 |
| DRC warnings | 4 |
| no_clock | 0 |
| unconstrained_internal_endpoints | 0 |
| no_output_delay | 4 |

四个缺少 output delay 的端口为 `eom_out_0`、`soa_gate_out_0`、
`acq_trig_out_0`、`acq_gate_out_0`。DRC warning 为 dbg_hub 的三项
PDCN-1569 和一项 RTSTAT-10 no-routable-load；没有 DRC error。

最差 setup 是：

```text
GT_TXUSRCLK2_RUNTIME_MAX
u_tx_eom_geometry_precompute/end_tick_reg[13]_replica
→
GT_EOM_CLK_RUNTIME_MAX
u_tx_eom_window_generator/eom_window_reg
WNS=-2.912 ns
```

时钟交互摘要：

| From | To | WNS | TNS | WHS | THS |
|---|---|---:|---:|---:|---:|
| TXUSRCLK2 runtime max | EOM runtime max | -2.912 | -136.089 | -0.117 | -0.276 |
| EOM runtime max | TXUSRCLK2 runtime max | -2.393 | -7.009 | +0.088 | 0 |
| TXUSRCLK2 intra-clock | TXUSRCLK2 | -1.822 | -269.631 | +0.073 | 0 |
| EOM intra-clock | EOM | +1.339 | 0 | +0.262 | 0 |

CDC 报告还将 EOM arm、geometry、clock-safe 相关路径列为 Critical，包括
`eom_arm_pulse`、`end_tick` 和 `gt_ready_tx` 到 EOM domain 的跨域路径。
这些是 500M/1000M/2000M 均会经过的公共 EOM 控制，不是仅在高速 profile
活动的旁路。

## 8. 临时 artifact 决策

用户给定的低速临时 artifact 前提包括：无 unrouted net、DRC 无 error，
且不得存在明显 reset/CDC/EOM 卡高风险。虽然旧 route fully routed 且 DRC
无 error，但 setup/hold 失败及 EOM 公共 CDC Critical 直接违反安全前提。

因此本阶段：

- 不生成 `NON_SIGNOFF_LOW_SPEED_TEST_ONLY` bit/LTX/XSA；
- 不把已生成的 standalone ELF 作为上板组合交付；
- 不建议使用 refresh 前 routed DCP 上板；
- 不修改 RTL 或约束来追时序；
- 等后续独立任务修复 EOM CDC/约束并重新实现。

## 9. BD / wrapper / XSA 边界

- BD module reference 已 refresh，Validate Design 通过；
- wrapper 接口未变化；
- 外部端口、AXI 地址、clock/reset topology 未有意改变；
- output products、synthesis、implementation 未在 refresh 后重跑；
- XSA 未导出；
- Vitis platform/BSP 未因本阶段重新生成。

## 10. 当前结论

V2 的软件 parser、BRAM record/CRC/原子提交、pattern sequence 和 EOM
行为已经通过 host-side 与 self-checking RTL regression；Vitis managed
clean build 通过。

但 refresh 前 routed DCP 的 setup/hold 和 EOM CDC 结果不满足低速临时
上板安全条件。当前只能声明“功能仿真和软件构建通过”，不能声明
implementation、timing、CDC 或 hardware 通过。

Timing signoff deferred.

Low-speed artifacts are provisional only.

Hardware test was not run.

board_verified remains 0.

## 11. 后续建议

1. 单独审查 EOM geometry/arm/clock-safe 的 CDC 协议，使用明确的
   request/ack 或源域保持+目的域捕获结构，不能靠直接多位跨域；
2. 处理 `TXUSRCLK2 ↔ EOM clock` 的 setup/hold 约束与结构；
3. 补齐四个同步输出的板级 output delay，或在明确外部接口模型后说明为何
   不适用；
4. refresh 后重新跑 synthesis/implementation、timing、CDC、DRC；
5. 只有 WNS/TNS/WHS/THS、CDC、DRC 和 route 全部满足后，才生成新的成套
   bit/LTX/XSA/ELF，并进入 500M/1000M/2000M 实板验证。

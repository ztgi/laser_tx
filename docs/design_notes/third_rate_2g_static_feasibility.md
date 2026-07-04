# 2.000 Gbps 第三速率候选 static feasibility 分析

## 1. 分析目标与边界

本报告只做 read-only feasibility 分析，用于判断 2.000 Gbps 是否适合作为 500M/1000M 之后的第三速率候选。

本阶段不修改：

```text
RTL；
BD；
XDC；
GT Wizard；
Vitis / UDP 协议；
AD9528；
156.25 MHz refclk；
QPLL；
laser_tx_core；
bit / LTX。
```

本报告结论基于现有 XCI、RTL 结构、既有调试报告和用户提供的 line-rate 搜索结果。没有生成 2.0G GT Wizard，没有运行 static 2.0G synthesis/implementation，也没有上板验证。因此，本文只能作为下一步 2.0G static profile 的可行性判断，不能写成“2.0G 已实现”或“2.0G 已验证”。

## 2. 输入证据

本轮只读核查参考了以下文件和结论：

| 证据来源 | 用途 |
|---|---|
| `laser_tx.srcs/sources_1/ip/gtwizard_0/gtwizard_0.xci` | 确认当前 500M Profile0 的 refclk、CPLL、TXOUT_DIV、TXDATA width |
| `reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/copied_ip/gtwizard_0.xci` | 确认 1000M static compare profile 的 refclk、CPLL、TXOUT_DIV |
| `docs/debug_reports/06_drp_parameter_confirmation_for_500m_1000m.md` | 确认 GTXE2 TXOUT_DIV DRP address/bitfield、500M/1000M 编码、CPLL 参数未变化 |
| `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | 确认当前 profile table/accessor 中 500M/1000M 的 rate_id、TXOUT_DIV encoding、expected_txusrclk2、freq window |
| 用户提供的 line-rate 搜索结果 | 确认 125MHz refclk 搜索空间中包含 2.000 Gbps，且候选参数为 M=1、N1=4、N2=4、TXOUT_DIV=2 |

## 3. 当前 500M/1000M 参数核查

### 3.1 500M Profile0

当前主工程 GT Wizard XCI 中可确认：

```text
gt0_val_tx_line_rate        = 0.5
gt0_val_tx_data_width       = 64
gt0_val_tx_int_datawidth    = 32
gt0_val_tx_reference_clock  = 125.000
gt0_val_cpll_fbdiv_45       = 4
gt0_val_cpll_fbdiv          = 4
gt0_val_cpll_refclk_div     = 1
gt0_val_cpll_txout_div      = 8
```

因此，当前 500M Profile0 使用：

```text
REFCLK = 125 MHz
CPLL_FBDIV_45 = 4
CPLL_FBDIV    = 4
CPLL_REFCLK_DIV = 1
TXOUT_DIV = 8
TXDATA width = 64 bit
TX internal datawidth = 32-bit 语义
encoding = None
```

### 3.2 1000M Profile1 / dynamic profile

1000M static compare XCI 中可确认：

```text
gt0_val_tx_line_rate        = 1.0
gt0_val_tx_data_width       = 64
gt0_val_tx_int_datawidth    = 32
gt0_val_tx_reference_clock  = 125.000
gt0_val_cpll_fbdiv_45       = 4
gt0_val_cpll_fbdiv          = 4
gt0_val_cpll_refclk_div     = 1
gt0_val_cpll_txout_div      = 4
```

既有 DRP 参数确认报告也明确记录：

| 参数 | 500M | 1000M |
|---|---:|---:|
| REFCLK | 125 MHz | 125 MHz |
| CPLL_FBDIV_45 | 4 | 4 |
| CPLL_FBDIV | 4 | 4 |
| CPLL_REFCLK_DIV | 1 | 1 |
| TXOUT_DIV | 8 | 4 |

因此，500M -> 1000M 已验证路径中，GT 侧主要变化是 `TXOUT_DIV=8 -> 4`，CPLL 参数未变化。

### 3.3 当前 dynamic controller 中的 profile table

当前 `laser_gt_rate_switch_500m_1000m.v` 已经将 500M/1000M 参数集中到 profile accessor：

| 字段 | 500M | 1000M |
|---|---:|---:|
| `RATE_ID` | `RATE_ID_500M = 1` | `RATE_ID_1000M = 2` |
| `profile_rate_mbps` | 500 | 1000 |
| `profile_refclk_id` | `REFCLK_125M` | `REFCLK_125M` |
| `profile_refclk_freq_hz` | 125000000 | 125000000 |
| `profile_pll_type` | `PLL_TYPE_CPLL` | `PLL_TYPE_CPLL` |
| `profile_gt_drp_seq_id` | `GT_DRP_SEQ_TXOUT_DIV` | `GT_DRP_SEQ_TXOUT_DIV` |
| `profile_txout_div_enc` | `3'b011` | `3'b010` |
| `profile_expected_txusrclk2_hz` | 7,812,500 | 15,625,000 |
| freq counter window | 7700..7950 | 15400..15900 |

这说明当前代码结构已经适合新增第三个固定 profile：新增 profile_id、profile fields、MMCM DRP sequence 和 frequency window 即可扩展，但本报告不执行这些修改。

## 4. 2.000 Gbps 候选参数判断

用户提供的 line-rate 搜索结果指出，在当前 125MHz refclk 下，2.000 Gbps 可使用：

```text
REFCLK = 125 MHz
M = 1
N1 = 4
N2 = 4
CPLLCLKOUT = 2.0000 GHz
TXOUT_DIV = 2
```

该参数与当前 500M/1000M 已确认参数高度一致：

| 项目 | 500M | 1000M | 2.000G 候选 |
|---|---:|---:|---:|
| REFCLK | 125 MHz | 125 MHz | 125 MHz |
| CPLL M / REFCLK_DIV | 1 | 1 | 1 |
| CPLL N1 | 4 | 4 | 4 |
| CPLL N2 | 4 | 4 | 4 |
| CPLLCLKOUT | 2.000 GHz | 2.000 GHz | 2.000 GHz |
| TXOUT_DIV | 8 | 4 | 2 |
| line rate | 0.500 Gbps | 1.000 Gbps | 2.000 Gbps |

从结构上看，2.000G 很适合作为第三速率候选：它不要求引入 156.25MHz refclk，不要求 AD9528 动态输出，不要求 QPLL，也不要求改变 CPLL feedback/refclk divider。它延续了当前已经通过的 500M/1000M 设计思路：固定 125MHz refclk + 固定 CPLL 参数 + 只改变 TXOUT_DIV + 对应修改 TX user clock MMCM。

## 5. 2.000G 对 TX user clocking 的影响

当前设计保持：

```text
TXDATA width = 64 bit
TX internal datawidth = 32-bit 语义
encoding = None
TXUSRCLK = 2 * TXUSRCLK2
laser_tx_core 工作在 TXUSRCLK2 域
```

因此 2.000G 候选下理论用户时钟为：

| 项目 | 500M | 1000M | 2.000G 候选 |
|---|---:|---:|---:|
| line rate | 0.500 Gbps | 1.000 Gbps | 2.000 Gbps |
| TXUSRCLK | 15.625 MHz | 31.25 MHz | 62.5 MHz |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz | 31.25 MHz |
| laser_tx_core 时钟 | 7.8125 MHz | 15.625 MHz | 31.25 MHz |
| 每拍发送语义 | 64 bit/cycle | 64 bit/cycle | 64 bit/cycle |

2.000G 的 `expected_txusrclk2_hz` 应候选为：

```text
expected_txusrclk2_hz = 31_250_000
```

如果当前 `txusrclk2_freq_counter_axi` 的统计窗口约等价于 1ms 计数，且 500M/1000M 窗口分别为约 7,812 / 15,625，则 2.000G 的初始 frequency window 可按比例候选为：

```text
FREQ_2000M_MIN_COUNT ≈ 30800
FREQ_2000M_MAX_COUNT ≈ 31800
```

该窗口只是候选值，必须在 2.0G static bit 上用 AXI/FCLK ILA 实测 `txusrclk2_freq_counter_axi` 后再固化。不要在未实测前把它写成最终参数。

## 6. 需要新增的 profile 字段

若后续进入实现阶段，建议新增第三 profile：

```text
RATE_ID_2000M
rate_mbps = 2000
refclk_id = REFCLK_125M
refclk_freq_hz = 125000000
pll_type = PLL_TYPE_CPLL
TXOUT_DIV = 2
gt_drp_seq_id = GT_DRP_SEQ_TXOUT_DIV
mmcm_drp_seq_id = MMCM_DRP_SEQ_PROFILE2_2000M
expected_txusrclk2_hz = 31250000
freq_counter_min = 待 static 2.0G ILA 实测后确认
freq_counter_max = 待 static 2.0G ILA 实测后确认
lock_timeout = 可先沿用当前 profile timeout，static 验证后再调整
reset_timeout = 可先沿用当前 profile timeout，static 验证后再调整
flags = PROFILE_FLAG_NONE
ad9528_dynamic_required = 0
```

GT TXOUT_DIV encoding 需要从 UG476 / 既有 DRP map / readback 再确认。按当前 500M/1000M 规律：

| TXOUT_DIV | 已知/候选 encoding |
|---:|---:|
| 8 | `3'b011`，已确认 |
| 4 | `3'b010`，已确认 |
| 2 | `3'b001`，候选，仍需 2.0G static readback 确认 |

## 7. 仍需从 XCI / GT Wizard / 实现报告确认的参数

虽然 2.000G 是低风险候选，但进入实现前仍需要先生成独立 static 2.0G profile，并确认以下内容：

| 待确认项 | 当前判断 | 为什么必须确认 |
|---|---|---|
| 2.0G GT Wizard XCI 是否仍使用 CPLL | 候选为 CPLL | 防止 Wizard 自动切到 QPLL 或改变其它 GT 参数 |
| 2.0G XCI 中 `gt0_val_cpll_fbdiv_45` | 候选 4 | 必须与 500/1000 一致才可声明同 CPLL 参数 |
| 2.0G XCI 中 `gt0_val_cpll_fbdiv` | 候选 4 | 同上 |
| 2.0G XCI 中 `gt0_val_cpll_refclk_div` | 候选 1 | 同上 |
| 2.0G XCI 中 `gt0_val_cpll_txout_div` | 候选 2 | 必须由 XCI/generated HDL 确认 |
| 2.0G generated HDL 中 `TXOUT_DIV` | 候选 2 | 以 primitive 参数为最终证据 |
| 2.0G generated HDL 中 `RXOUT_DIV` | 不参与 TX-only 声明 | 当前项目仍只声明 TX 路径，不声明 RX/全双工 |
| 2.0G MMCM example design 参数 | 未确认 | TXUSRCLK/TXUSRCLK2 必须来自官方 example clocking 或等价确认 |
| 2.0G MMCM DRP 写表 | 未确认 | 不能从 1000M 表直接猜测后写入 |
| 2.0G `txusrclk2_freq_counter_axi` 实测窗口 | 未确认 | 需要 static bit + AXI/FCLK ILA 实测 |
| 2.0G timing | 未确认 | laser_tx_core 将运行在 31.25MHz TXUSRCLK2，虽然仍不高，但必须实现确认 |

## 8. 2.0G static 验证要求

下一阶段建议不要直接把 2.0G 加入 dynamic `rate set`。应先建立 2.0G static profile 并完成以下验证：

1. 生成独立 2.0G GT Wizard / wrapper / user clocking；
2. 保持 125MHz REFCLK，不引入 156.25MHz；
3. 保持 TXDATA width = 64 bit、encoding=None、internal datawidth=32；
4. 生成 2.0G static bit/LTX；
5. synthesis / implementation / timing 通过；
6. AXI/FCLK ILA 确认：
   - `cplllock_sync=1`；
   - `tx_mmcm_locked_sync=1`；
   - `txresetdone_sync=1`；
   - `gt_ready=1`；
   - `txoutclk_alive_axi=1`；
   - `txusrclk2_alive_axi=1`；
   - `txusrclk2_freq_counter_axi` 接近 31.25MHz 目标窗口；
7. TX 域 ILA 确认：
   - APPLY 后 `cfg_update_seen/cfg_valid/pattern_valid` 正常；
   - ENABLE 后 `engine_start/busy/done` 正常；
   - `txdata[63:0]` 非零；
   - `valid_mask[63:0]` 有效；
8. 保留 UDP 控制流程，但不要声明动态 2G 切换，直到 static 2G 先通过。

## 9. 禁止混入本阶段的内容

本阶段不应做：

```text
不选择 1.25G 作为第三速率；
不引入 156.25MHz refclk；
不实现 AD9528 动态输出；
不新增 GT refclk 动态切换；
不切 QPLL；
不修改 laser_tx_core；
不修改 UDP 协议；
不把 2.0G feasibility 写成 2.0G 已实现；
不未经 static 2.0G 验证就加入 dynamic profile table。
```

## 10. 结论

基于现有文件和用户提供的 line-rate 搜索结果，建议选择 2.000 Gbps 作为第三速率候选。

理由：

1. 2.000G 可以复用当前已验证的 125MHz refclk；
2. 2.000G 候选 CPLL 参数为 M=1、N1=4、N2=4，与当前 500M/1000M 的 CPLL 参数一致；
3. 2.000G 很可能只需要新增 `TXOUT_DIV=2` 的 GT profile；
4. 当前 dynamic rate controller 已经具备 profile table/accessor、GT DRP、MMCM DRP、reset/lock/ready/frequency verify 的执行框架；
5. 2.000G 比引入 156.25MHz / AD9528 / QPLL / 1.25G 分支风险低，更适合作为 Level 2 第三速率扩展的第一步。

但必须强调：

```text
2.000G 当前只是 feasibility 推荐；
2.000G static GT Wizard / MMCM / timing / ILA 尚未验证；
2.000G dynamic rate set 尚未实现；
2.000G 不应写入当前 dynamic profile table，直到 static 2.0G build 和上板 ILA 验证完成。
```

建议下一步：

```text
1. 新建独立 2.0G static profile；
2. 生成官方 GT Wizard example design；
3. 提取 2.0G user clocking / MMCM 参数；
4. 生成 bit/LTX 并通过 timing；
5. 上板用 AXI/FCLK ILA 验证 GT/MMCM/txusrclk2 alive；
6. 再决定是否将 2.0G 加入 dynamic profile table。
```

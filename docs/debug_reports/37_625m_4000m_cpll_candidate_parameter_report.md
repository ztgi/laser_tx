# 625M / 4000M 125MHz CPLL 候选参数确认报告

## 1. 任务边界

本阶段只生成和核对两个隔离 GT Wizard 参数包：625Mbps 与 4000Mbps。
主工程 `laser_tx.xpr`、RTL、BD、XDC、GT wrapper、rate controller、Vitis、
UDP、`RATE_ID`、正式 profile table 与 `board_verified` 均未修改。

隔离生成物位于：

```text
reports/cpll_candidate_parameter_compare/625m_125m_cpll/
reports/cpll_candidate_parameter_compare/4000m_125m_cpll/
reports/cpll_candidate_parameter_compare/mmcm_drp_candidates/
```

`WIZARD_CONFIRMED` 仅表示隔离 generated HDL/user-clock helper 与 XDC 已
交叉确认参数；不表示主工程已综合、已写入 DRP、已上板或已进入 supported list。

## 2. 复用方法

| 项目 | 复用依据 |
|---|---|
| GT Wizard 隔离生成 | `scripts/create_gtwizard_1000m_compare.tcl`、`scripts/create_gtwizard_2000m_compare.tcl` 的复制 XCI / 临时 project / example design 流程 |
| GT CPLL/TXOUT_DIV DRP | 当前 controller 的 VPHY 口径：CPLL divider `0x05E[12:0]`，TXOUT_DIV `0x088[6:4]` |
| MMCM DRP 生成 | Vitis 2022.2 `xvphy_mmcme2.c` 的 XAPP888 整数 divider、LOCK、FILTER 编码 |
| 当前执行器格式 | 15 项顺序：`0x28,14,15,16,08,09,0A,0B,0C,0D,18,19,1A,4E,4F` |

新增脚本不会打开或保存主工程：

```text
scripts/create_gtwizard_625m_4000m_compare.tcl
scripts/generate_625m_4000m_mmcm_drp_candidates.py
```

## 3. 625M 参数确认

### 3.1 数学候选与 generated GT 参数

| 项目 | 初始推导 | generated HDL/XDC 交叉结果 | 状态 |
|---|---|---|---|
| MGTREFCLK | 125MHz | 125MHz | WIZARD_CONFIRMED |
| PLL | CPLL | CPLL | WIZARD_CONFIRMED |
| CPLL M/N1/N2 | 1 / 4 / 5 | 1 / 4 / 5 | WIZARD_CONFIRMED |
| TXOUT_DIV | 8 | 8 | WIZARD_CONFIRMED |
| line rate | 625Mbps | `2 × 125 × 4 × 5 / 8 = 625Mbps` | WIZARD_CONFIRMED |
| TX data width | 64 | 64 | WIZARD_CONFIRMED |
| TX internal width | 32-bit semantic / primitive encoding 1 | 64 / primitive encoding 1 | WIZARD_CONFIRMED |
| encoding | None | None | WIZARD_CONFIRMED |
| TXOUTCLKSEL | `3'b010` | `3'b010` | WIZARD_CONFIRMED |
| TXSYSCLKSEL | CPLL | generated init assigns `2'b00` | WIZARD_CONFIRMED |

`selected_properties.txt` 中 `identical_val_tx_line_rate` 仍显示 copied-XCI 的
0.5，因为该 Wizard configuration group 将该字段禁用；它不能作为本包的
最终 line-rate 依据。最终证据是 generated `GTXE2_CHANNEL` 的 CPLL divider
与 `TXOUT_DIV=8`，以及 generated XDC 的 `TXOUTCLK` period=51.2ns。

### 3.2 CPLL / GT DRP 复用关系

| 项目 | 值 | 与现有 profile 的关系 |
|---|---:|---|
| CPLL divider DRP value | `0x1003` | REUSED_PARAMETER_GROUP：1250/2500/5000M |
| TXOUT_DIV DRP field | `0x088[6:4]` | 已验证 field |
| TXOUT_DIV=8 encoding | `3'b011` | REUSED_PARAMETER_GROUP：500M |
| 1/4/5 + D8 | 新组合 | NEW_PARAMETER_COMBINATION |

### 3.3 Wizard 实际 MMCM 静态参数

| 参数 | 值 |
|---|---:|
| CLKIN / TXOUTCLK | 19.53125MHz，period=51.2ns |
| DIVCLK_DIVIDE | 1 |
| CLKFBOUT_MULT | 31 |
| CLKOUT0_DIVIDE | 62，TXUSRCLK2=9.765625MHz |
| CLKOUT1_DIVIDE | 31，TXUSRCLK=19.53125MHz |
| CLKOUT2_DIVIDE | 1 |
| MMCM VCO | 605.46875MHz |
| fractional 参数 | 无；均为整数 |

注意：Wizard 选择 31/62/31，而不是初始数学猜测的 32/64/32；后者没有被
用于 candidate sequence。

### 3.4 625M MMCM DRP candidate

来源：`xvphy_mmcme2.c` 的整数编码，输出文件：
`reports/cpll_candidate_parameter_compare/mmcm_drp_candidates/625m_mmcm_drp_candidate.json`。

| addr | value |
|---:|---:|
| 28 | FFFF |
| 14 | 13D0 |
| 15 | 0080 |
| 16 | 1041 |
| 08 | 17DF |
| 09 | 0000 |
| 0A | 13D0 |
| 0B | 0080 |
| 0C | 1041 |
| 0D | 00C0 |
| 18 | 002C |
| 19 | 7C01 |
| 1A | 7DE9 |
| 4E | 0800 |
| 4F | 9000 |

MMCM_SEQUENCE_GENERATED；尚未接入主工程，尚未执行 DRP readback。

### 3.5 625M frequency window 候选

当前约 1ms counter 的理论中心为 `9,765.625`。参照现有 CPLL profile 的
约 -1.7% 至 +1.9% 窗口，初始候选为：

```text
FREQ_625M_MIN_COUNT = 9600
FREQ_625M_MAX_COUNT = 9950
```

该窗口仅用于后续第一次上板的初始候选，必须以 ILA 实测校准。

## 4. 4000M 参数确认

### 4.1 数学候选与 generated GT 参数

| 项目 | 初始推导 | generated HDL/XDC 交叉结果 | 状态 |
|---|---|---|---|
| MGTREFCLK | 125MHz | 125MHz | WIZARD_CONFIRMED |
| PLL | CPLL | CPLL | WIZARD_CONFIRMED |
| CPLL M/N1/N2 | 1 / 4 / 4 | 1 / 4 / 4 | WIZARD_CONFIRMED |
| TXOUT_DIV | 1 | 1 | WIZARD_CONFIRMED |
| line rate | 4000Mbps | `2 × 125 × 4 × 4 / 1 = 4000Mbps` | WIZARD_CONFIRMED |
| TX data width | 64 | 64 | WIZARD_CONFIRMED |
| TX internal width | 32-bit semantic / primitive encoding 1 | 64 / primitive encoding 1 | WIZARD_CONFIRMED |
| encoding | None | None | WIZARD_CONFIRMED |
| TXOUTCLKSEL | `3'b010` | `3'b010` | WIZARD_CONFIRMED |
| TXSYSCLKSEL | CPLL | generated init assigns `2'b00` | WIZARD_CONFIRMED |

该包的 selected property line-rate 同样保留 copied-XCI 的 0.5；实际
generated primitive 的 CPLL values、`TXOUT_DIV=1` 与 generated XDC 的
TXOUTCLK period=8ns 共同证明实际 TX 参数是 4.000Gbps。

### 4.2 CPLL / GT DRP 复用关系

| 项目 | 值 | 与现有 profile 的关系 |
|---|---:|---|
| CPLL divider DRP value | `0x1002` | REUSED_PARAMETER_GROUP：500/1000/2000M |
| TXOUT_DIV DRP field | `0x088[6:4]` | 已验证 field |
| TXOUT_DIV=1 encoding | `3'b000` | REUSED_PARAMETER_GROUP：5000/6250M |
| 1/4/4 + D1 | 新组合 | NEW_PARAMETER_COMBINATION |

### 4.3 Wizard 实际 MMCM 静态参数

| 参数 | 值 |
|---|---:|
| CLKIN / TXOUTCLK | 125MHz，period=8ns |
| DIVCLK_DIVIDE | 1 |
| CLKFBOUT_MULT | 5 |
| CLKOUT0_DIVIDE | 10，TXUSRCLK2=62.5MHz |
| CLKOUT1_DIVIDE | 5，TXUSRCLK=125MHz |
| CLKOUT2_DIVIDE | 1 |
| MMCM VCO | 625MHz |
| fractional 参数 | 无；均为整数 |

### 4.4 4000M MMCM DRP candidate

来源：`xvphy_mmcme2.c` 的整数编码，输出文件：
`reports/cpll_candidate_parameter_compare/mmcm_drp_candidates/4000m_mmcm_drp_candidate.json`。

| addr | value |
|---:|---:|
| 28 | FFFF |
| 14 | 1083 |
| 15 | 0080 |
| 16 | 1041 |
| 08 | 1145 |
| 09 | 0000 |
| 0A | 1083 |
| 0B | 0080 |
| 0C | 1041 |
| 0D | 00C0 |
| 18 | 01E8 |
| 19 | 3801 |
| 1A | 39E9 |
| 4E | 0800 |
| 4F | 1900 |

MMCM_SEQUENCE_GENERATED；尚未接入主工程，尚未执行 DRP readback。

### 4.5 4000M frequency window 候选

理论中心为 `62,500`。按现有 2000/5000M CPLL window 的相对余量，初始
候选为：

```text
FREQ_4000M_MIN_COUNT = 61400
FREQ_4000M_MAX_COUNT = 63600
```

现有 controller 的 counter 和 profile window 均为 24-bit，62500 不存在
16-bit signed/unsigned 截断问题；但窗口仍须用上板 ILA 实测确认。

## 5. 建议进入集成的判定与边界

| 条件 | 625M | 4000M |
|---|---|---|
| WIZARD_CONFIRMED | 是 | 是 |
| REUSED_PARAMETER_GROUP | `0x1003` + D8 | `0x1002` + D1 |
| NEW_PARAMETER_COMBINATION | 是 | 是 |
| MMCM_SEQUENCE_GENERATED | 是 | 是 |
| HARDWARE_NOT_TESTED | 是 | 是 |
| 可进入主工程集成准备 | 建议 | 建议 |

建议下一阶段将两档作为同一 125MHz/CPLL 批次接入，但每一档仍需独立完成：
GT/MMCM DRP readback、从稳定档切入、TXUSRCLK2 frequency verify、回切、
UDP 状态与 error_code 检查。未完成这些上板证据前，两档均不得设置
`board_verified=1`，不得加入正式 `rate set` supported list。

本报告不是 synthesis、implementation、bit/LTX 或 hardware bring-up 报告。

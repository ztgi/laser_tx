# AD9528 PLL2 细步进 TEST0 候选选择与实现路径状态模型

## 1. 目标与严格边界

本阶段只重构只读候选规划模型、生成 shortlist 并定义下一阶段接口。不写 AD9528 寄存器，不执行 IO_UPDATE/SYNC，不修改 RTL、BD/XDC、GT Wizard、CPLL/QPLL/MMCM DRP、supported rate 或 UDP 下板命令，也不生成 bitstream。

最终安全决策为：

```text
NO_SAFE_PLL2_TEST0_CANDIDATE
```

原因不是没有数学候选，而是本板尚无针对 PLL2 TEST0 经 readback/lock/共享输出影响确认的完整运行镜像。当前首选待解锁候选为 `PLL2_TEST0_OUT0_124P8_CPLL_998P4`，但它不能在本阶段进入可执行 candidate set。

## 2. 固定参考时钟与 AD9528 实验路径

速率状态必须由 `(target_rate, implementation_path)` 联合确定，不能只用 Mbps：

```text
FIXED_125M_CPLL
FIXED_125M_QPLL
FIXED_156P25M_CPLL
FIXED_156P25M_QPLL
AD9528_OUT0_CPLL_EXPERIMENTAL
AD9528_OUT0_QPLL_EXPERIMENTAL
```

现有正式 profile 继续使用固定 125 MHz CPLL/QPLL 路径。AD9528 OUT0 即使存在精确数学组合，也只是独立实验路径，不覆盖正式 planner。

## 3. 当前已验证 AD9528 基线

当前 `VCXO_122P88` 的真实证据链为：

- 四线 SPI identity/readback 已验证；
- 七项 buffered masked write、单次 IO_UPDATE、post-readback 和 snapshot/restore 已验证；
- OUT0 source=VCXO、divider=1；
- FPGA ODIV2 计数和 UDP 回读得到 OUT0 约 122.872～122.874 MHz；
- restore 后完整窗口 `count=0/alive=0/in_range=0`；
- `board_verified=0`，因为外部仪器和 Bank110→Bank111 GT refclk 尚未验证。

该 profile 标记为：

```text
source=VCXO_DIRECT
board_measured=1
pll2_fine_step_candidate=0
```

## 4. 当前寄存器事实与推导边界

### 4.1 已由本板 readback/apply 确认

| 内容 | 证据 |
|---|---|
| 上电 PLL2 字段 | `0202=03,0203=00,0204=00,0207=00,0208=00`，不构成有效 PLL2 profile |
| VCXO candidate PLL1 bypass | `0108=01,0109=38` masked readback |
| OUT0 source/divider | `0300=20,0301=00,0302=00`，VCXO source/divide-1/LVDS |
| global power | `0500=1C`；candidate 有意 power-down PLL1/PLL2 |
| OUT0 enable | `0501 bit0=0`、LDO/status readback 通过 |
| IO_UPDATE | 七项 buffered write 后一次 `000F=01`，已上板验证 |
| restore | 七个完整旧字节恢复、一次 IO_UPDATE、统一 readback 成功 |

`VCXO_122P88` 设置了 PLL1 bypass 路径，但没有使 PLL1 锁相环工作；PLL1 和 PLL2 均被 power-down。OUT0 使用 VCXO direct，不是 PLL2 输出。

### 4.2 仍为推导或参考实现来源

- PLL2 charge pump、feedback A/B、loop filter、calibration 的完整 TEST0 值；
- PLL2 lock/status 在本板该配置下的实际响应；
- PLL2 作为共享源时 OUT1/OUT3/OUT12/OUT13 的运行依赖；
- PLL2 profile 是否需要 channel SYNC，以及 SYNC 对其他输出的影响；
- 目标 OUT0 接入 Bank111 后的 GT Wizard/MMCM/实现结果。

当前软件只直接改 OUT0 channel，但启用 PLL2 必然修改 common PLL2 寄存器。其他 OUTx 当前是否消费 PLL2 没有完整运行配置证据，因此共享时钟树风险标为 `HIGH_UNACCEPTED_PLL2_COMMON_CHANGE`。

## 5. Buffered、IO_UPDATE 与 SYNC

已验证 VCXO candidate 的 buffered snapshot 范围为：

```text
0108, 0109, 0300, 0301, 0302, 0501, 0500
```

写完后执行一次 IO_UPDATE；单 OUT0 VCXO/divide-1 profile 不执行 SYNC。

PLL2 TEST0 下一阶段至少还需 snapshot：

```text
0200, 0201, 0202, 0203, 0204, 0205, 0206, 0207, 0208,
0300, 0301, 0302, 0500, 0501
```

并确认 calibration、IO_UPDATE、lock wait 和可选 SYNC 的顺序。当前没有把这些地址写入 Vitis executor。

## 6. 实现路径感知状态和原因码

状态：`SUPPORTED / CANDIDATE / BLOCKED`。原因码使用明确作用域，包括：

```text
LEGAL_NOT_IMPLEMENTED
IMPLEMENTED_NOT_BOARD_VERIFIED
REFERENCE_CLOCK_NOT_BOARD_CONNECTED
AD9528_PROFILE_NOT_IMPLEMENTED
GT_WIZARD_NOT_CONFIRMED
MMCM_PROFILE_NOT_CONFIRMED
NO_LEGAL_VERIFIED_125M_CPLL_PROFILE
NO_LEGAL_125M_QPLL_PROFILE
NO_LEGAL_156P25M_PROFILE
NO_LEGAL_AD9528_OUT0_PROFILE
SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED
AD9528_REGISTER_IMAGE_NOT_CONFIRMED
```

3000M 固定路径永久保留当前记录：

```text
target_rate=3000M
path=FIXED_125M_CPLL
state=BLOCKED
reason=NO_LEGAL_VERIFIED_125M_CPLL_PROFILE
```

AD9528 数学候选只新增独立 `AD9528_OUT0_*_EXPERIMENTAL/CANDIDATE` 记录。

## 7. 枚举器输入模型

`scripts/enumerate_ad9528_gt_refclk_candidates.py` 现在显式定义：

- `Ad9528SourceModel`：VCXO、PLL1 mode、candidate output；
- `Ad9528Pll2Limits`：PFD/VCO/输出边界及 R1/N2/M1/divider 集合；
- `GtImplementationPath`：CPLL/QPLL 实验路径；
- `RatePolicy`：supported 值和固定 3000M BLOCKED 策略。

所有精确匹配和合法性判断使用 `Fraction`。浮点只用于 CSV 小数显示。AD9528 Rev. G 已编码 PFD 最大值 275 MHz、VCO 3450～4025 MHz 和 OUT0 最大 1.25 GHz；未虚构资料中未确认的额外 PFD 最小规格，计算模型只要求正频率并在报告中明确这一边界。

## 8. 候选排序字段

CSV 保留所有可解释分项，不使用黑盒分数：exact match、125 MHz 距离、PFD/VCO/GT VCO margin、是否复用已验证 GT 参数族、是否 QPLL、是否需新 MMCM、common/channel 寄存器变化数、共享风险和 1 ms 测量分辨率。

## 9. 低风险 shortlist

输出 `low_risk_shortlist.csv` 共 20 行。首选待解锁候选：

| 项目 | 值 |
|---|---:|
| 名称 | `PLL2_TEST0_OUT0_124P8_CPLL_998P4` |
| VCXO | 122.88 MHz |
| doubler/R1/N2/M1/OUT0_DIV | 1 / 8 / 65 / 4 / 8 |
| PLL2 PFD | 15.36 MHz |
| PLL2 VCO | 3993.6 MHz |
| OUT0 | 124.8 MHz 精确值 |
| 1 ms ODIV2 count | 62400 |
| GT | CPLL M=1,N1=4,N2=4,TXOUT_DIV=4 |
| 理论 line rate | 998.4 Mbps |
| TXUSRCLK/TXUSRCLK2 | 31.2 / 15.6 MHz |

选择理由：OUT0 接近固定 125 MHz、复用 1/4/4 CPLL 参数族、计数器能与 125 MHz 的 62500 count 清晰区分、VCO margin 合法、restore 方案可沿用 snapshot 框架。它的用途仅是验证 PLL2 可编程 OUT0，不是新增 998.4M supported rate。

## 10. 精确 3000M shortlist

共 3 条独立实验路径：

| OUT0 | AD9528 R1/N2/M1/div | GT 路径 | GT 参数 | GT VCO | TXUSRCLK2 |
|---:|---|---|---|---:|---:|
| 120 MHz | 16/125/4/8 | CPLL | M=1,N1=5,N2=5,D=2 | 3.0 GHz | 46.875 MHz |
| 120 MHz | 16/125/4/8 | QPLL | M=2,N=100,D=2 | 6.0 GHz | 46.875 MHz |
| 60 MHz | 16/125/4/16 | QPLL | M=1,N=100,D=2 | 6.0 GHz | 46.875 MHz |

三条均为 `CANDIDATE/LEGAL_NOT_IMPLEMENTED`，仍需 AD9528 image、GT Wizard 和 MMCM 确认。它们不改变固定 125 MHz CPLL 的 BLOCKED 记录。

## 11. TEST0 决策

当前不能满足“完整寄存器字段可追溯、共享 PLL2 影响已接受、snapshot 覆盖所有 common 修改”的全部条件。因此正式决策是 `NO_SAFE_PLL2_TEST0_CANDIDATE`。

`PLL2_TEST0_OUT0_124P8_CPLL_998P4` 只是下一阶段优先补齐寄存器计划的对象，不是当前可执行 profile。

## 12. 输出文件与测试

生成：

```text
reports/ad9528_fine_step_test0/all_candidates.csv
reports/ad9528_fine_step_test0/low_risk_shortlist.csv
reports/ad9528_fine_step_test0/exact_3000m_shortlist.csv
reports/ad9528_fine_step_test0/recommended_test0.json
reports/ad9528_fine_step_test0/generation_summary.txt
```

统计：all=1701（含 1 条 `VCXO_DIRECT` 测量基线）、low-risk=20、exact-3000=3。10 项 unittest 覆盖 Fraction 确定性、非法 PFD/VCO、GT line-rate gap、VCXO/PLL2 来源、3000M 路径独立、去重、计数、无安全候选停止语义和 JSON `board_verified=false`，全部通过。

## 13. 下一阶段明确输入

下一阶段在实现任何写命令前，必须产出并人工审核：

```text
candidate: PLL2_TEST0_OUT0_124P8_CPLL_998P4
masked-write: 0200..0208 PLL2 common + 0300..0302 OUT0 + 0500/0501 power
snapshot: 覆盖所有被修改完整字节及 lock/status
sequence: snapshot -> masked writes -> IO_UPDATE/calibration -> lock wait -> optional SYNC -> readback
expected measured_out0_hz: 124800000
measurement tolerance: 由当前1ms计数窗口定义，目标count=62400
restore: 恢复完整snapshot -> IO_UPDATE -> readback；预期回到apply前测量状态
shared risk: PLL2 common配置可能影响所有消费PLL2的OUTx，必须先确认/接受
```

只有完整寄存器 image、charge-pump/loop-filter、calibration/lock 和共享输出影响确认后，才可实现未来命令：

```text
ad9528 candidate set pll2_test0
ad9528 candidate status
ad9528 candidate restore
ad9528 measure status
```

本阶段没有实现这些命令。

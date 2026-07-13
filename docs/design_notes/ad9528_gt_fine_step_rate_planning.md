# AD9528 经相邻 Quad GTX 细步进参考时钟候选规划

## 1. 修改摘要

新增只读枚举器 `scripts/enumerate_ad9528_gt_refclk_candidates.py`，以及生成结果 `reports/ad9528_gt_refclk_candidates/ad9528_gt_refclk_candidates.csv`。工具从 AD9528 的参考性 PLL2 模型推导 OUT0 的精确有理数频率，再与 XC7Z100-2 GTX 的 CPLL/QPLL 合法元组相乘；全过程使用 Python `Fraction`，不以浮点近似作为合法性判定依据。

本阶段只建立候选数据和架构边界：不改主工程 RTL、Vitis、GT/MMCM DRP、profile table、supported list、XDC 或 AD9528 实际寄存器。

## 2. 修改前问题

当前工程已经确认 OUT0 可通过 Bank110 到 Bank111 的专用相邻 Quad 参考时钟资源到达 SFP+ GTX Quad，但没有当前板卡 AD9528 的可信寄存器镜像：`laser_ad9528.c` 只初始化 SPI、读取芯片 ID，`laser_ad9528_apply_rate_profile()` 返回 `XST_NO_FEATURE`。因此不能把“OUT0 物理可达”误写成“OUT0 当前频率已知”或“任何数学频率都能安全切换”。

外部旧工程 `project_gtx/software_src/laser_tx_rate/ad9528_rate.c` 包含一个可读的参考性配置：122.88 MHz VCXO、PLL1 bypass、PLL2/OUT0 配置、IO_UPDATE、PLL2 lock 轮询和 channel sync。该工程并非当前 `laser_tx` 的已验证寄存器镜像，且其 GTX 路由叙述与本工程的 Bank111 SFP+ 拓扑不一致；它只能用来限定枚举模型和字段范围，不能直接下发到本板。

## 3. 修改后结构

候选生成链路如下：

```text
参考性 VCXO/PLL1 假设
  -> AD9528 PLL2 (doubler, R1, N2, M1)
  -> OUT0 divider
  -> 精确 OUT0 refclk 候选
  -> XC7Z100-2 CPLL/QPLL 枚举
  -> line rate / TXUSRCLK / TXUSRCLK2
  -> ALREADY_SUPPORTED_RATE_VALUE / LEGAL_CANDIDATE / BLOCKED
```

参考模型的精确公式为：

```text
PFD       = VCXO × doubler / R1
PLL2 VCO  = PFD × N2 × M1
OUT0      = PLL2 VCO / (M1 × OUT0_DIV)
CPLL line = 2 × OUT0 × N1 × N2 / (M × TXOUT_DIV)
QPLL line = OUT0 × N / (M × TXOUT_DIV)
TXUSRCLK2 = line / 64       (当前 64-bit、无 8b/10b 接口假设)
```

模型限制：VCXO=122.88 MHz、PLL1 bypass 只是**参考软件假设**；PLL2 PFD 不超过 275 MHz、VCO 范围 3450–4025 MHz、M1=3/4/5、R1=1…31、N2=1…256、OUT0 divider=1…256，OUT0 不超过 1.25 GHz。GTX 约束复用项目现有 `enumerate_gtx_rate_candidates.py` 的 UG476/DS191 实现，其中 silicon line-rate coverage 是 0.500–8.000 Gbps 与 9.800–10.3125 Gbps 两段，8.000–9.800 Gbps 不是连续可用区域。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| OUT0 频率依据 | 仅有物理连线，不知当前频率 | 参考模型下精确候选表 | 仅规划，不可执行 |
| 计算精度 | 无统一工具 | 全程 `Fraction` 精确有理数 | 避免浮点误分类 |
| AD9528 配置来源 | 当前工程无 OUT0 镜像 | 外部参考代码仅作为模型输入 | 不等同板级真值 |
| GT profile | 九档已支持 profile | 不变 | 不新增 supported rate |
| 3000 Mbps | formal planner blocked | 仍 BLOCKED | 数学行不覆盖验证门槛 |
| 主工程 | 无改动 | 无改动 | 功能等价 |

## 5. 功能等价性说明

Expected system behavior unchanged。枚举器不访问硬件、不写 SPI、不生成 DRP magic number、不调用 Vivado、不写 GPIO request，也不改变 UDP `rate list`/`rate set`。其结果中 `LEGAL_CANDIDATE` 表示当前模型与已编码硅片范围相容，绝不表示 GT Wizard 已接受、MMCM DRP 已生成、时序已满足或板级已通过。

`3000 Mbps` 在 CSV 中即使可出现数学 QPLL 行，也被统一标记为：

```text
BLOCKED
FORMAL_3000M_BLOCKED_PENDING_GT_WIZARD_AND_MMCM_PROFILE_EVIDENCE
```

它不会因候选枚举而进入正式 planner 或 supported list。

## 6. 测试与验证

执行：

```text
python scripts/enumerate_ad9528_gt_refclk_candidates.py \
  --output-dir reports/ad9528_gt_refclk_candidates
python -m py_compile scripts/enumerate_ad9528_gt_refclk_candidates.py
```

输出结果：

| 项目 | 结果 |
| --- | ---: |
| 范围内唯一 OUT0 精确频率 | 8,506 |
| AD9528/GTX 合法组合元组 | 174,640 |
| 唯一 GTX line-rate 数值 | 58,046 |
| 数值上与现有 supported rate 重合的元组 | 10 |
| `LEGAL_CANDIDATE` 元组 | 174,627 |
| `3000 Mbps` 数学元组 | 3，均为 `BLOCKED` |
| 参考模型中精确 125 MHz OUT0 | 0 |

最后一项说明：在“122.88 MHz、PLL1 bypass”的参考模型约束下，125 MHz 不是一个可由枚举范围内整数组合产生的 OUT0 结果。它不说明 AD9528 永远无法产生 125 MHz；若真实 PLL1/REF 输入路径不同，必须以读回的实际镜像重新枚举。

Hardware test was not run。没有 AD9528 写入、IO_UPDATE/SYNC、锁定读回、GT Wizard、主工程综合实现或上板测试。

## 7. QoR / timing 对比

本阶段没有改动主工程 RTL/时钟结构，也没有运行主工程 synthesis/implementation。

```text
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

该要求只在后续将某个经确认的 OUT0 候选实际接入 GT wrapper/profile 时生效。CSV 的 `TXUSRCLK2` 是接口公式结果，不能替代主工程的 MMCM 配置、VERIFY_RATE 窗口或 timing report。

## 8. 当前证据更新与 TEST0 规划状态

本文形成时“当前可信 AD9528 image 缺失”是正确的早期前提，但已经不是当前完整状态：

- 当前已取得并验证 `VCXO_122P88` 的七项 masked register plan、IO_UPDATE、post-readback、snapshot/restore；
- FPGA ILA 与 PS/UDP 软件回读已测得 OUT0 约 122.872～122.874 MHz；
- 该证据只覆盖 `VCXO_DIRECT`，且 PLL1/PLL2 均 power-down，不是 PLL2 细步进验证；
- 完整 PLL2 charge-pump/loop-filter/calibration/lock 运行镜像仍未针对 TEST0 在本板确认。

新版实现路径感知枚举和 TEST0 决策见 `ad9528_fine_step_test0_candidate_selection.md`。固定 `3000M/FIXED_125M_CPLL` 仍保持 `BLOCKED/NO_LEGAL_VERIFIED_125M_CPLL_PROFILE`；AD9528 数学路径只能建立独立 experimental candidate。

## 9. 风险与后续建议

1. **历史上可信 AD9528 image 缺失；当前只补齐了 VCXO direct image。** PLL2 TEST0 仍必须确认 charge pump、feedback A/B、loop filter、calibration、R1/N2/M1、power、IO_UPDATE/SYNC 和 lock/status。
2. 在该镜像确认前，不推荐定义 `AD9528_GT_REFCLK_TEST0`，也不推荐任何新 GT profile；推荐结论为“**没有可安全下板的测试 profile**”。
3. 读取到真实镜像后，应将其作为枚举器的显式输入重新生成候选表，选择**一档**与现有 CPLL/QPLL 参数族尽量接近的速率，逐项完成 GT Wizard、MMCM DRP、frequency window、implementation 与 UDP/ILA 双向回切验证。
4. 若真实 OUT0 频率或输入源与参考模型不同，当前 174,640 行只保留为方法验证，不能用于配置决策。
5. AD9528 OUT0 经 Bank110 到 Bank111 的路由能力已在隔离 Vivado 实现中确认；后续集成仍需独立处理 GT wrapper 的 `GTNORTHREFCLK0`、`CPLLREFCLKSEL/QPLLREFCLKSEL=3'b011`、reset/lock 和 XDC，且不能占用 Bank110 GTX 数据通道。

## 参考来源

- [AMD UG476: 7 Series Transceivers User Guide](https://docs.amd.com/api/khub/documents/SAXb2rXapMfInryXnPr5NQ/content)：GT reference-clock mux、CPLL/QPLL relation 与相邻 Quad 参考时钟资源。
- [AMD PG046: GTX/GTH Transceivers Wizard](https://docs.amd.com/r/en-US/pg046-gtwizard)：相邻 Quad 参考时钟的 Wizard 路由/引脚交换说明。
- [Analog Devices AD9528 data sheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ad9528.pdf)：PLL2、VCO、PFD、输出与 divider 限制。
- `D:/FPGA_Learn/project_gtx/software_src/laser_tx_rate/ad9528_rate.c`：仅作参考性模型输入，不是当前工程寄存器镜像。

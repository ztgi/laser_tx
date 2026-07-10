# 10.000G QPLL：125MHz 与 156.25MHz 参数确认包对比

## 1. 本阶段目标与边界

本阶段只做 10.000Gbps QPLL 参数确认，不接入主工程动态切换链路。

本阶段未修改：

- 主工程 RTL；
- BD / XDC；
- Vitis / UDP；
- rate list / supported profile；
- `RATE_ID_10000M`；
- 现有 CPLL profile；
- 156.25MHz 板级参考时钟路径；
- AD9528 或外部参考时钟动态配置。

本阶段新增一个隔离参数提取脚本：

```text
scripts/create_gtwizard_10g_qpll_compare.tcl
```

该脚本复制当前工程中的 GT Wizard XCI 到 `reports/qpll_10g_parameter_compare/` 下，在独立临时工程中尝试生成两个 10.000G QPLL 参数包：

1. `10g_125m_qpll_n80`：10.000G / 125MHz / QPLL / QPLL_N=80；
2. `10g_156p25m_qpll_n64`：10.000G / 156.25MHz / QPLL / QPLL_N=64。

它不打开、不保存、不修改 `laser_tx.xpr`，也不将生成结果加入主工程。

## 2. 关键结论

根据 UG476 中的 QPLL line-rate 关系：

```text
QPLL line rate = REFCLK × QPLL_N / (QPLL_M × TXOUT_DIV)
```

10.000Gbps 可由以下两组数学组合得到：

| REFCLK | QPLL_N | QPLL_M | TXOUT_DIV | 计算 line rate |
|---:|---:|---:|---:|---:|
| 125MHz | 80 | 1 | 1 | 10.000Gbps |
| 156.25MHz | 64 | 1 | 1 | 10.000Gbps |

当前工程中曾出现的 `QPLL_FBDIV_TOP=64` 不能在 125MHz REFCLK 下直接代表 10.000G。它在 125MHz 下对应约 8.000Gbps；只有在 156.25MHz REFCLK 下才对应 10.000Gbps。

本轮隔离参数包确认结果如下：

| 项目 | 125MHz + QPLL_N=80 | 156.25MHz + QPLL_N=64 |
|---|---|---|
| 是否被当前 GT Wizard 配置接受 | 接受 | 当前配置下拒绝 |
| 是否生成完整 example design / generated HDL | 是 | 否，最后一次 corrected run 未形成可信参数包 |
| 是否需要改变现有主工程 REFCLK 架构 | 否 | 是，需要重新确认板级 MGTREFCLK / IBUFDS_GTE2 / QPLLREFCLKSEL / XDC |
| 当前建议 | 优先作为后续 10.000G QPLL 候选 | 暂不作为当前主线 |

因此，在不改变当前 125MHz REFCLK 架构的前提下，后续若继续推进 10.000G QPLL profile，应优先采用：

```text
REFCLK = 125MHz
QPLL_N = 80
QPLL_M = 1
TXOUT_DIV = 1
```

但这仍只是参数确认结论，不等于 10G dynamic profile 已实现。

## 3. 参数包生成结果

### 3.1 125MHz / QPLL_N=80 参数包

生成目录：

```text
reports/qpll_10g_parameter_compare/10g_125m_qpll_n80/
```

该参数包已生成：

- copied XCI；
- generated IP；
- example design；
- selected property dump；
- QPLL common wrapper；
- GT channel generated HDL；
- user clock helper；
- generated XDC。

关键属性来自：

```text
reports/qpll_10g_parameter_compare/10g_125m_qpll_n80/gtwizard_10g_selected_properties.txt
reports/qpll_10g_parameter_compare/10g_125m_qpll_n80/example_design/gtwizard_0_ex/...
```

### 3.2 156.25MHz / QPLL_N=64 参数包

生成目录：

```text
reports/qpll_10g_parameter_compare/10g_156p25m_qpll_n64/
```

最后一次 corrected run 中，脚本尝试设置：

```text
identical_val_tx_reference_clock = 156.250
identical_val_rx_reference_clock = 156.250
gt0_val_qpll_fbdiv = 64
```

当前 GT Wizard / XCI 配置拒绝 `156.250` 作为 single clock source 的参考时钟值。生成摘要中记录：

```text
FAILED set_property CONFIG.identical_val_tx_reference_clock 156.250
FAILED set_property CONFIG.identical_val_rx_reference_clock 156.250
```

同时 Vivado 给出的有效参考时钟列表不包含 `156.250`。因此该目录中旧的 selected property 文件不能作为 156.25MHz 成功参数证据使用；当前只能记录为：

```text
156.25MHz / QPLL_N=64 package generation is blocked in the current GT Wizard configuration.
```

这不等价于板卡或器件绝对不支持 156.25MHz 方案，而是说明：在当前 XCI 基础和单时钟配置下，不能直接生成可信 156.25MHz / 10.000G 参数包。若后续选择 156.25MHz 路线，必须重新确认板级 MGTREFCLK 连接、IBUFDS_GTE2、QPLLREFCLKSEL、XDC 和 GT Wizard 输入时钟配置，而不能只把 `QPLL_FBDIV` 从 80 改成 64。

## 4. 10.000G / 125MHz / QPLL 参数提取

### 4.1 GT Wizard 顶层配置

| 参数 | 125MHz / QPLL_N=80 |
|---|---|
| line rate | 10.000Gbps |
| REFCLK | 125.000MHz |
| PLL type | QPLL |
| TXDATA width | 64 |
| TX internal datawidth | 32 |
| encoding | None |
| `gt0_val_qpll_refclk_div` | 1 |
| `gt0_val_qpll_fbdiv` | 80 |
| `gt0_val_cpll_txout_div` | 1 |
| `gt0_val_port_txsysclksel` | true |
| `gt0_val_port_qpllpd` | true |
| TX user clock source | TXOUTCLK |

注意：属性名 `gt0_val_cpll_txout_div` 是该版本 GT Wizard property 名称，虽然名称中带有 `cpll`，但在该 10G QPLL 参数包中用于记录 TXOUT_DIV 选择，实际 TX PLL 为 QPLL。

### 4.2 GTXE2_COMMON / QPLL 参数

从生成的 `gtwizard_0_common.v` 提取：

| 参数 | 125MHz / 10.000G QPLL |
|---|---|
| `QPLL_FBDIV_TOP` | 80 |
| `QPLL_FBDIV` encoding | `10'b0100100000` |
| `QPLL_FBDIV_RATIO` | `1'b1` |
| `QPLL_REFCLK_DIV` | 1 |
| `QPLL_CFG` | `27'h0680181` |
| `QPLL_CP` | `10'b0000011111` |
| `QPLL_LPF` | `4'b1111` |
| `QPLL_LOCK_CFG` | `16'h21E8` |
| `QPLL_INIT_CFG` | `24'h000006` |
| `QPLL_CLKOUT_CFG` | `4'b0000` |

这些值来自 Wizard 生成文件，不是手写 magic number。

### 4.3 GT channel 关键属性

从生成的 `gtwizard_0_gt.v` / `gtwizard_0_init.v` 提取：

| 参数 | 125MHz / 10.000G QPLL |
|---|---|
| `TX_DATA_WIDTH` | 64 |
| `TX_INT_DATAWIDTH` | Wizard primitive encoding = `1`，对应上层配置 `32` |
| `TXOUT_DIV` | 1 |
| `TXOUTCLKSEL` | `3'b010` |
| `TXSYSCLKSEL` | `2'b11` |
| `TX_QPLL_USED` | `"TRUE"` |
| `RX_QPLL_USED` | `"FALSE"` |
| QPLL reset helper | `gt0_qpllreset_out` 由 reset FSM 输出 |
| QPLL lock input | `gt0_qplllock_in` |
| QPLL refclk lost input | `gt0_qpllrefclklost_in` |

后续接入主工程时必须确保 `TXSYSCLKSEL=2'b11` 的 QPLL encoding 与当前 wrapper 中 CPLL/QPLL select 逻辑一致，并且不得用常量伪造 `QPLLLOCK`。

### 4.4 user clock helper 与 MMCM 静态参数

从生成的 `gtwizard_0_gt_usrclk_source.v` 提取 TX user clock MMCM：

| 项目 | 125MHz / 10.000G QPLL |
|---|---|
| MMCM input | `gt0_txoutclk_i` |
| `CLK_PERIOD` | 3.2ns |
| `MULT` | 2.0 |
| `DIVIDE` | 1 |
| `OUT1_DIVIDE` | 2 |
| `OUT0_DIVIDE` | 4.0 |
| `CLK1_OUT` | `gt0_txusrclk_i` |
| `CLK0_OUT` | `gt0_txusrclk2_i` |

由此得到：

| 时钟 | 频率 |
|---|---:|
| TXOUTCLK | 312.5MHz |
| TXUSRCLK | 312.5MHz |
| TXUSRCLK2 | 156.25MHz |
| MMCM VCO | 625MHz |

生成 XDC 同样给出 TXOUTCLK period 为 3.2ns。

### 4.5 MMCM DRP sequence 状态

GT Wizard example design 提供了静态 MMCM 参数，但没有直接生成与当前 `laser_tx` 动态 MMCM DRP controller 兼容的写寄存器序列。

因此本轮已确认：

```text
10G MMCM static parameters are extracted.
10G MMCM DRP sequence is not yet converted into the project-specific MMCM DRP table.
```

后续若要把 10G 接入动态 profile，必须使用当前工程已有的 MMCM DRP 表生成/转换方法，将上述静态 MMCM 参数转换为工程内 `MMCM_DRP_SEQ_PROFILE_10G` 等价序列，并做 readback / lock / frequency verify。不能直接把本报告中的静态参数当成已完成 DRP sequence。

## 5. 10G frequency counter 预期

当前动态 rate-switch 频率计数近似使用约 1ms 统计窗口。既有经验值为：

| Rate | TXUSRCLK2 | counter 约值 |
|---:|---:|---:|
| 500M | 7.8125MHz | 7812 |
| 1000M | 15.625MHz | 15625 |
| 1250M | 19.53125MHz | 19531 |
| 2000M | 31.25MHz | 31250 |
| 5000M | 78.125MHz | 78125 |
| 6250M | 97.65625MHz | 97656 |
| 10000M | 156.25MHz | 156250 |

因此 10.000G QPLL profile 的初始 expected value 可按：

```text
expected_txusrclk2_hz = 156250000
expected counter      ≈ 156250
```

后续动态集成时必须检查：

- `txusrclk2_freq_counter_axi` 位宽；
- profile table 的 min/max 位宽；
- VERIFY_RATE 比较位宽；
- Vitis 打印类型；
- ILA probe 位宽。

不能使用 16-bit 窗口，也不能用 QPLLLOCK / gt_ready 替代频率验证。

## 6. 125MHz 与 156.25MHz 方案对比

| 对比项 | 125MHz + QPLL_N=80 | 156.25MHz + QPLL_N=64 |
|---|---|---|
| 数学上是否可得 10.000G | 是 | 是 |
| 当前隔离 Wizard 是否生成完整包 | 是 | 否 |
| 是否保持当前 REFCLK 架构 | 是 | 否 |
| 是否需要 AD9528 / refclk 切换 | 否 | 需要进一步评估 |
| 是否需要确认板级 MGTREFCLK / XDC | 沿用当前 125MHz 路线 | 必须重新确认 |
| 当前推荐 | 优先 | 暂缓 |

选择原则：

1. 如果 125MHz 配置被 GT Wizard 接受，并生成完整 10.000G 参数，则优先采用 125MHz + QPLL_N=80，因为它不需要改变当前参考时钟架构。
2. 如果后续发现 125MHz + QPLL_N=80 在实现、时序或上板中存在不可解决问题，再评估 156.25MHz + QPLL_N=64。
3. 采用 156.25MHz 时必须确认板级 MGTREFCLK 连接、当前 GT Quad、IBUFDS_GTE2、QPLLREFCLKSEL 和 XDC，不能只改 `QPLL_FBDIV`。

## 7. 3.000G / 125MHz CPLL 结论

本轮同时记录 3.000G CPLL profile 判断：

```text
125MHz, CPLL, N1=4, N2=3, M=1, D=1
```

数学上可得到：

```text
line rate = 3.000Gbps
```

但此时：

```text
CPLLOUTCLK = 1.5GHz
```

该值低于 UG476 给出的 GTX CPLL 1.6GHz 标称下限。若尝试 `D=2`，又不存在合法的 `N1 × N2 = 24` 组合来得到 3.000G。

因此当前结论为：

```text
3000M / 125MHz CPLL = BLOCKED / unsupported
```

不要新增 `3000M` dynamic profile。已有 `3125M` profile 保持支持。

## 8. 后续接入 10G 前必须完成的项目

在把 `RATE_ID_10000M` 加入主工程前，至少还需要完成：

1. 将 10G MMCM 静态参数转换为工程内 MMCM DRP sequence；
2. 确认 10G 下 `txusrclk2_freq_counter_axi`、profile window 和 Vitis 打印位宽足够；
3. 确认当前 QPLL-capable wrapper 中 `GTXE2_COMMON` 参数能采用 `QPLL_FBDIV_TOP=80`、`QPLL_REFCLK_DIV=1` 等生成值；
4. 确认 QPLL reset / lock / refclk-lost 状态机闭环；
5. 确认 CPLL→QPLL、QPLL→CPLL 双向恢复语义；
6. 重新 synthesis / implementation / timing；
7. 用 UDP + AXI/FCLK ILA 做 CPLL 基线回归和 10G bring-up。

本报告不能作为：

- `rate set 10000` 已支持的证据；
- 10G dynamic switching 已通过的证据；
- 10G 眼图 / BER / 外部光口链路通过的证据；
- 156.25MHz REFCLK 路线已验证的证据。

## 9. 本阶段验证状态

| 项目 | 状态 |
|---|---|
| 主工程 RTL 修改 | 未修改 |
| 主工程 BD/XDC 修改 | 未修改 |
| Vitis/UDP 修改 | 未修改 |
| rate list 修改 | 未修改 |
| 10G / 125MHz / QPLL_N=80 参数包 | 已生成 |
| 10G / 156.25MHz / QPLL_N=64 参数包 | 当前 Wizard 配置下未闭环 |
| synthesis / implementation | 未运行 |
| bit / LTX | 未生成 |
| hardware test | 未运行 |

结论：

```text
10.000G / 125MHz / QPLL_N=80 是当前优先候选路线。
10.000G / 156.25MHz / QPLL_N=64 数学上成立，但当前 GT Wizard 配置未生成可信参数包，必须等板级 REFCLK 路径与 Wizard 输入时钟配置确认后再评估。
3000M / 125MHz CPLL 当前标记为 BLOCKED / unsupported。
```

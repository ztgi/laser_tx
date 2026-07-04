# GT 动态速率第一阶段：速率规划器与可行性核查

## 1. 阶段边界

本阶段只完成可行性核查和 dry-run 速率规划器，不真正改变 GTX line rate。

明确禁止并已遵守：

- 未修改 `laser_tx_core` 功能逻辑；
- 未修改 RTL / BD / XDC / GT Wizard；
- 未写 GT DRP；
- 未配置 AD9528 动态 clock-tree；
- 未破坏当前已验证的固定 500 Mb/s Profile 0；
- UDP 只新增 `rate status` 和 `rate plan <Mbps>`，不实现 `rate set <Mbps>`。

当前阶段回答的问题是：“如果以后要做动态速率，软件层应该如何表达目标速率、如何返回规划结果、当前工程还缺哪些硬件与时钟条件。”

## 2. 当前 GT Wizard / GTX 配置核查

本节基于源文件、XCI 和 wrapper 结构检查，未重新生成 GT Wizard，也未重新实现。

| 项目 | 当前核查结果 |
|---|---|
| GT 类型 | 7-series GTX，当前 wrapper 使用 `gtwizard_0` |
| 当前 line rate | 0.5 Gb/s |
| 外部 TXDATA 宽度 | `gt0_txdata_in[63:0]`，64 bit |
| TX_INT_DATAWIDTH | `gt0_val_tx_int_datawidth = 32` |
| 编码 | `gt0_val_encoding = None`，`gt0_val_port_tx8b10ben = false` |
| PLL | 当前 Profile 0 使用 CPLL；QPLL 输入在 wrapper 中未接入实际时钟 |
| MGTREFCLK | 当前 Profile 0 文档和 wrapper 指向本地 125 MHz MGTREFCLK0 |
| TXOUT_DIV | `gt0_val_cpll_txout_div = 8` |
| TXOUTCLK / TXUSRCLK | Profile 0 中按 15.625 MHz 约束和使用 |
| TXUSRCLK2 | Profile 0 中按 7.8125 MHz 约束和使用 |
| 时钟关系 | 当前固定 500 Mb/s / 64-bit / no encoding 语义下，`TXUSRCLK = 2 * TXUSRCLK2` |

结论：当前 Profile 0 的 64-bit 用户数据语义保持不变，`laser_tx_core` 仍工作在 `TXUSRCLK2 = 7.8125 MHz` 域，每拍 64 bit。动态速率规划不应把上层发送核心改成 32-bit。

## 3. 当前 DRP 条件核查

| 项目 | 当前状态 |
|---|---|
| channel DRP XCI 参数 | `gt0_val_drp = true` |
| DRP clock XCI 参数 | `gt0_val_drp_clock = 60` |
| wrapper 中 `gt0_drpclk_in` | 接 `ctrl_clk` |
| wrapper 中 `gt0_drpaddr_in` | 固定 `9'd0` |
| wrapper 中 `gt0_drpdi_in` | 固定 `16'd0` |
| wrapper 中 `gt0_drpen_in` | 固定 `1'b0` |
| wrapper 中 `gt0_drpwe_in` | 固定 `1'b0` |
| wrapper 中 `gt0_drpdo_out` / `gt0_drprdy_out` | 接未使用 wire |
| CPLL reset | 由 `ctrl_rst` 控制 |
| QPLL reset / common DRP | 当前 wrapper 未形成可软件控制的 common DRP 访问路径 |
| TX reset | 当前由 wrapper 内固定 reset 逻辑控制 |
| TXRESETDONE / CPLLLOCK | 当前可通过 GT status GPIO 回读 |

结论：IP 层 channel DRP 信号存在，但当前硬件 wrapper 没有把 DRP 控制面暴露给 PS/PL 状态机。现阶段不能声称具备运行时动态改速率能力。

## 4. 当前 AD9528 条件核查

| 项目 | 当前状态 |
|---|---|
| SPI 初始化 | `laser_ad9528_spi_init()` 已存在 |
| SPI 控制器 | PS SPI1，`LASER_SPI_DEVICE_ID` 来自 `xparameters.h` |
| Slave select | `LASER_AD9528_SPI_SLAVE = 1U` |
| chip ID / readback | `laser_ad9528_read_chip_id()` 和 `laser_ad9528_basic_check()` 已存在 |
| 动态 rate profile | `laser_ad9528_apply_rate_profile()` 当前返回 `XST_NO_FEATURE` |
| 完整 clock-tree | 当前未实现，按项目约束后置 |
| AD9528 输出到 MGTREFCLK 的精确通道 | 仍需结合原理图和板级时钟方案确认 |
| refclk mux / refsel | 当前工程未发现可用于动态切换的完整控制路径 |

结论：AD9528 目前只能支持最小 SPI/readback 层面的 bringup，尚不具备动态参考时钟配置能力。细步进速率必须等 AD9528 输出通道、寄存器表、IO update、lock/readback 和 GT refclk 连接全部确认后再展开。

## 5. 为什么不把“每个速率一个 Profile”作为最终架构

多个固定 Profile 适合早期验证典型点，例如 500M、1G、2.5G、5G、10G；但它不是最终动态调速接口的理想形态：

1. 每个 Profile 都需要独立 GT Wizard 参数、时钟约束、实现和 bit/LTX/XSA 管理，维护成本高；
2. UDP/上位机如果暴露 `profile_id`，会把用户接口绑死在内部实现细节上；
3. 后续一旦引入 AD9528 可变参考时钟，速率点可能从离散 Profile 扩展到搜索结果，`profile_id` 不能自然表达；
4. 真正面向用户的语义应是目标 line rate，即 `rate set <Mbps>`。

因此本阶段先做 `rate plan <Mbps>`，后续真实切换时复用同一套 `gt_rate_plan()` 结果。

## 6. 为什么最终接口采用 `rate set <Mbps>`

最终接口建议为：

```text
rate set <Mbps>
```

内部执行路径应是：

```text
rate set <Mbps>
  -> gt_rate_plan()
  -> disable TX
  -> configure AD9528 if needed
  -> submit rate control word to PL
  -> PL DRP/reset state machine
  -> wait lock/resetdone/ready
  -> return OK or ERR
```

本阶段只实现前两条只读/dry-run 命令：

```text
rate status
rate plan <Mbps>
```

## 7. 固定 125 MHz / 156.25 MHz 与细步进关系

固定 125 MHz 和 156.25 MHz 参考时钟只能得到有限离散速率点。若后续需要大量非典型速率，例如 1375、3680、9000 Mb/s，则不能只靠固定参考时钟和少量 TXOUT_DIV 组合，需要：

- AD9528 输出可变 MGTREFCLK；
- CPLL/QPLL 参数搜索；
- 合法 VCO 范围检查；
- TXUSRCLK / TXUSRCLK2 生成方式重新评估；
- XDC/timing 多模式或重新实现策略。

因此第一版 `gt_rate_plan()` 只支持典型点查表，非典型点返回 `ERR RATE_PLAN_UNSUPPORTED`。

## 8. `GtRatePlan` 数据结构

新增 `GtRatePlan` 结构体记录目标速率、实际速率、参考时钟来源、PLL 来源、TXUSRCLK2 频率、TXOUT_DIV、CPLL/QPLL 候选参数、是否需要 AD9528，以及备注。

该结构当前用于 UDP dry-run 输出；后续真实 `rate set <Mbps>` 应复用它作为软件和 PL 速率控制状态机之间的输入依据。

## 9. 第一版支持的典型速率点

| target Mbps | actual kbps | ref | pll | txusrclk2 Hz | 说明 |
|---:|---:|---|---|---:|---|
| 500 | 500000 | LOCAL_125 | CPLL | 7812500 | 当前 Profile 0 已验证路径，仅 dry-run 回报 |
| 1000 | 1000000 | LOCAL_125 | CPLL | 15625000 | 候选点，未做 DRP/bitstream 验证 |
| 1250 | 1250000 | LOCAL_125 | CPLL | 19531250 | 候选点，未做 DRP/bitstream 验证 |
| 2000 | 2000000 | LOCAL_125 | CPLL | 31250000 | 候选点，未做 DRP/bitstream 验证 |
| 2500 | 2500000 | LOCAL_125 | CPLL | 39062500 | 候选点，未做 DRP/bitstream 验证 |
| 3125 | 3125000 | LOCAL_15625 | CPLL | 48828125 | 候选点，156.25 MHz refclk 路径待确认 |
| 5000 | 5000000 | LOCAL_125 | QPLL | 78125000 | 候选点，QPLL bitfield 未验证 |
| 6250 | 6250000 | LOCAL_15625 | QPLL | 97656250 | 候选点，156.25 MHz refclk 路径待确认 |
| 10000 | 10000000 | LOCAL_15625 | QPLL | 156250000 | 候选点，需重新评估 timing/clocking |

不支持示例：

```text
rate plan 1375 -> ERR RATE_PLAN_UNSUPPORTED target=1375
rate plan 3680 -> ERR RATE_PLAN_UNSUPPORTED target=3680
rate plan 9000 -> ERR RATE_PLAN_UNSUPPORTED target=9000
```

## 10. UDP dry-run 命令

新增：

```text
rate status
rate plan <Mbps>
```

返回示例：

```text
rate status
OK RATE_STATUS mode=fixed_profile0 dynamic_hw=not_enabled

rate plan 1000
OK RATE_PLAN target=1000 actual_kbps=1000000 ref=LOCAL_125 pll=CPLL txout_div=4 txusrclk2_hz=15625000 dry_run=1

rate plan 1375
ERR RATE_PLAN_UNSUPPORTED target=1375

rate set 1000
ERR RATE_SET_UNSUPPORTED_DRY_RUN
```

`rate set` 只返回明确错误，不执行 DRP、不配置 AD9528、不改变 GT 速率。

## 11. 当前动态速率缺口

距离真实运行时动态改速率仍缺：

- PL 侧 DRP / reset / lock 状态机；
- DRP 控制寄存器或 AXI-lite/GPIO 控制面；
- channel DRP 与 common/QPLL DRP 的完整访问路径；
- CPLL/QPLL bitfield 映射和合法性搜索；
- TXOUT_DIV、TXUSRCLK、TXUSRCLK2 关系的动态重建方案；
- AD9528 动态输出频率配置；
- AD9528 输出到 MGTREFCLK 的板级连接确认；
- 切换失败 rollback 流程；
- 切换期间 `laser_tx_core` stop/flush/restart 规则；
- XDC/timing 多速率策略或每速率独立实现策略；
- 上板 lock/resetdone/ready 观测和恢复验证。

## 12. 当前阶段结论

当前是否真正改变 GT 速率：否，本阶段仅规划。

Profile 0 是否保留：是。当前 fixed 500 Mb/s Profile 0、GT Wizard、txusrclk2、`laser_tx_core` 数据路径、BRAM/GPIO/GT status 地址均未修改。

是否需要重新生成 bitstream：本阶段不需要，因为只修改 Vitis 应用软件和文档。

是否需要更新 Vitis platform：本阶段不需要，因为 XSA/BD/地址图未改变。

下一阶段建议：优先先完成“CPLL + 本地 125 MHz REFCLK 的少数典型点真实切换可行性验证”，并在此之前补齐 PL DRP/reset 状态机；AD9528 可变 REFCLK 应作为下一小阶段单独验证，不建议与第一次 DRP 切换同时叠加。

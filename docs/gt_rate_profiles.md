# GT rate profile

当前采用“编译期固定 profile”策略，而不是运行时动态改速率。当前版本只支持固定 500 Mb/s Profile 0；UDP 动态控制暂不实现，运行时 GTX 动态速率切换暂不实现。

后续必须在 Profile 0 完成上板 ILA 验证后，才能展开 UDP 业务参数控制、多固定 profile 评估或真正运行时 GTX 动态速率切换。每个新增 profile 必须由独立的 GT Wizard/XCI、时钟方案、bitstream 和对应 XSA 表示，或经过单独评审的受控切换方案表示。

| Profile | 状态 | Line rate | REFCLK | 外部 TXDATA | 编码 | TXUSRCLK | TXUSRCLK2 |
|---|---|---:|---:|---:|---|---:|---:|
| 0 | 已接入并完成实现，待上板验证 | 0.5 Gb/s | 125 MHz | 64 bit | None | 15.625 MHz | 7.8125 MHz |
| 1 | 预留 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 |
| 2 | 预留 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 | 待确认 |

Profile 0 的关键点：

- GT 外部 `gt0_txdata_in[63:0]` 保持 64 bit；
- XCI 中 `gt0_val_tx_int_datawidth = 32`，表示 GT 内部 datapath 语义为 32 bit；
- 无 8b/10b 编码时，`TXUSRCLK = line_rate / 32 = 15.625 MHz`；
- 无 8b/10b 编码时，`TXUSRCLK2 = line_rate / 64 = 7.8125 MHz`；
- `TXUSRCLK = 2 * TXUSRCLK2`；
- `laser_tx_core` 每个 `TXUSRCLK2` 周期输出 64-bit word，`valid_mask[63:0]` 每一位仍对应一个串行 bit。

因此 Profile 0 的 payload bit cadence 为：

```text
64 bit / 128 ns = 500 Mb/s
```

不要因为 `gt0_val_tx_int_datawidth = 32` 把 `laser_tx_core` 改成 32-bit 数据路径；32-bit 内部 datapath 只影响 GT 用户时钟关系。

## 运行时命令

在尚未实现并验证以下闭环前，`SET_GT_RATE_PROFILE` 必须返回 `UNSUPPORTED_RUNTIME_RATE_CHANGE`：

- AD9528 输出重配置；
- GT DRP；
- PLL/TX reset；
- 用户时钟重新稳定；
- `laser_tx_core` 安全停止和重新启动；
- 状态与错误 readback。

当前不能声称支持动态改速率。详细后置计划见 `docs/deferred_udp_dynamic_rate_plan.md`。

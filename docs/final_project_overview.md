# laser_tx 工程概览

当前数据链路为：

```text
PS -> AXI BRAM / AXI GPIO -> laser_tx_core -> 64-bit GT TX -> gtx_txp_out/gtx_txn_out
```

## 当前版本边界

当前版本只支持固定 500 Mb/s Profile 0。

```text
Line rate      = 500 Mb/s
GT TXDATA      = 64 bit
TXUSRCLK       = 15.625 MHz
TXUSRCLK2      = 7.8125 MHz
laser_tx_core  = TXUSRCLK2 domain
发送语义        = 64 bit / TXUSRCLK2 cycle
```

UDP 动态控制、运行时 GTX 动态速率切换、多个 GT rate profile 和完整 AD9528 clock-tree 均暂不实现。后续必须在固定 500 Mb/s Profile 0 上板验证通过后再展开。

## 子系统状态

| 子系统 | 当前状态 |
|---|---|
| PL pattern 核心 | 已存在；当前保持 64-bit word 发送语义 |
| GT Profile 0 | 已集成，已完成 bitstream/XSA；待上板 ILA 验证 |
| GT user clocking | 已修正为 `TXUSRCLK=15.625 MHz`、`TXUSRCLK2=7.8125 MHz` |
| TX ILA | 应采样 `TXUSRCLK2=7.8125 MHz` 域 |
| AD9528 | 仅允许最小 SPI readback，未配置完整 clock-tree |
| UDP/lwIP | 暂停，未实现 |
| 运行时 GTX 动态速率切换 | 暂停，未实现 |
| Vitis platform/BSP | 必须使用 `laser_tx_board_top_gt_profile0.xsa` 重建 |

顶层关系保持为 `laser_tx_board_top -> system_wrapper -> system_i`；不直接编辑生成的 wrapper。

物理高速输出仅为 `gtx_txp_out/gtx_txn_out`。`eom_out`、`soa_gate_out`、`acq_trig_out`、`acq_gate_out` 是同步/调试输出，不是额外光口。

# 后置 UDP 动态调速的阶段计划

## 当前版本边界

当前版本只支持固定 500 Mb/s GT Profile 0。

Profile 0 的已实现目标是让固定 500 Mb/s 模式下的 GT TX user clocking 自洽：

```text
Line rate      = 500 Mb/s
GT TXDATA      = 64 bit
TXUSRCLK       = 15.625 MHz
TXUSRCLK2      = 7.8125 MHz
laser_tx_core  = TXUSRCLK2 domain
发送语义        = 64 bit / TXUSRCLK2 cycle
```

该修复不等于已经实现运行时 GTX line rate 动态切换。当前工程不得把 laser_tx_core 的业务参数配置、UDP 控制和 GTX line rate 切换混在一起实现。

## 当前 TODO 标记

| 项目 | 当前状态 | 处理规则 |
|---|---|---|
| 固定 500 Mb/s Profile 0 | 当前唯一支持版本 | 优先完成上板 ILA 验证 |
| UDP server / lwIP | 暂不实现 | Profile 0 上板通过前不展开 |
| UDP 动态控制 | 暂不实现 | 后续仅先控制 laser_tx_core 业务参数 |
| 运行时 GTX 动态速率切换 | 暂不实现 | 必须后置到 Profile 0 验证之后 |
| 多 GT rate profile | 暂不引入 | 需要独立 bitstream 或受控 profile 切换方案评估 |
| AD9528 完整 clock-tree | 暂不修改 | 当前只允许最小 SPI readback |
| `SET_GT_RATE_PROFILE` | 不支持 | 必须返回 `UNSUPPORTED_RUNTIME_RATE_CHANGE` |

## 当前优先目标：固定 500 Mb/s Profile 0 上板 ILA 验证

上板时只验证固定 Profile 0，不叠加 UDP、lwIP、动态改速率或完整 AD9528 clock-tree。

必须检查：

1. 下载的 bitstream 是否为最新生成的 `laser_tx.runs/impl_1/laser_tx_board_top.bit`；
2. Vitis platform/BSP 是否使用最新 `laser_tx_board_top_gt_profile0.xsa` 重建；
3. CPLL lock 是否为 1；
4. TX MMCM lock 是否为 1；
5. TX reset done 是否为 1；
6. `gt_ready` 是否为 1；
7. TX ILA 采样时钟是否为 7.8125 MHz；
8. `laser_tx_core` 是否确实运行在 `TXUSRCLK2` 域；
9. `phase_start_pulse`、`valid_mask`、`txdata`、`eom_out`、`soa_gate_out`、`acq_trig_out`、`acq_gate_out` 的单拍宽度是否为 128 ns；
10. pattern / gap / phase 节拍是否符合 `64 bit / TXUSRCLK2 cycle`。

## 阶段一：UDP 只控制 laser_tx_core 业务参数

进入条件：固定 500 Mb/s Profile 0 已经完成上板 ILA 验证。

允许 UDP 控制：

- start / stop；
- repeat_cycles；
- gap_len_bits；
- insert_after；
- direct pattern；
- PRBS seed；
- pattern source；
- loop / phase 配置。

禁止 UDP 控制：

- GTX line rate；
- CPLL/QPLL 参数；
- TXOUT_DIV；
- TXUSRCLK/TXUSRCLK2；
- GT reset sequence；
- AD9528 clock-tree。

## 阶段二：多个固定 GT profile 方案评估

进入条件：阶段一稳定，且用户确认需要多速率。

候选 profile 可包括：

- 500M；
- 1G；
- 2.5G；
- 5G；
- 10G。

每个 profile 必须独立确认：

- GT Wizard/XCI 参数；
- TXDATA 宽度；
- 内部 datapath；
- 编码方式；
- CPLL/QPLL；
- TXOUT_DIV；
- TXUSRCLK/TXUSRCLK2；
- XDC/timing；
- bitstream 或受控 profile 切换方案；
- 上板 lock/reset/status。

在该阶段仍不默认承诺真正运行时动态改速率。

## 阶段三：真正运行时 GTX 动态速率切换研究

进入条件：多个固定 profile 已经单独验证，且用户确认要投入动态切换设计。

该阶段需要单独设计：

- GT DRP 配置流程；
- CPLL/QPLL 切换策略；
- TXOUT_DIV 切换策略；
- TXUSRCLK/TXUSRCLK2 clocking reconfiguration；
- GT TX reset sequence；
- lock / reset done / ready 状态机；
- XDC/timing 多模式约束；
- AD9528/refclk 关系；
- 软件状态机和错误恢复；
- 切换期间 laser_tx_core 的停止、清空、恢复流程。

未完成该阶段前，`SET_GT_RATE_PROFILE` 必须保持 `UNSUPPORTED_RUNTIME_RATE_CHANGE`。

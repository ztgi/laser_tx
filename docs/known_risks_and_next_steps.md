# 已知风险与下一步

## 当前 TODO 状态

| 项目 | 状态 |
|---|---|
| 固定 500 Mb/s Profile 0 | 当前唯一支持版本，优先上板验证 |
| UDP server / lwIP | 暂不实现 |
| UDP 动态控制 laser_tx_core 业务参数 | Profile 0 上板通过后再做 |
| 运行时 GTX 动态速率切换 | 暂不实现 |
| 多个 GT rate profile | 暂不引入 |
| AD9528 完整 clock-tree | 暂不修改 |
| `SET_GT_RATE_PROFILE` | 必须返回 `UNSUPPORTED_RUNTIME_RATE_CHANGE` |

## 固定 500 Mb/s Profile 0 上板检查

1. 下载最新 bitstream：`laser_tx.runs/impl_1/laser_tx_board_top.bit`。
2. 确认 Vitis platform/BSP 来自最新 XSA：`laser_tx_board_top_gt_profile0.xsa`。
3. 检查 GT status：
   - CPLL lock = 1；
   - TX MMCM lock = 1；
   - TX reset done = 1；
   - `gt_ready` = 1。
4. 检查 TX ILA：
   - 采样时钟为 `TXUSRCLK2 = 7.8125 MHz`；
   - `laser_tx_core` 运行在 `TXUSRCLK2` 域；
   - `phase_start_pulse`、`eom_out`、`soa_gate_out`、`acq_trig_out`、`acq_gate_out` 的单拍宽度为 128 ns；
   - `txdata/valid_mask` 的节拍符合 `64 bit / TXUSRCLK2 cycle`。
5. 检查 pattern / gap / phase：
   - direct 63-bit；
   - PRBS6；
   - direct 127-bit；
   - PRBS7；
   - gap；
   - 非法配置。

## 仍需注意的风险

1. GT Wizard XCI 来自同板卡参考工程。虽然 Profile 0 已完成 synthesis/implementation/timing/bitstream/XSA，但上板前仍需确认实际 XC7Z100 GT lane、REFCLK、光模块和管脚匹配。
2. `report_cdc` 当前仍存在 AXI↔TX 域 Critical 项，需要后续按端点拆分；不能把当前 CDC 状态声明为完全干净。
3. AD9528 当前只允许最小 SPI readback，不写完整 clock-tree 寄存器。
4. 旧 `xparameters.h` 不再作为软件依据；使用新 XSA 后必须依赖新 BSP 生成的 `xparameters.h`。
5. 当前 Vitis IDE 应用工程仍需确认是否已切换到 `laser_tx_gt_profile0_platform`。
6. UDP/lwIP、完整 AD9528 配置、GT 动态速率切换均按优先级后置。

详细阶段计划见 `docs/deferred_udp_dynamic_rate_plan.md`。

# laser_tx GT Profile 0 阶段工程变更报告

## 已实现

- 新增固定 Profile 0 的 `laser_gt_tx_profile0`：64-bit GT TX、0.5 Gb/s、125 MHz MGTREFCLK、CPLL、无 8b/10b。
- `laser_tx_core` 的发送使能增加 `gt_ready` 硬件门控；GT 未 ready 时不允许启动发送。
- BD 新增只读 `axi_gpio_gt_status`（`0x4002_0000`），向 PS 回读 CPLL lock、TX reset done、ready 和 Profile 号。
- 完成 GT Wizard 导入、BD 连接、GT/AXI 异步时钟组约束、wrapper 重新生成。
- 导出新的 XSA，并从该 XSA 重新生成 standalone BSP。
- UART_TEST 已增加：GT 状态打印、AD9528 SPI 最小只读、当前测试 case 打印，以及运行时改速率返回 `UNSUPPORTED_RUNTIME_RATE_CHANGE`。

## 已编译

| 项目 | 结果 | 证据 |
|---|---|---|
| `validate_bd_design` | 通过 | `scripts/bd_connect_laser_tx_core.tcl` 执行日志 |
| GT output products / HDL wrapper | 已生成 | Vivado 批处理构建日志 |
| synthesis | 完成 | `reports/gt_profile0/build_gt_profile0_cdc_hook.log` |
| implementation | 完成 | `reports/gt_profile0/build_gt_profile0_cdc_hook.log` |
| timing | 通过 | Setup WNS 7.029 ns、TNS 0；Hold WHS 0.172 ns、THS 0 |
| bitstream | 已生成 | `laser_tx.runs/impl_1/laser_tx_board_top.bit` |
| XSA | 已导出 | `laser_tx_board_top_gt_profile0.xsa` |
| 新 platform/BSP | 已生成 | `vitis_bringup/laser_tx_gt_profile0_platform` |
| UART_TEST 源码 | 已用新 BSP 直接编译、链接 | `tmp/uart_test_profile0_recheck/uart_test_profile0.elf`，text/data/bss=33029/1192/22648 bytes |

## 待上板验证

- 125 MHz REFCLK、AB1/AB2 光口管脚及光模块兼容性。
- AD9528 SPI1/SS1 的实际 readback 值；当前软件不写 clock-tree 寄存器。
- GT ready、DIRECT63、PRBS6、DIRECT127、PRBS7、gap/非法配置的串口和 ILA 波形。
- 现有 Vitis IDE 应用工程仍需切换/重建到新 platform；直接编译验证不等同于 IDE 工程已迁移。

## 待用户确认

- `gtwizard_0.xci` 来自同板卡参考工程，但生成时有器件族脚本警告；虽已通过综合、实现和时序，仍应在上板前确认其 GT Wizard Profile 0 与 XC7Z100 实际收发器通道匹配。
- 不实施 UDP/lwIP、完整 AD9528 时钟树或运行时 GT 改速率，直至 UART_TEST 上板通过且用户另行确认。

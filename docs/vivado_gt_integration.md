# Vivado GT Profile 0 集成说明

`laser_gt_tx_profile0` 位于 `laser_tx_board_top`，不直接放入 `system.bd`。BD 只负责将 `txdata`、`valid_mask`、`txusrclk2`、`tx_rst`、`gt_ready` 和 `gt_status_in` 在 wrapper 边界连通；顶层将它们接到 GT 适配模块。

| 项目 | 配置 |
|---|---|
| GT 外部 TXDATA 宽度 | 64 bit |
| GT 内部 datapath 语义 | 32 bit，`gt0_val_tx_int_datawidth = 32` |
| Profile 0 line rate | 0.5 Gb/s |
| REFCLK | 本地 125 MHz MGTREFCLK0 |
| PLL | CPLL |
| 编码 | None，无 8b/10b |
| `TXOUTCLK` | 15.625 MHz，64 ns |
| `TXUSRCLK` | 15.625 MHz，64 ns |
| `TXUSRCLK2` | 7.8125 MHz，128 ns |
| `laser_tx_core` 时钟域 | `TXUSRCLK2` |
| TX 引脚 | `gtx_txp_out=AB2`，`gtx_txn_out=AB1` |
| REFCLK 引脚 | `gt_refclk125_p/n=U8/U7` |

当前 Profile 0 的 GTX 用户时钟结构复用了 GT Wizard example design 的思路：`TXOUTCLK` 先进入 BUFG，再送入 `MMCME2_ADV`，由 MMCM 产生同源、低 skew 的 `TXUSRCLK` 和 `TXUSRCLK2`。

具体参数为：

| MMCM 输出 | 用途 | 频率 | 周期 |
|---|---|---:|---:|
| `CLKOUT1 /39` | GT `gt0_txusrclk_in` | 15.625 MHz | 64 ns |
| `CLKOUT0 /78` | GT `gt0_txusrclk2_in`、`laser_tx_core/txusrclk2`、TX ILA | 7.8125 MHz | 128 ns |

不要把 `TXUSRCLK2` 直接接成 `TXOUTCLK`，也不要用普通 fabric toggle/divider 产生 GT 用户时钟。

## 构建与约束

`scripts/build_gt_profile0.tcl` 会执行：

1. 生成/刷新 GT Wizard output products；
2. 先运行 `gtwizard_0_synth_1`；
3. 重新生成 wrapper；
4. 运行 top-level synthesis、implementation、timing；
5. 生成 bitstream；
6. 导出 XSA。

`scripts/gt_profile0_impl_pre.tcl` 在 implementation 中检查以下时钟周期，若不满足会直接报错：

- `TXOUTCLK`：64.000 ns；
- `TXUSRCLK`：64.000 ns；
- `TXUSRCLK2`：128.000 ns。

该脚本还会为 `clk_fpga_0` 与 GT TX user-clock group 建立异步 clock group。该约束只覆盖已经由 RTL 显式同步的 AXI↔TX 跨时钟控制/状态路径，不放宽同域数据路径。

板级 GT/光口功能尚未通过实物验证。使用 bitstream 前仍需在 Hardware Manager 中确认 GT lock/reset/status，并用 ILA 检查 `laser_tx_core` 是否确实在 `TXUSRCLK2=7.8125 MHz` 域运行。

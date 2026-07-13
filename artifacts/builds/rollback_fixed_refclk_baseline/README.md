# rollback_fixed_refclk_baseline 可烧写回退包

## 用途与来源

本包是 AD9528 OUT0 measurement/readback 接入前的固定 125MHz GTX 回退基线。源码固定在 `feature/add-625m-4000m-cpll-profiles` 的 `12d3b71`；该提交包含 625M/4000M 正式支持收口，硬件功能提交为 `51005ec`，软件正式 supported 收口提交为 `2eb6b64`。

- 板卡/器件：ZYNQ XC7Z100-2FFG900；
- 工具：Vivado 2022.2 / Vitis 2022.2；
- top / run：`laser_tx_board_top` / 隔离重建的 `impl_1`；
- GT MGT REFCLK：固定 125MHz；
- bit/LTX/XSA：从 `12d3b71` 隔离 worktree 的同一次实现重新生成；
- ELF：从本包 XSA 新建 platform/domain 后完成 managed clean build。

## 功能边界

- 包含固定 125MHz REFCLK 下的 11 档离散 profile：500、625、1000、1250、2000、2500、3125、4000、5000、6250、10000Mbps；
- 10000M 使用固定 125MHz QPLL profile，其余为已集成 CPLL profile；
- 不包含 AD9528 OUT0 Bank110 frequency counter；
- 回滚 PL 不包含 AD9528 OUT0 measurement counter/status；本包 ELF 使用同一历史源码快照 `12d3b71` 的 application sources 完成 managed clean build，不包含 `laser_ad9528_measure.c` 及 measurement 命令；
- 不包含 AD9528 到 Bank111 `GTNORTHREFCLK` 路径；
- 不包含 PLL2 TEST0；
- `3000M/FIXED_125M_CPLL` 仍为 `BLOCKED`。

## 推荐烧写顺序

1. 使用 `hardware/laser_tx_fixed_refclk_baseline.bit` program FPGA；
2. Hardware Manager 加载配对的 `hardware/laser_tx_fixed_refclk_baseline.ltx`；
3. `rst -processor`；
4. 下载并运行 `software/laser_tx_udp_bringup.elf`；
5. 执行 UDP `PING`、`rate list`、`rate status`，再进行所需档位回归；不要在回滚 PL 上使用 AD9528 measurement 结果作结论。

不得将 measurement 包的 ELF、XSA 或 LTX 与本包 bit 混用。

## 已完成验证与边界

`12d3b71` 对应文档记录 625M/4000M 已完成初步上板验证并提升为正式 supported profile；更早的固定 125MHz CPLL/QPLL 档位证据见各编号报告。本次归档重新构建 bit/LTX/XSA/ELF，但没有重新执行整套板级回归，因此“本次重建产物的 hardware regression”仍标记为未执行。

## 尚未验证

- 本次重建包的重新上板冒烟/全档循环；
- 外部光口 BER、眼图和长期稳定性；
- AD9528 OUT0 测量与 PLL2；
- AD9528 参考时钟接入 GT；
- 任意连续速率。

## 回退方法

从 measurement 构建回退时，必须一起替换本目录中的 bit、LTX 和 ELF。XSA用于重建/复核 platform，不直接替代烧写文件。回退后执行 `rst -processor` 并重新运行本包 ELF。

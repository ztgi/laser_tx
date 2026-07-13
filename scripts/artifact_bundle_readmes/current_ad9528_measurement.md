# current_ad9528_measurement 可烧写产物包

## 用途与来源

本包用于当前 AD9528 OUT0 Bank110 频率测量及 PS/UDP 软件回读。硬件基线来自 `feature/ad9528-out0-software-measurement-readback` 的硬件提交 `b6ada09`，软件源收口到 `feature/ad9528-pll2-test0-register-image-audit` 的 `8f38b71`。打包时所在分支和精确哈希以同目录 `manifest.json` 为准。

- 板卡/器件：ZYNQ XC7Z100-2FFG900；
- 工具：Vivado 2022.2 / Vitis 2022.2；
- top / run：`laser_tx_board_top` / `impl_1`；
- GT MGT REFCLK：现有固定 125MHz；
- bit/LTX：来自同一次 implemented design；
- ELF：从本包 XSA 新建 platform/domain 后完成 managed clean build。

## 功能边界

- 包含 AD9528 OUT0 经 Bank110 `IBUFDS_GTE2.ODIV2` 的频率计数；
- 包含 PS/UDP measurement readback；
- 不包含 PLL2 TEST0 写入；
- 不包含 AD9528 到 Bank111 `GTNORTHREFCLK` 的功能连接；
- 不新增 supported rate；
- `3000M/FIXED_125M_CPLL` 仍为 `BLOCKED`；
- 当前 OUT0 VCXO candidate 已通过 FPGA 内部计数和 UDP 回读，未完成外部仪器测量。

## 推荐烧写顺序

1. 使用 `hardware/laser_tx_ad9528_measurement.bit` program FPGA；
2. Hardware Manager 加载配对的 `hardware/laser_tx_ad9528_measurement.ltx`；
3. `rst -processor`；
4. 下载并运行 `software/laser_tx_udp_bringup.elf`；
5. 先执行 UDP `PING`/状态检查，再执行 AD9528 只读或 candidate 测试命令。

不得把本包 bit 与其它目录 LTX 混用，也不得把本包 ELF 与旧 XSA/旧 bit 搭配。

## 已完成验证

- implementation timing、route、DRC 和 debug core 报告已归档；
- AD9528 OUT0 candidate 下 FPGA 内部计数约对应 122.872～122.874MHz；
- restore 后计数归零/不再 alive；
- PS/UDP measurement readback 已完成上板检查；
- 原有 11 档离散 GT profile 未因该测量链路而改变。

## 尚未验证

- 外部示波器/频率计实测；
- AD9528 PLL2 TEST0；
- AD9528 到 Bank111 GTX 参考时钟接入；
- 新 GT 速率或连续调速；
- 外部光口 BER、眼图和长期稳定性。

## 回退方法

如需排除 AD9528 measurement/PS readback 增量，完整切换到相邻的 `rollback_fixed_refclk_baseline` 包：bit、LTX、XSA 对应 ELF 必须整套替换，不能只替换单个文件。

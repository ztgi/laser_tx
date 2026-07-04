# Vitis UART_TEST 说明

新硬件平台为 `laser_tx_board_top_gt_profile0.xsa`，生成的 standalone platform/BSP 位于 `vitis_bringup/laser_tx_gt_profile0_platform`。软件必须从该 BSP 的 `xparameters.h` 获取 GPIO、BRAM、GT status GPIO 和 SPI1 标识，不能继续使用旧 BSP。

`bringup/src/main.c` 当前选择 `UART_TEST`。启动后打印：控制 GPIO/BRAM 基地址、GT status GPIO、PS SPI1/SS1、当前 test case、运行时速率设置不支持、AD9528 最小 readback、GT 状态与 `gpio_status`。未实现 UDP。

AD9528 使用 PS SPI1、SS1、强制 slave select 和仅三个字节的寄存器读事务；不写任何完整 clock-tree 表。运行时速率切换函数明确返回 `XST_NO_FEATURE`，串口表示为 `UNSUPPORTED_RUNTIME_RATE_CHANGE`。

源码已直接用新 BSP 编译/链接成功；仍需在 Vitis GUI/XSCT 将 application 工程迁移到新 platform 后再执行板上 UART_TEST。

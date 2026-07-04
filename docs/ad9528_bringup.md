# AD9528 bring-up

## 已确认硬件映射

PS 使用 SPI1 EMIO；SS0 对应 ADRV9009，SS1 对应 AD9528。当前 XDC：SCLK AJ24、MOSI AH23、MISO AH24、AD9528 SS1 AK23，均为 LVCMOS25。SS2 不导出。

## 本阶段边界

待新增的 `laser_ad9528.c/h` 只应完成：SPI1 初始化、选择 SS1、单寄存器读写、chip ID 读取、基础通信检查和 `apply_rate_profile()` 预留接口。

完整 AD9528 clock-tree、PLL、output divider 与 IO-update 序列尚未根据当前板卡正式时钟方案确认；不得从参考工程盲拷完整寄存器表后宣称可用。

## 上板最小检查

1. 从新 XSA 的 `xparameters.h` 确认 `XPAR_PS7_SPI_1_DEVICE_ID`。
2. 以 SS1 进行 AD9528 chip-ID 读回。
3. 失败时停止 GT 启动，打印 SPI/片选/读回值。
4. 完整时钟配置确认前，不执行动态改速率。

Hardware test was not run。

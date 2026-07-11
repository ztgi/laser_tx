# AD9528 真实运行配置只读寄存器读取报告

## 1. 修改摘要

本阶段在 `vitis_bringup/bringup/src/laser_ad9528.c/.h` 增加 `laser_ad9528_dump_runtime_state()`、UART 原始/解析打印和状态格式化接口；在 `laser_udp_server.c` 增加只读命令：

```text
ad9528 status
ad9528 dump
```

`status` 返回紧凑状态，`dump` 在 UART 输出完整原始寄存器与解析字段后返回同一紧凑状态。接口不提供任意地址写入，不改变现有 `rate` 命令。

## 2. 修改前问题

当前 `laser_tx` 只执行 `laser_ad9528_spi_init()` 和 chip-ID 基础读回；`laser_ad9528_apply_rate_profile()` 固定返回 `XST_NO_FEATURE`。因此无法判断正在运行的 AD9528 是否锁定、OUT0 配置的 source/divider 是什么，或是否可由寄存器条件推导频率。

只读审计结果如下：

| 位置 | 结论 |
| --- | --- |
| 当前 `laser_tx` UDP 启动链路 | 未调用 AD9528 clock-tree 配置，仅新增 SPI 初始化供只读命令使用 |
| 当前 `laser_tx` FSBL/QSPI | 未发现 AD9528 初始化表或 IO_UPDATE/SYNC 调用 |
| 当前 `laser_tx` Linux/device tree | 未发现 Linux AD9528 driver/device-tree 配置 |
| `project_gtx/software_src/laser_tx_rate/ad9528_rate.c` | 有 PLL1 bypass、PLL2/OUT0 写入、IO_UPDATE/SYNC 的参考实现 |
| 外部参考代码可信度 | 不是当前 `laser_tx` 已执行镜像；不得当作当前板卡真值 |

旧 bit/ELF、外部启动镜像或其它板级软件仍可能保留配置；在实际运行新 ELF 并读取前，当前运行 image 为 UNKNOWN。

## 3. 修改后结构

只读读取路径：

```text
UDP "ad9528 status|dump"
  -> laser_ad9528_dump_runtime_state()
  -> SPI1 / SS1 只读 transaction
  -> 原始寄存器快照
  -> 保守字段解析
  -> UART 完整输出 + UDP 紧凑状态
```

读取的寄存器集合来自 AD9528 数据手册与本地 ADI 参考驱动定义：

| 内容 | 寄存器 |
| --- | --- |
| Chip ID / revision 原始字段 | `0x0006..0x0003` |
| PLL1 control | `0x010A..0x0108` |
| PLL2 CTRL/VCO/M1/R1/N2 | `0x0202`、`0x0203`、`0x0204`、`0x0207`、`0x0208` |
| OUT0 distribution control | `0x0302..0x0300` |
| global/channel power-down | `0x0500`、`0x0502..0x0501` |
| STATUS0/STATUS1/status enable | `0x0505..0x0507` |
| calibration / PLL readback | `0x0509..0x0508` |

读取失败会在 UART 报告 `reg=0x....` 与返回状态；UDP 返回 `failed_reg`。实现不调用 `laser_ad9528_write()`、RESET、IO_UPDATE、SYNC 或 SYSREF request。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| AD9528 运行状态 | 仅 chip-ID 基础检查 | 可读取 PLL/OUT0/power/status 原始值 | 只读观测 |
| UDP 命令 | 无 AD9528 状态命令 | `ad9528 status` / `ad9528 dump` | 新增只读调试命令 |
| AD9528 写事务 | `apply_rate_profile()` 未实现 | 未改变，仍未实现 | 不改变时钟树 |
| IO_UPDATE/SYNC | 不操作 | 不操作 | 不改变 active 配置 |
| rate set / GPIO | 现有行为 | 未改 | 无 PL 切速率影响 |

## 5. 硬件接口一致性说明

软件继续使用现有 PS SPI1 EMIO 和 `LASER_AD9528_SPI_SLAVE = 1`（SS1）。不修改 Device ID、SPI mode、SPI prescaler、EMIO 引脚、AXI 地址、GPIO bitfield 或 XSA。

`laser_ad9528_spi_init()` 仅初始化 PS SPI 控制器与选择 SS1；dump 随后只发读 transaction。没有配置写、IO_UPDATE、SYNC、SYSREF_REQ、输出 enable/power-down 事务。

XSA / Platform / BSP dependency unchanged。

## 6. active 与 buffered 寄存器语义

AD9528 具有编程寄存器与 IO_UPDATE 生效机制。普通 SPI readback 在未确认 serial-port read mode、最近 IO_UPDATE 和器件文档特定 active-readback 语义时，不能单独证明模拟 PLL、divider 或输出 mux 的实时生效状态。

因此本实现统一标记：

```text
runtime_image_confidence=REGISTER_READBACK_ONLY
```

仅当 PLL1 bypass 的三个相关位均符合参考定义、R1/N2/M1 合法且 OUT0 source 为 VCO 时，才按照板卡已知 122.88 MHz VCXO 作**条件性寄存器推导**。否则 `vco_hz` / `out0_hz` 返回 `UNKNOWN`。即使已推导，也不能提升为 `RUNTIME_IMAGE_CONFIRMED`；仍需频率测量交叉验证。

IO_UPDATE、SYNC 的“当前是否已经发生”不能由本次静态读取可靠确认，报告保持 UNKNOWN。

## 7. 构建与测试验证

完成的静态检查：

```text
git diff --check
全仓库初始化来源只读搜索
AD9528 地址/bitfield 与本地 ADI 参考驱动对照
dump 函数调用路径检查：仅 laser_ad9528_read()
```

Vitis clean build 未完成：本机没有可用 Vitis ARM toolchain 或 `make`。尝试执行 `make -C vitis_bringup/bringup/Debug clean all` 在启动前即报 `make` not found，因此没有产生“软件编译通过”的结论。

Hardware test was not run。没有 UART/UDP 实际 dump、没有 SPI readback 截图、没有 AD9528 lock 结果。

## 8. 内存与启动风险说明

新增结构体仅保存小型寄存器快照；未添加大缓冲区、DMA、heap 分配或 linker script 修改。由于 Vitis build 未运行，ELF/map 的最终内存使用尚未确认。

## 9. 修改文件列表

| 文件 | 修改 |
| --- | --- |
| `vitis_bringup/bringup/src/laser_ad9528.h` | 新增 runtime-state 数据结构与只读 API |
| `vitis_bringup/bringup/src/laser_ad9528.c` | 新增寄存器只读、解析、UART/UDP 格式化与失败地址记录 |
| `vitis_bringup/bringup/src/laser_udp_server.c` | 新增 `ad9528 status|dump`，并初始化只读 SPI 接口 |

## 10. 风险与后续建议

1. 必须使用**新 ELF** 上板，执行 `ad9528 dump`，保存 UART 原始值与 UDP response。
2. 若 dump 失败，先核查 SPI1 EMIO、SS1、SPI mode、板级 reset/供电；不要切换 GT 或写 AD9528。
3. 若可解析 OUT0，仍须用独立频率计数/示波器测量验证，才可把 confidence 提升为 `RUNTIME_IMAGE_CONFIRMED`。
4. 当前不定义 `AD9528_GT_REFCLK_TEST0`，不新增 profile、不修改 supported list。


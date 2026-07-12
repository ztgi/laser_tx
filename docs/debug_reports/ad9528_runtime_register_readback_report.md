# AD9528 真实运行配置只读寄存器读取报告

## 1. 修改摘要

本阶段在 `vitis_bringup/bringup/src/laser_ad9528.c/.h` 增加 `laser_ad9528_dump_runtime_state()`、UART 原始/解析打印和状态格式化接口；在 `laser_udp_server.c` 增加只读命令。后续四线 SPI 修复仅在初始化时写 serial-port live register `0x0000=0x18`，不写 clock-tree 配置：

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

读取失败会在 UART 报告 `reg=0x....` 与返回状态；UDP 返回 `failed_reg`。完整 dump 本身不调用写接口、RESET、IO_UPDATE、SYNC 或 SYSREF request；初始化阶段唯一写事务是 `0x0000=0x18`，用于启用四线 SDO。

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

`laser_ad9528_spi_init()` 初始化 PS SPI 控制器、选择 SS1，并写 serial-port live register `0x0000=0x18` 使能独立 SDO；dump 随后只发读 transaction。没有 PLL/OUT0/power-down 配置写，也没有 IO_UPDATE、SYNC 或 SYSREF_REQ 事务。

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

## 11. 四线 SPI 读回修复

### 11.1 上板失败现象

首次上板执行 `ad9528 status/dump` 时，SPI driver 返回 success，但 chip、PLL、OUT0 和 status 寄存器全部为零。已知只读识别寄存器不应全零：

| 地址 | 预期值 | 含义 |
| --- | ---: | --- |
| `0x0003` | `0x05` | product ID 低地址字节 |
| `0x0006` | `0x03` | revision |
| `0x000C` | `0x56` | vendor ID |

因此原来的 `spi_ok=1` 只证明 `XSpiPs_PolledTransfer()` 正常返回，不证明 AD9528 在 MISO/SDO 上产生有效响应。

### 11.2 板级接口核对

当前工程和 XDC 使用 PS SPI1 EMIO 的独立四线连接：

| 信号 | FPGA pin | 作用 |
| --- | --- | --- |
| SCLK | `AJ24` | AD9528 serial clock |
| MOSI / SDIO | `AH23` | FPGA 到 AD9528 数据 |
| MISO / SDO | `AH24` | AD9528 到 FPGA 数据 |
| SS1 | `AK23` | AD9528 chip select |

软件继续选择 `LASER_AD9528_SPI_SLAVE=1`。`XSPIPS_CLK_ACTIVE_LOW_OPTION` 和 `XSPIPS_CLK_PHASE_1_OPTION` 均未置位，因此使用 CPOL=0、CPHA=0。

AD9528 上电默认 serial data path 不保证独立 SDO 已使能。为匹配板级四线连接，SPI 初始化后只执行以下 serial-port 写入：

```text
register 0x0000 = 0x18
TX frame = 00 00 18
```

该帧置位 serial-port config 的 Bit4/Bit3，启用独立 SDO。寄存器 `0x0000` 是 live serial-port 配置，不执行 IO_UPDATE。本次未写 PLL、OUT0、power-down、SYSREF 或其它 clock-tree 寄存器，也未执行 RESET、SYNC。

### 11.3 最小识别门槛

初始化写入后依次读取：

```text
0x0003: TX = 80 03 00, expected RX[2] = 05
0x0006: TX = 80 06 00, expected RX[2] = 03
0x000C: TX = 80 0C 00, expected RX[2] = 56
```

每个 SPI write/read 临时打印完整 TX/RX 三字节和 driver status。只有三个值全部匹配，`laser_ad9528_dump_runtime_state()` 才继续读取 PLL/OUT0/status。若传输成功但识别值不匹配，UDP 返回：

```text
ERROR AD9528_STATUS spi_ok=1 error_code=ID_MISMATCH
reg0003=<raw> reg0006=<raw> reg000c=<raw>
```

这避免把全零寄存器继续解释成 PLL unlock、OUT0 divider=1 或 output enabled。

旧 `laser_ad9528_read_chip_id()` 也已从错误的 `0x0000..0x0002` 修正为读取 `0x0003..0x0005`，组合顺序与 ADI `0x00FF05` 定义一致。

### 11.4 Build 与硬件状态

Vitis 2022.2 clean build 已通过：

```text
text=157543 data=3432 bss=3201088 total=3362063
compiler errors=0
application compiler warnings=0
```

新 ELF：

```text
vitis_bringup/bringup/Debug/bringup.elf
```

本轮自动验证时，hw_server 可启动，但 `targets` 和 `jtag targets` 均为空。因此尚未下载 ELF，也尚未取得修复后的实际 UART/UDP 输出。以下结果保持待验证：

| 项目 | 当前结果 |
| --- | --- |
| `0x0000` 实际 MOSI/CS/SCLK 波形 | 未采集 |
| `0x0003/0x0006/0x000C` 实际 RX | 未取得 |
| UART 原始 TX/RX | 未取得 |
| UDP `ad9528 status/dump` | 未取得 |
| register-derived OUT0 frequency | UNKNOWN |
| measured OUT0 frequency | 未测量，本阶段不推进 |

如果修复后仍返回全零，下一步仅检查 SS1/CS 是否覆盖完整 24 个 SCLK、RESETB、MISO/SDO 引脚、SPI mode 0 和 `RX[2]`；在识别寄存器正确前仍不运行完整 dump 解析。

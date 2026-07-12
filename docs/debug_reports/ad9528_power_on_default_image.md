# AD9528 上电默认寄存器镜像

## 1. 目的与边界

本文记录当前板卡 AD9528 在尚未初始化 clock tree 时的 SPI 只读镜像。数据来自
2026-07-12 上板 `ad9528 dump` 原始读回，不是推荐配置，也不是 OUT0 实测频率。

```text
clock_tree_initialized=false
out0_runtime_valid=false
```

本轮未执行 RESET、IO_UPDATE、SYNC，未写 PLL1/PLL2、OUT0 或其他输出通道。

## 2. 器件识别

| 地址 | 读值 | 含义 |
|---|---:|---|
| `0x0003` | `0x05` | Product ID |
| `0x0004` | `0xFF` | 芯片识别镜像中间字节；不作为 product ID 判断依据 |
| `0x0005` | `0x00` | 芯片识别镜像高字节 |
| `0x0006` | `0x03` | Revision |
| `0x000C` | `0x56` | Vendor ID |

身份门限以 `0x0003/0x0006/0x000C = 0x05/0x03/0x56` 为准，已经通过。

## 3. 当前已取得的默认镜像

| 地址 | 读值 | 当前解释 |
|---|---:|---|
| `0x0108` | `0x00` | PLL1 control byte 0 |
| `0x0109` | `0x00` | PLL1 control byte 1 |
| `0x010A` | `0x00` | PLL1 control byte 2 |
| `0x0202` | `0x03` | PLL2 control |
| `0x0203` | `0x00` | PLL2 VCO control |
| `0x0204` | `0x00` | PLL2 M1 divider field |
| `0x0207` | `0x00` | PLL2 R1 divider field |
| `0x0208` | `0x00` | PLL2 N2 divider field |
| `0x0300` | `0x00` | OUT0 source/control byte |
| `0x0301` | `0x00` | OUT0 driver/phase byte |
| `0x0302` | `0x04` | OUT0 divider encoding；解码值为 5 |
| `0x0500` | `0x10` | Global power-down control |
| `0x0501` | `0x00` | Channel power-down low byte |
| `0x0502` | `0x00` | Channel power-down high byte |
| `0x0505` | `0x00` | Status monitor 0 |
| `0x0506` | `0x00` | Status monitor 1 |
| `0x0507` | `0x00` | Status pin enable |
| `0x0508` | `0x10` | Readback byte 0 |
| `0x0509` | `0x08` | Readback byte 1 |

当前 PLL1/PLL2 均未锁定；PLL2 divider/VCO 字段也不构成有效 clock-tree 配置。
因此不能把 `0x0302=0x04` 单独解释为一个正在输出的确定频率。

## 4. 补充镜像读取状态

补充地址已经通过新 ELF 在真实板卡读取：

| 地址 | 真实读值 |
|---|---:|
| `0x0200` | `0x00` |
| `0x0201` | `0x04` |
| `0x0205` | `0x00` |
| `0x0206` | `0x00` |
| `0x0209` | `0x00` |
| `0x032A` | `0x00` |
| `0x032D` | `0x00` |
| `0x0503` | `0xFF` |
| `0x0504` | `0xFF` |

UDP 原始结果：

```text
OK AD9528_DEFAULT_IMAGE reg0200=00 reg0201=04
reg0205=00 reg0206=00 reg0209=00 reg032a=00
reg032d=00 reg0503=ff reg0504=ff
clock_tree_initialized=0 out0_runtime_valid=0
```

`0x0503/0x0504=0xFF` 按真实 SPI readback 原样记录，不将其解释为有效配置字段。

## 5. 当前结论

当前证据证明 SPI 四线读回和器件身份有效，并补齐了本阶段要求的上电镜像；镜像同时
证明 AD9528 仍处于未初始化的上电状态。
它不证明 OUT0 有时钟，更不证明 OUT0 为 122.88 MHz。

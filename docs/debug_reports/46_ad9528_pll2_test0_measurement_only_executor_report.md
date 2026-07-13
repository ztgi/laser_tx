# 46. AD9528 PLL2 TEST0 measurement-only executor 实现报告

## 1. 本阶段目标与结论

本阶段停止扩大 PLL2 模拟环路参数理论审计，新增实验室 measurement-only 命令：

```text
ad9528 candidate set pll2_test0
```

目标候选保持上一阶段推荐值，没有替换：

```text
profile       = PLL2_TEST0
VCXO          = 122.88 MHz
R1/N2/M1      = 8/81/3
PLL2 VCO      = 3732.48 MHz
OUT0 divider  = 10
OUT0          = 124.416 MHz
ODIV2         = 62.208 MHz
1 ms count    = 62208
```

Vitis clean build 已通过并生成新 ELF，但尚未执行上板。因此当前只能声明 executor/build 完成，不能声明 PLL2 calibration、lock、OUT0 频率或 restore 已通过硬件验证。

## 2. 实验边界

该命令只用于 `OUT0_PLL2_MEASUREMENT_ONLY`，前提是：

- ADRV9009/JESD 子系统在测试期间不运行；
- 允许其他消费 PLL2 的 AD9528 输出临时变化或中断；
- 测试结束必须执行 restore；
- 不加入正式产品 profile；
- `board_verified` 始终保持 0。

UDP 状态明确输出：

```text
shared_pll2_output_impact=ACCEPTED_FOR_LAB_TEST_ONLY
configuration_class=REFERENCE_CONFIGURATION
board_verified=0
```

## 3. 模拟参数来源

本次采用本地 ADI-derived reference driver 中的一套完整初始化配置：

```text
D:/FPGA_Learn/project_gtx/vitis_clean/laser_tx_rate/src/ad9528.c
D:/FPGA_Learn/project_gtx/vitis_clean/laser_tx_rate/src/ad9528.h
```

同一结构提供：

| 项目 | 参数/寄存器 |
| --- | --- |
| charge pump | 805000 nA，0x0200=`0xE6` |
| RPOLE2 | 900 Ω，code 0 |
| RZERO | 1850 Ω，code 7 |
| CPOLE1 | 16 pF，code 2 |
| loop filter | 0x0205=`0x3A`、0x0206 bit0=`0` |
| calibration | 配置后 IO_UPDATE，再置 CALIBRATE 并第二次 IO_UPDATE |
| status | 等待 calibration 结束后检查 PLL2 lock/OK |

这些参数被标记为 `REFERENCE_CONFIGURATION`，不声明 `OPTIMIZED`，也不证明最终 jitter/phase-noise 性能。

## 4. 修改前问题

此前软件只支持 `VCXO_122P88` candidate。它能完成七项 masked write、一次 IO_UPDATE、readback、FPGA 测频和 restore，但没有：

- PLL2 common parameter executor；
- VCO calibration timeout；
- PLL2 lock/feedback/VCXO status gate；
- 针对 62208 的三窗口验收；
- PLL2 measurement-only 独立状态和错误码。

## 5. 修改后软件结构

`laser_ad9528_plan_clock_profile()` 新增 `PLL2_TEST0` 计划，共 16 个唯一 snapshot 地址：

```text
0108,0109
0200..0208
0500
0300..0302
0501
```

执行分为两段：

```text
无active candidate检查
→ identity/4-wire/baseline precheck
→ 16字节完整snapshot
→ 写reference/PLL2 common/power字段
→ IO_UPDATE #1
→ masked readback
→ 置0x0203 CALIBRATE
→ IO_UPDATE #2
→ 等待0x0509 bit0经历calibrating并清零
→ 等待0x0508 mask 0xA2 == 0xA2
→ 标记测量transition
→ 写OUT0 source=PLL2/divider=10/LVDS/channel enable
→ IO_UPDATE #3
→ masked readback
→ 等待3个不同sequence的完整1 ms窗口
→ 全部落入±1%后进入READY_MEASURED
```

本阶段没有写 0x032A，也没有执行 CHANNEL_SYNC。如果无 SYNC 时无法得到输出，按要求停止并报告，不会自动扩大为全局 SYNC。

## 6. 测量窗口与状态

| 项目 | 值 |
| --- | ---: |
| expected | 62208 |
| preferred ±0.5% | 61897..62519 |
| maximum lab acceptance ±1% | 61586..62830 |
| 必须连续取得的不同窗口 | 3 |
| measurement timeout | 2 s |

成功状态增加：

```text
state=READY_MEASURED
pll2_functionally_measured=1
measurement_windows=3
measured_odiv2_count=<最后窗口>
preferred_tolerance_pass=<0|1>
board_verified=0
```

±0.5% 用于报告 preferred 结果；硬失败界限为 ±1%，没有使用 ±5% 宽窗口。

## 7. 错误与自动回滚

新增错误：

```text
PLL2_CALIBRATION_TIMEOUT
PLL2_LOCK_TIMEOUT
OUT0_MEASUREMENT_TIMEOUT
OUT0_MEASUREMENT_OUT_OF_RANGE
```

SPI read/write、IO_UPDATE、readback、calibration、lock、alive/valid/timeout/count 任一步失败，都进入既有 rollback：恢复 16 个完整 snapshot 字节、执行 IO_UPDATE、逐字节 readback。成功自动 rollback 后清除 active/snapshot/TEST0 测量状态，并用 measurement transition 防止旧计数被当作新结果。

手动成功 restore 仍通过：

```text
ad9528 candidate restore
```

## 8. SPI 与硬件接口一致性

- 控制器：PS SPI1 / XSpiPs；
- device ID：来自 `XPAR_PS7_SPI_1_DEVICE_ID`；
- slave select：`LASER_AD9528_SPI_SLAVE=1`，沿用已验证板级 SS1；
- SPI mode：CPOL=0、CPHA=0；
- 输入时钟：166.666672 MHz，prescaler=64，SCLK 约 2.604 MHz；
- 四线模式：应用初始化仍只写 `0x0000=0x18`；
- identity：0x0003/0x0006/0x000C 期望 `05/03/56`；
- readback：PLL2/OUT0 配置、calibration 和 lock 均有明确检查；
- reset pin、SPI/BD/CS 映射本轮未改变。

## 9. 功能等价性和平台影响

原 `VCXO_122P88` candidate 路径保留。普通 GT `rate set`、11 档 supported list、RATE_ID、3000M BLOCKED、GT/CPLL/QPLL/MMCM、Bank111 refclk 均未修改。

本轮只增加新显式 candidate 名称，属于有意的软件功能扩展。XSA、platform、BSP、`xparameters.h`、AXI address、GPIO bitfield、linker script 均未改变。

## 10. 测试与构建

执行 56 项相关 Python tests，全部通过。覆盖 reference constants、候选数学、3 窗口、±0.5/±1% 边界、自动 rollback、禁止 CHANNEL_SYNC、3000M BLOCKED 和无 GT refclk 接入。

当前主 Vitis workspace 被 GUI/状态锁定，外部 XSCT 返回 `Invalid Workspace`。复用既有隔离 managed workspace 后，managed builder 重新生成的 `subdir.mk` 正式包含：

```text
laser_ad9528_measure.c
laser_ad9528_measure.o
laser_ad9528_measure.d
```

随后执行该 managed makefile 的 `clean` 和 `all`，无手工 `USER_OBJS`，编译和链接通过：

```text
text=182783
data=3512
bss=3201088
```

ELF：

```text
reports/ad9528_pll2_test0_measurement_only/bringup.elf
SHA256=9AFB4179D01184FBEC538349C313BA1BF08387D71531FF9138449AFE9B99B3E4
```

ELF 不提交 Git。本轮没有运行 Vivado、没有生成新 bit/LTX。

## 11. 上板步骤与成功标准

使用现有 measurement bitstream 和新 ELF：

```text
ad9528 candidate status
ad9528 candidate set pll2_test0
ad9528 candidate status
ad9528 measure status
ad9528 candidate restore
ad9528 measure status
READ_GT_STATUS
```

最低成功证据：calibration 完成、0x0508 lock/OK/VCXO 有效、`READY_MEASURED`、三个窗口接近 62208、`pll2_functionally_measured=1`，手动 restore 返回 `rollback_success=1`，且 restore 后不继续稳定保持 124.416 MHz。

## 12. 未验证边界

Hardware test was not run。当前尚未证明：

- PLL2 在板上完成 calibration 和 lock；
- OUT0 实测约 124.416 MHz；
- restore 后频率确实离开 124.416 MHz；
- reference configuration 是最优环路参数；
- jitter、phase noise、ADRV9009/JESD 兼容；
- Bank110 到 Bank111 GTX 接入；
- GTX fine-step profile 或动态切换可用。

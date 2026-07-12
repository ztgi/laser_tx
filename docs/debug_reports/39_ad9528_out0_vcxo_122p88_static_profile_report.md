# AD9528 OUT0 VCXO 122.88 MHz 静态测试 Profile 计划报告

## 1. 阶段目标

本阶段建立 `AD9528_OUT0_TEST_VCXO_122P88` 的只读 dry-run 计划。目标路径为：

```text
板载差分 VCXO 122.88 MHz
-> AD9528 OSC/VCXO differential receiver
-> PLL1 bypass / VCXO distribution source
-> OUT0 divider = 1
-> OUT0 LVDS
```

本阶段没有实现或执行 `ad9528 candidate set vcxo_122p88`，没有 IO_UPDATE、SYNC，
也没有改变任何硬件寄存器。

## 2. 官方参数依据

寄存器位域来自 [AD9528 Rev.G datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9528.pdf)
和 [ADI no-OS AD9528 driver](https://github.com/analogdevicesinc/no-OS/tree/main/drivers/frequency/ad9528)：

- PLL1 bypass 使用差分 OSC input，并设置 REFA/REFB/feedback bypass；
- output source `SOURCE_VCXO = 1`，位于 channel control `[7:5]`；
- channel divider 编码为 `divider - 1`，所以 divide-by-1 写 `0x00`；
- driver mode `0` 为 LVDS；
- channel power-down bit 为 1 时关闭，因此 OUT0 必须清除 channel 0 的 bit；
- PLL1/PLL2 均可在 VCXO direct 测试中 power-down；
- 单 channel source/divider 更新由 channel register + IO_UPDATE 生效；本计划不做全局
  SYNC，以免改变其他 output 的相位/对齐状态。

## 3. Dry-run transaction

UDP 只读命令：

```text
ad9528 profile plan vcxo_122p88
```

该命令只读取 old value 并计算 RMW 结果，不写硬件。
为容纳七项完整的 `reg/old/mask/value/new/readback_mask/readback_expected`，UDP 内部
ASCII response buffer 从 512 bytes 调整为 1024 bytes；现有命令格式、端口和硬件
控制行为均未改变。

基于当前已读默认镜像，计划如下；实际 UDP 返回会再次实时读取 old value。每项严格按

```text
new = (old & ~mask) | (value & mask)
```

计算：

| 地址 | old | mask | value | new | readback mask/expected | 目的 |
|---|---:|---:|---:|---:|---:|---|
| `0x0108` | `0x00` | `0x05` | `0x01` | `0x01` | `0x05/0x01` | 使能差分 OSC input，清除 VCXO receiver power-down |
| `0x0109` | `0x00` | `0x38` | `0x38` | `0x38` | `0x38/0x38` | REFA/REFB/feedback bypass |
| `0x0300` | `0x00` | `0xE0` | `0x20` | `0x20` | `0xE0/0x20` | OUT0 source = VCXO |
| `0x0301` | `0x00` | `0xC0` | `0x00` | `0x00` | `0xC0/0x00` | OUT0 driver = LVDS |
| `0x0302` | `0x04` | `0xFF` | `0x00` | `0x00` | `0xFF/0x00` | OUT0 divide-by-1 |
| `0x0501` | `0x00` | `0x01` | `0x00` | `0x00` | `0x01/0x00` | 保证 channel 0 未 power-down |
| `0x0500` | `0x10` | `0x0C` | `0x0C` | `0x1C` | `0x0C/0x0C` | PLL1/PLL2 power-down，保留其他 global bits |

计划属性：

```text
configured_out0_hz=122880000
requires_io_update=1
requires_sync=0
affects_other_outputs=0
```

`configured_out0_hz` 只是配置目标，不是 measured frequency。

### 3.1 字段来源边界

来自 AD9528 datasheet/ADI driver 的字段是：PLL1 bypass bit、OSC differential receiver
bit、VCXO source encoding、OUT divider encoding、LVDS driver encoding、channel/global
power-down bit、IO_UPDATE 需求及 readback mask。

依赖本板假设的内容只有：板载 VCXO 标称频率为 122.88 MHz，以及该差分 VCXO 已连接
到 AD9528 OSC/VCXO input。因尚未测量 OUT0，`122880000` 只能称为 configured target。

## 4. 其它输出影响

计划不写 OUT1/OUT3/OUT12/OUT13，也不重写全 channel power-down mask。`0x0501`
只清除 channel 0 bit，`0x0500` 只修改 PLL1/PLL2 power-down bits。由于不执行全局
SYNC，其他输出不会因本 dry-run 计划产生相位重对齐。

## 5. Apply 与 rollback 状态

```text
apply_implemented=false
apply_executed=false
io_update_executed=false
sync_executed=false
rollback_executed=false
active_profile=NONE
board_verified=false
```

人工确认 transaction 后，下一步才允许实现 apply。apply 必须保存七个寄存器的原始
镜像、逐项 readback、执行一次 IO_UPDATE，并在失败时恢复原镜像后再次 IO_UPDATE。

## 6. 频率验证状态

示波器和 `AA8/AA7 -> IBUFDS_GTE2.ODIV2 -> BUFG counter` 均未执行。因此不能声明
OUT0 已产生 122.88 MHz。

## 7. 构建与当前阻塞

Vitis 2022.2 build 已通过，新 ELF 包含 `AD9528_DEFAULT_IMAGE` 和
`AD9528_PROFILE_PLAN` 命令字符串。最终 ELF 已下载到 A9 #0，并完成真实 UDP dry-run。

默认镜像返回：

```text
OK AD9528_DEFAULT_IMAGE reg0200=00 reg0201=04 reg0205=00 reg0206=00
reg0209=00 reg032a=00 reg032d=00 reg0503=ff reg0504=ff
clock_tree_initialized=0 out0_runtime_valid=0
```

最终 plan 返回：

```text
OK AD9528_PROFILE_PLAN profile=VCXO_122P88 out0_hz=122880000
writes=7 io_update=1 sync=0 affects_other_outputs=0
tx=reg=0108/old=00/mask=05/value=01/new=01/readback_mask=05/readback_expected=01,
reg=0109/old=00/mask=38/value=38/new=38/readback_mask=38/readback_expected=38,
reg=0300/old=00/mask=e0/value=20/new=20/readback_mask=e0/readback_expected=20,
reg=0301/old=00/mask=c0/value=00/new=00/readback_mask=c0/readback_expected=00,
reg=0302/old=04/mask=ff/value=00/new=00/readback_mask=ff/readback_expected=00,
reg=0501/old=00/mask=01/value=00/new=00/readback_mask=01/readback_expected=00,
reg=0500/old=10/mask=0c/value=0c/new=1c/readback_mask=0c/readback_expected=0c
```

plan 后 `rate status` 仍为 500M，`gt_drp_written/mmcm_drp_written` 和对应 done 均为 0；
普通 GT rate executor 未被触发。源代码检查确认 planner 仅通过
`ad9528_add_plan_write()` 读取 old value 并在内存中计算结果，没有调用
`laser_ad9528_write()`、IO_UPDATE、SYNC 或 RESET。

## 8. 边界

本阶段未修改 RTL、BD、XDC、GT profile、RATE_ID、supported list、GT refclk、
OUT1/OUT3/OUT12/OUT13 或 ADRV9009/JESD 配置。阶段完成后仍停在 OUT0 独立测试，
不接入 Bank111 GTNORTHREFCLK。

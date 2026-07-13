# 43. AD9528 PLL2 TEST0 完整寄存器镜像与共享输出影响核查

## 1. 本阶段目标与结论

本阶段复核 `PLL2_TEST0_OUT0_124P8_CPLL_998P4` 的数学模型、ADI 寄存器语义、PLL2 校准顺序和共享输出风险，并增加只读 full dump。没有配置 PLL2，也没有增加可执行 candidate。

最终 gate：

```text
NO_PROVEN_PLL2_REGISTER_IMAGE
```

## 2. 为什么数学候选不能直接下板

频率公式成立不等于全部 AD9528 字段可编码。该候选的 PFD=15.36 MHz、VCO=3993.6 MHz、OUT0=124.8 MHz 均满足数学关系，但 ADI no-OS 驱动对 calibration divider 施加 16..255（排除 18/19/23/27）的合法性检查。候选 `M1×N2=260` 超限，不能生成 0x0201 A/B。

## 3. 124.8 MHz 候选重新推导

| 项目 | 结果 |
|---|---:|
| VCXO | 122.88 MHz |
| doubler | 1（disabled） |
| R1 | 8 |
| PFD | 15.36 MHz |
| N2 / M1 | 65 / 4 |
| VCO | 3993.6 MHz |
| OUT0 parent | 998.4 MHz |
| OUT0 divider | 8 |
| OUT0 | 124.8 MHz |
| ODIV2 1 ms count | 62400 |
| calibration divider | 260（非法） |

数学模型已复核；寄存器镜像不成立。

## 4. 字段与术语核对

- `N2`：0x0208 独立 divider，ADI 宏编码为 `N2-1`；
- `M1`：0x0204 VCO divider；
- `feedback A/B`：0x0201，用于 calibration divider；
- `calibration divider`：ADI 驱动按 `M1×N2` 计算，之后 `A=div%4`、`B=div/4`；
- 0x0201 与 0x0208 不是同一字段，不得混用。

来源为 AD9528 Rev. G 字段语义及本地 ADI no-OS `ad9528.c/.h`。本次没有从论坛或其他型号复制值。

## 5. 0x0200～0x0208 寄存器核查

| 地址 | 含义 | 当前 | 目标/掩码 | 结论 |
|---|---|---|---|---|
| 0200 | charge pump | `BOARD_DUMP_REQUIRED` | 未确认 | 805 µA 只是已有 ADI/厂商参考配置，不能机械复制为 TEST0 |
| 0201 | feedback A/B | `BOARD_DUMP_REQUIRED` | 无合法值 | divider=260，B=65 超出 B[5:0] |
| 0202 | control | `BOARD_DUMP_REQUIRED` | value=03/mask=A3 | doubler off、CP normal、lock detector enabled的字段语义已确认 |
| 0203 | VCO/calibration | `BOARD_DUMP_REQUIRED` | base=10、calibrate=11/mask=17 | 顺序来自 ADI 驱动；候选本身仍被 gate 阻止 |
| 0204 | M1 | `BOARD_DUMP_REQUIRED` | value=04/mask=0F | M1=4、M1 power-up |
| 0205 | loop filter byte0 | `BOARD_DUMP_REQUIRED` | 未确认 | CPOLE1/RZERO/RPOLE2 不能由频率公式推测 |
| 0206 | loop filter byte1 | `BOARD_DUMP_REQUIRED` | 未确认 | bypass/upper byte需要已证明板级 profile |
| 0207 | R1 | `BOARD_DUMP_REQUIRED` | value=08/mask=1F | R1=8 |
| 0208 | N2 | `BOARD_DUMP_REQUIRED` | value=40/mask=FF | N2-1=64；不代表 A/B 可编码 |

完整逐字段来源、buffered/live、restore source 和 confidence 见 `reports/ad9528_pll2_test0_register_image/pll2_test0_register_plan.csv/json`。

## 6. OUT0 与全局 power

计划只允许 masked field：0300 source mask E0、0302 divider mask FF、0500 PLL2 power-down bit mask 08、0501 OUT0 power-down bit mask 01。0301 的 LVDS/phase 必须从现场 readback 保留；没有现场完整镜像时不得整字节覆盖。

## 7. Charge-pump 来源

ADI 公式为 `code=current_nA/3500`。本地参考工程使用 805000 nA，但该值与 loop filter 构成一组板级环路设计输入。本报告仅记录它为 `ADI_DRIVER_DERIVED/BOARD_VENDOR_REFERENCE`，不把它升级成 TEST0 target。

## 8. Feedback A/B 来源

ADI 驱动先检查 `M1×N2`，合法后才计算 A/B。260 超过上限 255，因此 feedback A/B 为 `INVALID_NOT_ENCODABLE`，不是 UNKNOWN，也不能靠截断修复。

## 9. Loop-filter 来源

参考工程存在 RPOLE2=900 Ω、RZERO=1850 Ω、CPOLE1=16 pF，但缺少证明该组值适用于本板 TEST0 PFD/VCO/charge pump 的正式 profile。0205/0206 保持 UNKNOWN。

## 10. Calibration 顺序

ADI no-OS 的可追溯顺序为：写 PLL2/common/output/power → IO_UPDATE → 写 0203 CALIBRATE → 第二次 IO_UPDATE → 轮询 `IS_CALIBRATING=0` → 检查 `PLL2_LOCKED/PLL2_OK`。本报告只记录顺序，不公开写入口。

## 11. Lock/status 判定

0x0508/0509 readback 中：bit8=`IS_CALIBRATING`、bit7=`PLL2_OK`、bit1=`PLL2_LOCKED`。`PLL2_LOCKED` 与 `PLL2_OK` 不是同一状态；未来 executor 必须分别检查。当前 timeout/poll interval 尚无本板实测依据，仍为 UNKNOWN。

## 12. IO_UPDATE 次数

官方初始化至少包含 common 配置后的 IO_UPDATE、CALIBRATE 置位后的第二次 IO_UPDATE，后续 SYSREF/status 与 SYNC 还可能产生额外更新。因此 TEST0 不能沿用 VCXO direct 的“固定一次 IO_UPDATE”假设。

## 13. SYNC 决策

当前结论为 `requires_sync=null`。ADI setup 最终会调用 channel SYNC，但未获得 032B/032C ignore mask 和全部 active channel 的本板镜像，无法证明 SYNC 只影响 OUT0。现阶段既不能宣称必须执行，也不能宣称安全省略；不得在 TEST0 中执行 SYNC。

## 14. 全 14 路共享输出影响

| 输出 | 已知板级去向 | 当前 source/enable | 风险 |
|---|---|---|---|
| OUT0 | FPGA_REF0_CLK / Bank110 | UNKNOWN | UNKNOWN |
| OUT1 | FPGA_REF1_CLK / Bank109 | UNKNOWN | UNKNOWN |
| OUT3 | FPGA_SYSREF | UNKNOWN | UNKNOWN |
| OUT12 | ADRV9009 SYSREF | UNKNOWN | UNKNOWN |
| OUT13 | ADRV9009 REF_CLK | UNKNOWN | UNKNOWN |
| 其余 OUT2/4..11 | 未完整确认 | UNKNOWN | UNKNOWN |

完整 14 行矩阵见 `pll2_test0_shared_output_matrix.csv`。未获得 full dump 前，不能确认其他活动输出是否消费 PLL2，故 `SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED` 保持。

## 15. Snapshot 范围

最低范围：0200..0208、0300..0302、0500、0501；若未来修改 SYNC，必须加入 032A..032C。任何后续新增写地址都必须同时进入 snapshot 和 restore 集合。

## 16. Restore 流程

失败后应先停止使用新测量值，恢复所有 snapshot 完整旧字节，执行必要 IO_UPDATE，统一 readback，确认 PLL2/common/各输出回到 apply 前状态，再清除 measurement cache。失败状态必须保留 `last_error/failed_reg/expected/actual/rollback_attempted/rollback_success`。本轮没有实现该 executor。

## 17. Host 测试

执行：

```text
python -m py_compile scripts/enumerate_ad9528_gt_refclk_candidates.py scripts/audit_ad9528_pll2_test0_register_image.py
python -m unittest scripts.tests.test_ad9528_fine_step_test0 scripts.tests.test_ad9528_pll2_test0_register_audit
```

30 项通过。覆盖数学公式、编码范围、calibration divider gate、地址唯一性、UNKNOWN gate、shared output gate、SYNC 未确认、禁止 initializer 和确定性输出。

## 18. Vitis/UDP 修改

现有 `ad9528 dump` 覆盖不足，新增 `ad9528 dump full`。它只读取 0000..000F、0100..010A、0200..0208、0300..032E、0400..0403、0500..0508，并输出 `AD9528_REG addr=... value=...`。没有新增 PLL2 写 helper 或 candidate set。

## 19. ELF 构建

Vitis 2022.2 ARM toolchain clean compile 后，managed makefile 因既有 `laser_ad9528_measure.c` 未列入对象而首次链接失败；以同一 toolchain 将该既有文件作为额外对象后链接通过。最终：text=175871、data=3448、bss=3201088。XSA/Platform/BSP 未变化。

## 20. 最终 gate

失败项：calibration divider/A-B 不可编码、charge pump 未确认、loop filter 未确认、A/B/C full dump 未采集、SYNC 决策未关闭、共享输出影响未接受。最终只能是：

```text
NO_PROVEN_PLL2_REGISTER_IMAGE
```

## 21. 需要用户采集的只读 dump

分别在以下状态执行 `ad9528 dump full` 并保存 UART 原文：

1. 上电且未执行 candidate；
2. `ad9528 candidate set vcxo_122p88` 后；
3. `ad9528 candidate restore` 后。

命令本身不写 AD9528，但 SPI 初始化仍会按现有设计写 0000=18 以启用四线 SDO；这不是 PLL2/clock-tree 写入。

## 22. 下一阶段条件与边界

下一阶段应重新选择一组 `M1×N2<=255` 且不属于排除值的 PLL2 参数，再结合三份 full dump、正式 charge-pump/loop-filter 依据和共享输出许可重做 gate。本报告没有修改 RTL/BD/XDC/GT/supported rates，没有生成 bit/LTX，没有执行硬件 PLL2 测试。

# 45. AD9528 PLL2 TEST0 双候选完整寄存器计划对比

## 1. 目标、输入与停止点

本阶段只把用户保存的 `ad9528 dump full` UART 原始输出解析为可审计的基线镜像，并比较两套 PLL2 TEST0 候选寄存器计划：

- A：`PLL2_TEST0_OUT0_125P44`；
- B：`PLL2_TEST0_OUT0_124P416`。

脚本不访问 AD9528，不调用任何 Vitis 驱动，不执行 SPI write、IO_UPDATE、CALIBRATION 或 SYNC，也不生成 C initializer。基线语义为：

```text
APPLICATION_INITIALIZED_BASELINE
```

它不是芯片绝对无软件干预的原始上电状态，因为 application 已写 `0x0000=0x18` 以启用四线 SDO。最终安全 gate 为：

```text
NO_SAFE_PLL2_TEST0_CANDIDATE
```

## 2. 输入镜像完整性

解析范围为 `0000..000F`、`0100..010A`、`0200..0208`、`0300..032E`、`0400..0403`、`0500..0509`，共 97 个唯一地址。解析器会拒绝重复地址和缺失地址。规范化原文与 JSON 保存为：

```text
reports/ad9528_pll2_test0_register_plan/baseline_full_dump.txt
reports/ad9528_pll2_test0_register_plan/baseline_full_dump.json
```

## 3. 两候选数学与编码对比

| 项目 | A：125.44 MHz | B：124.416 MHz |
| --- | ---: | ---: |
| VCXO | 122.88 MHz | 122.88 MHz |
| R1 / PFD | 6 / 20.48 MHz | 8 / 15.36 MHz |
| N2 / M1 | 49 / 4 | 81 / 3 |
| VCO | 4014.08 MHz | 3732.48 MHz |
| VCO 下边界余量 | 564.08 MHz | 282.48 MHz |
| VCO 上边界余量 | 10.92 MHz | 292.52 MHz |
| M1×N2 calibration divider | 196 | 243 |
| 0x0201 feedback A/B | `0x31` | `0xFC` |
| OUT0 divider / OUT0 | 8 / 125.44 MHz | 10 / 124.416 MHz |
| ODIV2 / 1 ms count | 62.72 MHz / 62720 | 62.208 MHz / 62208 |
| 8×OUT0 理论 line rate | 1003.52 Mbps | 995.328 Mbps |
| 相对 1 Gbps 偏差 | +3520 ppm | -4672 ppm |

两者 calibration divider 均落在 ADI driver 允许的 16..255 范围且不属于 18/19/23/27 排除值。A 更接近 125 MHz，但 VCO 只比 4025 MHz 上限低 10.92 MHz；B 的上下边界余量更均衡，因此只推荐 B 作为下一轮“参数闭环优先对象”，不代表允许实现。

## 4. 寄存器计划来源与置信度

完整逐项字段见 `candidate_125p44_register_plan.csv/json` 与 `candidate_124p416_register_plan.csv/json`。每行包含 address、baseline、target、write/readback mask、expected readback、字段来源、buffered/live、IO_UPDATE、snapshot/restore 和 confidence。

| 地址 | A | B | 来源与结论 |
| --- | --- | --- | --- |
| 0108 | value 01 / mask 05 | 同 A | datasheet 字段 + 板载 122.88 MHz differential VCXO 假设 |
| 0109 | value 38 / mask 38 | 同 A | datasheet 与已验证 VCXO direct candidate 路径 |
| 0200 | E6 | E6 | 本地 ADI driver 805 µA 参考值，尚未本板确认 |
| 0201 | 31 | FC | `divider=4×B+A`，由 M1×N2 编码 |
| 0202 | 03 / mask A3 | 同 A | doubler off、lock detector on、CP normal |
| 0203 | base 10 / mask 17 | 同 A | R1 path enable；CALIBRATE 是后续动作 |
| 0204 | 04 | 03 | M1 direct encoding |
| 0205/0206 | 3A / 00 | 同 A | 本地 ADI driver 环路滤波器参考值，尚无本板 TEST0 证明 |
| 0207 / 0208 | 06 / 30 | 08 / 50 | R1 direct、N2-1 encoding |
| 0300 / 0301 | 00 / 00 | 同 A | OUT0 source=PLL2、LVDS，phase 位保留 |
| 0302 | 07 | 09 | output divider-1 |
| 0500 / 0501 | 清 PLL2/OUT0 power-down 位 | 同 A | masked power control |
| 0508 | readback mask A2 / expected A2 | 同 A | VCXO OK、PLL2 feedback OK、PLL2 locked |
| 0509 | readback mask 01 / expected 00 | 同 A | calibration complete |

`0x0200=0xE6` 和 `0x0205=0x3A/0x0206 bit0=0` 虽可追溯到本地 ADI driver/reference 配置，但未证明适用于本板两套 PFD/VCO 条件，所以 confidence 保持 `REFERENCE_ONLY_NOT_BOARD_CONFIRMED`。

字段和顺序依据为 [AD9528 Rev. G datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/AD9528.pdf) 与本地 ADI driver `D:/FPGA_Learn/project_gtx/vitis_clean/laser_tx_rate/src/ad9528.c/.h`。

## 5. Calibration / IO_UPDATE / status 顺序

两候选的文档化顺序均为：

```text
snapshot所有拟写完整旧字节
→ masked write reference/PLL2/OUT0/power字段
→ IO_UPDATE #1
→ 置位0x0203 CALIBRATE
→ IO_UPDATE #2
→ 轮询0x0509 bit0清零
→ 检查0x0508 mask A2 == A2
→ 必要的channel SYNC
→ masked post-readback
→ 完整窗口ODIV2测量
```

该顺序只是审计输出，未实现执行器。calibration bit、PLL2 lock/feedback/VCXO status 分开检查，不以单一 lock 位替代完整验收。

## 6. 共享输出真实镜像

完整矩阵见 `shared_output_matrix.csv`。基线解码结果为：

- OUT0/2/4/6/8/10：source=PLL2、divider=5；
- OUT1/3/5/7/9/11：source=SYSREF_RETIMED_PLL2、divider=1；
- OUT12/13：source=PLL1/VCXO、divider=1；
- 0501/0502 均为 00，14 路 channel 全部未 power-down；
- 032B/032C 均为 00，没有 channel 被 SYNC ignore。

因此 PLL2 common 改动会直接影响 OUT0..OUT11；即使 OUT12/13 不直接消费 PLL2，global SYNC 仍覆盖全部 enabled channel。已知板级去向中 OUT1 为 FPGA_REF1、OUT3 为 FPGA_SYSREF、OUT12/13 连接 ADRV9009。共享时钟树影响尚未获得许可，不能仅为测试 OUT0 执行全局 SYNC。

## 7. Snapshot / restore 边界

所有 `write_mask != 0` 的可写寄存器都标记为同时进入 snapshot 和 restore；restore 使用完整旧字节，不按候选值反向推导。只读 0508/0509 和静态未写的 032A..032C 不伪装为 snapshot 写项。

若未来获准执行 SYNC，必须将实际 032A action 及失败恢复语义加入执行器；当前不生成该执行器。

## 8. Candidate gate 与推荐

两个候选共同失败：

```text
CHARGE_PUMP_BOARD_PROFILE_NOT_CONFIRMED
LOOP_FILTER_BOARD_PROFILE_NOT_CONFIRMED
SHARED_PLL2_OUTPUT_IMPACT_NOT_ACCEPTED
GLOBAL_SYNC_IMPACT_NOT_ACCEPTED
```

所以 A/B 均为 `safe_to_implement=false`，且 `executable_initializer_generated=false`。推荐 B 只表示下一轮优先闭环：其 VCO 离上下限均有约 282 MHz 以上余量；A 虽频率误差更小，但距离 VCO 上限只有 10.92 MHz。

## 9. 测试

执行：

```text
python -m py_compile scripts/compare_ad9528_pll2_test0_register_plans.py scripts/tests/test_ad9528_pll2_test0_dual_candidate.py
python -m unittest scripts.tests.test_ad9528_pll2_test0_dual_candidate
python scripts/compare_ad9528_pll2_test0_register_plans.py --dump-input <UART_CAPTURE> --output-dir reports/ad9528_pll2_test0_register_plan
```

15 项 host tests 通过，覆盖完整/缺失/重复 dump、两候选数学、calibration divider、VCO margin、snapshot/restore、shared output、SYNC gate、status readback mask、禁止 initializer、确定性生成及固定 3000M CPLL BLOCKED 状态。

## 10. 功能、构建与硬件边界

本阶段没有修改 Vitis application、AD9528 driver、RTL、BD、XDC、GT profile、RATE_ID、supported list 或普通 `rate set`。没有运行 Vitis/Vivado build，没有生成 bit/LTX，没有执行 AD9528 PLL2 上板写入或硬件测试。

当前只完成离线计划生成和代码结构检查。下一步必须先取得本板适用的 charge-pump/loop-filter 正式依据，并明确共享 OUT0..OUT13 与 global SYNC 影响许可；在此之前保持 `NO_SAFE_PLL2_TEST0_CANDIDATE`。

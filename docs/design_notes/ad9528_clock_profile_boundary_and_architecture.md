# AD9528 时钟规划边界与 Profile 架构确认

## 1. 目的和结论

本文只核对板级时钟连接、当前仓库的软件状态，并定义未来 AD9528 专用时钟
profile 的数据边界。它不是 GTX 候选速率规划，也不修改 AD9528 寄存器、GTX
profile、CPLL/QPLL/MMCM、UDP 或现有 supported rate。

结论如下：

1. 当前 `laser_tx` 的 SFP+ 发送通道位于 **Bank 111**，使用板载独立的
   125 MHz `MGTREFCLK0`；当前顶层/XDC 只有这一路输入。
2. AD9528 并不接到当前 Bank 111 光口通道的 MGTREFCLK。它的 OUT0/OUT1 分别
   接到 **Bank 110** 和 **Bank 109** 的 MGTREFCLK0；OUT3/OUT12/OUT13 属于
   FPGA SYSREF、ADRV9009 SYSREF 和 ADRV9009 device reference 时钟链路。
3. 因而，不能把 AD9528 输出当成当前 SFP+ GTX Bank 111 的可变 MGTREFCLK，
   也不能将 GTX 76 个合法 tuple 当成 AD9528 的输出 profile 表。
4. 当前仓库没有完整 AD9528 初始化寄存器表或任何已执行的 PLL2/output-divider/
   IO_UPDATE/SYNC 配置；`laser_ad9528_apply_rate_profile()` 明确返回
   `XST_NO_FEATURE`。当前 OUT0/OUT1/OUT3/OUT12/OUT13 的**实际频率未知**，
   不能由 122.88 MHz VCXO、30.72 MHz TCXO 或 GTX profile 反推。

本结论来自原理图、用户手册和当前仓库的结构检查；不是 AD9528、ADRV9009 或
JESD204B 的运行时测试结论。

## 2. 板级时钟拓扑核对

### 2.1 独立 MGT 参考时钟与当前 SFP+ 路径

原理图 sheet 8、17 和用户手册时钟章节显示：

- Bank 111 `MGTREFCLK0P/N`：`U8/U7`，网络 `LVDS_CLK111_P/N`，板载独立
  125 MHz 差分时钟；这正是当前工程 `gt_refclk125_p/n` 的 XDC 约束。
- Bank 111 `MGTREFCLK1P/N`：`W8/W7`，网络 `LVDS_CLK111_P1/N1`，板载独立
  156.25 MHz 差分时钟；当前主工程尚未将其作为顶层端口、`IBUFDS_GTE2` 输入
  或运行时可选参考时钟。
- 当前 SFP+ TX 使用 `MGTXTXP0/N0_111 = AB2/AB1`，因此属于 Bank 111，而不是
  AD9528 OUT0/OUT1 接入的 Bank 109/110。

### 2.2 AD9528 输出实际去向

| AD9528 输出 | 原理图网络 | FPGA/器件终点 | 板级作用 | 当前 `laser_tx` 使用情况 |
|---|---|---|---|---|
| OUT0/OUT0_N | `FPGA_REF0_CLK+/-` | Bank 110 `MGTREFCLK0P/N = AA8/AA7` | Bank 110 GTX 参考时钟 | 未接入当前 Bank 111 SFP+ wrapper |
| OUT1/OUT1_N | `FPGA_REF1_CLK+/-` | Bank 109 `MGTREFCLK0P/N = AD10/AD9` | Bank 109 GTX/JESD 侧参考时钟 | 未接入当前 SFP+ wrapper |
| OUT3/OUT3_N | `FPGA_SYSREF+/-` | Bank 11 `IO_L12P/N_T1_MRCC_11 = AE22/AF22` | FPGA JESD/SYSREF 输入 | 当前主工程未使用 |
| OUT12/OUT12_N | `SYSREF_IN+/-` | ADRV9009 `SYSREF_IN+/- = K3/K4` | ADRV9009 JESD SYSREF | 当前主工程未使用 |
| OUT13/OUT13_N | `REF_CLK_IN+/-` | ADRV9009 `REF_CLK_IN+/- = E7/E8` | ADRV9009 device reference clock | 当前主工程未使用 |

补充：`FPGA_SYSREF_OUT+/- = AG21/AH21` 是 FPGA 输出到 AD9528
`SYSREF_IN/IN_N`（AD9528 pin 70/71）的反向 SYSREF 路径，不能与 AD9528 OUT3
到 FPGA 的 `FPGA_SYSREF+/-` 混淆。

### 2.3 AD9528 输入与控制网络

用户手册 3.2.3 和原理图 sheet 20 显示：

- AD9528 的本振输入来自板载 122.88 MHz VCXO；
- 参考输入可使用板载 30.72 MHz TCXO 或外部参考输入；
- PS SPI1 EMIO 使用 SS1 选择 AD9528；当前 XDC 为 SCLK AJ24、SDIO/MOSI AH23、
  SDO/MISO AH24、CS AJ23，均为 LVCMOS25；
- `AD9528_RESETB` 为 AK22，`AD9528_SYSREF_REQ` 为 AH22。它们是低速控制，不是
  MGT reference-clock 引脚。

这些信号说明 AD9528 可服务于 ADRV9009/JESD 时钟树，但不构成当前 Bank 111
光口 MGTREFCLK 动态切换的硬件路径。

## 3. ADRV9009 与 JESD204B 当前可确认范围

板卡手册确认：

- ADRV9009 的 JESD204B 数据通道接 Bank 109 GTX；手册描述该通道速率最高
  可达 12.288 Gbps；
- 手册示例的 TX/RX 数据率为 122.880 MSPS；这是板卡示例条件，不是当前
  `laser_tx` 的运行时配置读回；
- OUT13 是 ADRV9009 `REF_CLK_IN`，OUT12 是其 `SYSREF_IN`。

当前仓库不包含 ADRV9009 初始化 profile、JESD204B core 配置或运行时读回，故
下列当前值均为 **NOT CONFIGURED / NOT PROVEN**：

| 项目 | 当前仓库结论 |
|---|---|
| ADRV9009 device clock | 无寄存器表或读回，未知 |
| ADRV9009 sample rate | 无当前配置；手册示例为 122.880 MSPS，不能当作现状 |
| JESD204B L/M/F/S/K | 当前仓库无来源，未知 |
| JESD lane rate | 当前仓库无来源；12.288 Gbps 仅为手册能力/示例边界 |
| SYSREF 周期、连续/oneshot 模式 | 无当前配置，未知 |

## 4. 当前软件与寄存器表核对

`vitis_bringup/bringup/src/laser_ad9528.c` 当前只实现：

- SPI1/SS1 初始化；
- 单寄存器三字节读写传输；
- `0x0000..0x0002` chip-ID 读回；
- 基础通信检查。

不存在 AD9528 PLL1/PLL2、VCO、OUT0/OUT1/OUT3/OUT12/OUT13 divider、
输出格式、IO_UPDATE、SYNC 或锁定状态的初始化表。`laser_ad9528_apply_rate_profile()`
无条件返回 `XST_NO_FEATURE`，所以当前没有“实际已应用 AD9528 clock profile”。

现有 GTX 软件表中的 `GT_RATE_REF_AD9528_OUT0` 只是预留 enum；所有现用正式
GT profile 均为 125 MHz、`ad9528_dynamic_required=0`，不能把该 enum 解释为
AD9528 OUT0 已参与切速率。

## 5. 仓库内 AD9528-as-MGTREFCLK 表述审计

| 位置 | 当前表述/状态 | 与原理图的一致性 |
|---|---|---|
| `attachment/设计说明.txt` 28-53 行 | 将 AD9528 规划为“AD9528 -> FPGA MGT 可编程 GTX 参考时钟” | 对当前 Bank 111 SFP+ 路径冲突；只在特指 Bank 109/110 时才有物理连线依据 |
| `docs/gt_dynamic_rate_phase1_plan.md` | 写为“精确通道仍需确认”、未来可能性 | 不是实现声明；应以本文板级结论替代模糊假设 |
| `vitis_bringup/.../gt_rate_plan.h` | 保留 `GT_RATE_REF_AD9528_OUT0` enum | 仅预留，不等于连接或功能已实现 |
| `docs/ad9528_bringup.md` 与现有 Vitis 代码 | 明确只有 SPI/readback，clock tree 未确认 | 与当前事实一致 |

因此需要修正的不是“AD9528 永远不能驱动任何 GTX MGTREFCLK”，而是：**它不能
驱动当前 Bank 111 SFP+ 通道的 MGTREFCLK；当前仓库也没有实现其对 Bank 109/110
GTX 或 ADRV/JESD 时钟树的动态配置。**

## 6. 独立 AD9528ClockProfile 数据模型

AD9528 profile 必须与 `GtRateProfile` 分离。其输入是 ADRV9009/JESD 时钟需求，
不是 GTX line-rate tuple；其输出是完整的、可校验的 AD9528 时钟树配置。

```text
Ad9528ClockProfile
  profile_id / revision / board_verified
  source
    vcxo_hz, ref_source, ref_input_hz
    pll1 parameters (when used)
    pll2_r_div, pll2_n_div, pll2_vco_hz, loop-filter/charge-pump fields
  adrv9009_requirement
    sample_rate_hz, device_clock_hz
    jesd: L, M, F, S, K, N, N_prime, subclass, lane_rate_bps
  fpga_requirement
    fpga_ref0_hz, fpga_ref1_hz, fpga_sysref_hz
  sysref
    adrv_sysref_hz, mode, pulse_count, alignment/phase requirement
  outputs[OUT0, OUT1, OUT3, OUT12, OUT13]
    enabled, destination, divider, frequency_hz, electrical format/drive
  transaction
    register_image, per-register readback mask/value
    io_update_required, sync_required, lock/status expectation, timeout
```

该模型必须保留 `board_verified=false` 的候选状态。只有在对应 ADRV/JESD profile、
完整 register image、读回、IO_UPDATE/SYNC、STATUS0/STATUS1/锁定检查及硬件
验证全部完成后，才可置为 true。

## 7. 安全执行接口的建议边界

未来接口应分为 planner、validator 和 executor 三层：

1. **Planner**：由 ADRV sample rate、JESD L/M/F/S/K、device clock 和 SYSREF
   要求选择已有 `Ad9528ClockProfile`；不计算或下载任意未知 divider。
2. **Validator**：确认 profile revision、目标输出频率、输出目的地、寄存器
   readback mask/value、板级状态和 `board_verified`。若所需字段缺失，拒绝执行。
3. **Executor**：在 ADRV/JESD 停止或受控复位的前提下，按
   `program registers -> readback -> IO_UPDATE -> SYNC/SYSREF -> STATUS/lock`
   执行；失败不得更新 active profile。

`GtRateProfile` 可保留一个“是否依赖某 AD9528 profile”的外部引用字段，但不得
携带 AD9528 分频魔数，也不得将 GTX 的 76 个合法 line-rate tuple 复制为 AD9528
profile 表。对于当前 SFP+ Bank 111 GTX，这种引用应始终为空/不支持，除非未来
板级硬件与顶层 refclk 输入路径发生明确的设计变更。

## 8. 下一步前置条件

在任何 AD9528 写寄存器任务前，必须先取得并审核：

1. 目标 ADRV9009 mode 的正式 sample rate、JESD L/M/F/S/K、lane rate 与
   SYSREF 要求；
2. 对应 AD9528 register image 的来源和完整性；
3. OUT0/OUT1/OUT3/OUT12/OUT13 是否需要同时改变，以及改变期间 ADRV/JESD
   的复位、重同步和校准顺序；
4. AD9528 STATUS0/STATUS1、锁定和输出频率的实际硬件验证方法；
5. 若涉及 Bank 109/110 GTX，确认与 ADRV JESD 通道、GT quad、IBUFDS_GTE2、
   XDC 和 GT Wizard 的专用工程边界。

在上述条件满足前，当前正式 GTX supported-rate 列表、CPLL/QPLL/MMCM profile
和 AD9528 软件实现都应保持不变。

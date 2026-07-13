# AD9528 PLL2 细步进 TEST0 候选选择与安全状态

## 1. 当前结论

本阶段只进行候选枚举和寄存器镜像审计，不写 AD9528 PLL2，不修改 GT、RTL、BD/XDC 或 supported rates。当前结论仍为：

```text
NO_SAFE_PLL2_TEST0_CANDIDATE
```

原首选数学候选 `PLL2_TEST0_OUT0_124P8_CPLL_998P4` 已经被更高优先级的 ADI no-OS 驱动约束否决：其 `M1×N2=4×65=260`，而 0x0201 feedback calibration A/B divider 仅接受 16..255（并排除 18、19、23、27）。禁止将 B=65 截断到 6 bit，也不得将该候选生成可执行寄存器表。

## 2. 数学结果与寄存器可编码性不是同一层

原候选的频率公式本身成立：

```text
PFD         = 122.88 MHz / 8             = 15.36 MHz
VCO         = 15.36 MHz × 65 × 4         = 3993.6 MHz
OUT0 parent = 3993.6 MHz / 4             = 998.4 MHz
OUT0        = 998.4 MHz / 8              = 124.8 MHz
ODIV2 count = 124.8 MHz / 2 × 1 ms       = 62400
```

但 AD9528 同时使用两个不同字段：

- 0x0208：N2 divider，编码为 `N2-1`，N2=65 对应 0x40；
- 0x0201：feedback calibration divider A/B，ADI 驱动按 `M1×N2` 推导，`divider=4×B+A`，A 为 2 bit、B 为 6 bit。

因此 0x0208 可编码不代表完整 PLL2 profile 可校准。规划器现已将官方 calibration divider gate 纳入枚举。

## 3. 修正后的枚举结果

重新生成 `reports/ad9528_fine_step_test0/` 后：

- all candidates：274（含 VCXO direct 基线）；
- low-risk shortlist：20；
- exact 3000M experimental shortlist：0；
- 124.8 MHz / R1=8 / N2=65 / M1=4 已排除；
- 固定 `3000M/FIXED_125M_CPLL` 继续为 `BLOCKED/NO_LEGAL_VERIFIED_125M_CPLL_PROFILE`。

修正后的 shortlist 仍只是数学与器件字段合法候选，不代表 AD9528 register image、GT Wizard、MMCM、共享时钟树或上板结果已确认。

## 4. 当前已验证基线

`VCXO_122P88` 已完成四线 SPI、masked buffered write、IO_UPDATE、readback、snapshot/restore、FPGA ODIV2 计数及 UDP 回读验证。OUT0 约为 122.872～122.874 MHz；restore 后完整窗口为 `count=0/alive=0`。这只证明 VCXO direct 测量链路，不证明 PLL2。

## 5. PLL2 TEST0 仍需关闭的 gate

```text
PLL2 calibration divider must be encodable
charge-pump must be board-profile justified
loop-filter must be board-profile justified
full A/B/C board dumps must be collected
all OUT0..OUT13 consumers must be classified
SYNC/IGNORE mask impact must be confirmed
snapshot/restore must cover every modified byte
calibration/lock timeout must be defined
```

只要任一关键项为 UNKNOWN，就不得实现 `ad9528 candidate set pll2_test0`。

## 6. 完整运行时 dump

新增只读命令：

```text
ad9528 dump full
```

UART 以如下格式输出：

```text
AD9528_REG addr=0x0200 value=0xXX
```

覆盖 0000..000F、0100..010A、0200..0208、0300..032E、0400..0403、0500..0509；最后一段包含 0x0508/0x0509 两字节 readback。命令由 UDP 触发，UDP 只返回摘要，完整 `AD9528_REG` 行输出在 UART。命令本身只执行 SPI read，不执行 IO_UPDATE、SYNC、RESET，不改变 candidate/snapshot。

这里的“上电未 set”不是芯片绝对无软件干预的原始上电状态：应用启动时已经按现有四线 SPI 设计写入 `0x0000=0x18` 以启用独立 SDO。后续应分别保存：应用启动且未执行 candidate、VCXO candidate set 后、restore 后三份完整 dump。

## 7. 实现路径边界

AD9528 OUT0 实验路径与正式 fixed-125M profile 相互独立。候选不会进入正式 planner，不覆盖现有 11 档，不改变 3000M BLOCKED，不连接 Bank110 到 Bank111。下一步只能先根据真实 full dump 重新选择一组 calibration divider 合法的 PLL2 参数，再完成 register-image 与共享输出审计。

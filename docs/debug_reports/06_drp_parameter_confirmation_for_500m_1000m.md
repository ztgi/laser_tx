# 500M / 1000M 最小真实动态切换 DRP 参数确认报告

## 1. 本轮目标

本轮只做 500M Profile0 与 1000M Profile1 之间最小真实动态切换的 DRP 参数确认，不实现 RTL 状态机，不写 GTX DRP，不写 MMCM DRP，不重新生成 bit/LTX。

本轮确认范围：

```text
GTXE2_CHANNEL TXOUT_DIV DRP address / bitfield；
500M / 1000M 静态生成物中的 TXOUT_DIV / RXOUT_DIV / CPLL 参数；
MMCME2_ADV 500M / 1000M 参数；
MMCME2 DRP register 写入序列和候选写值；
reset / lock / readback / txusrclk2_alive 验证要求。
```

本轮禁止范围：

```text
不修改 RTL；
不修改 BD；
不修改 XDC；
不修改 Vitis；
不写 GTX DRP；
不写 MMCM DRP；
不接 AD9528；
不做 QPLL/CPLL 泛化；
不支持除 500M/1000M 外的任意速率；
不声明动态切换已实现或已上板通过。
```

## 2. 证据来源

本轮使用当前工程生成物与 Xilinx/Vitis 官方驱动源码交叉确认。

| 证据 | 路径 / 来源 | 用途 |
| --- | --- | --- |
| Profile0 GT generated HDL | `laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v` | 确认 500M static 的 CPLL / RXOUT_DIV / TXOUT_DIV |
| Profile1 1000M GT generated HDL | `_p1_1g_vivado/p1.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v` | 确认 1000M static 的 CPLL / RXOUT_DIV / TXOUT_DIV |
| Profile0 MMCM helper | `laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile0.v` | 确认 500M TX user clocking MMCM 参数 |
| Profile1 MMCM helper | `laser_tx.srcs/sources_1/new/laser_gt_usrclk_profile1_1000m.v` | 确认 1000M TX user clocking MMCM 参数 |
| Xilinx GTXE2 VPHY driver | `D:/Vitis/2022.2/data/embeddedsw/XilinxProcessorIPLib/drivers/vphy_v1_12/src/xvphy_gtxe2.c` | 确认 GTXE2 `OUT_DIV_PROG = 0x88`、bit mask、编码函数 |
| Xilinx MMCME2 VPHY driver | `D:/Vitis/2022.2/data/embeddedsw/XilinxProcessorIPLib/drivers/vphy_v1_12/src/xvphy_mmcme2.c` | 确认 MMCME2 DRP 地址、写入序列和无小数分频编码方法 |
| Xilinx XAPP888 口径 | `xvphy_mmcme2.c` 注释引用 XAPP888 | MMCM/PLL dynamic reconfiguration 编码依据 |

说明：本报告中的 MMCM 写值是按 Xilinx `xvphy_mmcme2.c` 中的整数分频、phase=0、duty=0.5、no fractional division 编码函数复算得到；这些值仍需在第二步 RTL 实现后通过 readback、LOCKED 和 `txusrclk2_freq_counter_axi` 上板验证闭环。

## 3. 当前 500M / 1000M 静态参数确认

### 3.1 GT 参数

当前两档均使用：

```text
CPLL_FBDIV      = 4
CPLL_FBDIV_45   = 4
CPLL_REFCLK_DIV = 1
TXDATA width    = 64 bit
encoding        = None
internal width  = 32 bit
CPLL            = used
```

两档差异如下：

| 参数 | 500M Profile0 | 1000M Profile1 |
| --- | ---: | ---: |
| TX line rate | 500 Mb/s | 1000 Mb/s |
| CPLL_FBDIV | 4 | 4 |
| CPLL_FBDIV_45 | 4 | 4 |
| CPLL_REFCLK_DIV | 1 | 1 |
| RXOUT_DIV | 8 | 4 |
| TXOUT_DIV | 8 | 4 |
| TXOUTCLK | 15.625 MHz | 31.25 MHz |
| TXUSRCLK | 15.625 MHz | 31.25 MHz |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz |

结论：

```text
500M -> 1000M 的 GT 差异主要是 TXOUT_DIV=8 -> 4。
由于 Profile1 生成物中 RXOUT_DIV 也从 8 变为 4，但当前 laser_tx 只声明 TX 路径验证，本阶段最小真实切换优先只修改 TXOUT_DIV，并在报告中明确不声明 RX/全双工动态切换。
```

## 4. GTXE2_CHANNEL TXOUT_DIV DRP 参数确认

### 4.1 DRP address

Xilinx `xvphy_gtxe2.c` 中定义：

```c
#define XVPHY_DRP_OUT_DIV_PROG 0x88
```

并在 `XVphy_Gtxe2OutDivChReconfig()` 中对地址 `0x88` 做 TX/RX output divider 的 read-modify-write。

结论：

```text
GTXE2_CHANNEL TXOUT_DIV / RXOUT_DIV 相关 DRP address = 9'h088。
```

### 4.2 DRP bitfield

Xilinx `XVphy_Gtxe2OutDivChReconfig()` 行为：

```c
read  DRP[0x88]

RX:
  mask out 0x07
  write RX_OUT_DIV encoding into bits [2:0]

TX:
  mask out 0x70
  write TX_OUT_DIV encoding into bits [6:4]
```

因此：

| 字段 | DRP address | bit | 写法 |
| --- | --- | --- | --- |
| RXOUT_DIV | `9'h088` | `[2:0]` | RMW，mask `~16'h0007` |
| TXOUT_DIV | `9'h088` | `[6:4]` | RMW，mask `~16'h0070` |

### 4.3 TXOUT_DIV encoding

Xilinx `XVphy_DrpEncodeCpllTxRxD()` 对 `D` 的编码：

| divider | DRP encoding |
| ---: | ---: |
| 1 | 0 |
| 2 | 1 |
| 4 | 2 |
| 8 | 3 |
| 16 | 4 |

本工程两档：

| 目标 | TXOUT_DIV | encoding | DRP[0x88][6:4] |
| --- | ---: | ---: | ---: |
| 500M | 8 | 3'b011 | `3 << 4 = 0x0030` |
| 1000M | 4 | 3'b010 | `2 << 4 = 0x0020` |

推荐写法：

```verilog
// readback = DRP[9'h088]
// target_enc = 3 for TXOUT_DIV=8, 2 for TXOUT_DIV=4
write_data = (readback & 16'hFF8F) | (target_enc << 4);
```

### 4.4 是否需要同步写 RXOUT_DIV

当前事实：

```text
500M static generated HDL: RXOUT_DIV=8, TXOUT_DIV=8
1000M static generated HDL: RXOUT_DIV=4, TXOUT_DIV=4
```

但当前 laser_tx 阶段性目标是 TX-only / TX 路径，不声明 RX/全双工。因此最小真实动态切换可以先只写 TXOUT_DIV，并保持 RXOUT_DIV bits `[2:0]` 不变。

风险与建议：

```text
1. 因 TXOUT_DIV 与 RXOUT_DIV 位于同一个 DRP word，必须 read-modify-write，不能整字覆盖。
2. 若后续要声明 RX 或全双工 500M/1000M 动态切换，必须同步定义 RXOUT_DIV 策略、RX reset sequence、RX lock/CDR 验证。
3. 当前最小 TX-only 切换报告中必须明确：不验证 RX 动态切换。
```

## 5. 是否需要 CPLL reset / TX reset

### 5.1 CPLL 参数是否变化

两档 generated HDL 均为：

```text
CPLL_FBDIV      = 4
CPLL_FBDIV_45   = 4
CPLL_REFCLK_DIV = 1
```

因此最小 500M/1000M 切换不需要修改 CPLL divider DRP。

### 5.2 CPLL reset

虽然 CPLL 参数不变，但 TXOUT_DIV 和 TX user clock MMCM 会改变，并且 GT TX reset sequence 需要重新建立 TX datapath / TX user ready / TX reset done 的已知状态。

建议：

```text
不强制 CPLL reset 作为必须步骤；
但状态机应保留可选 CPLL reset hook；
最小实现应至少 assert GT TX reset / txuserrdy=0，再修改 TXOUT_DIV 和 MMCM，最后 release TX reset 并等待 txresetdone。
```

若上板发现只 TX reset 不足以让 `txresetdone/gt_ready/txusrclk2_alive` 稳定恢复，再升级为包含 CPLL reset 的序列。

### 5.3 TX reset

必须需要 TX reset sequence。

建议顺序：

```text
1. quiesce laser_tx_core，禁止新的 APPLY/ENABLE；
2. 等 busy_tx=0 或 done_tx=1；
3. assert GT TX reset / txuserrdy=0；
4. assert MMCM reset；
5. 写 GTX TXOUT_DIV；
6. 写 MMCME2 DRP；
7. release MMCM reset，等待 tx_mmcm_locked；
8. release GT TX reset / txuserrdy=1；
9. 等 cplllock、txresetdone、gt_ready；
10. 验证 txusrclk2_alive 和 freq_counter window。
```

## 6. GTX DRP readback 验证

GTX TXOUT_DIV 可通过 DRP readback 验证：

```text
read DRP[9'h088]
check bits [6:4]
500M expected: 3'b011
1000M expected: 3'b010
```

注意：

```text
readback 只能证明 DRP field 写入成功；
不能单独证明 line rate 和 TXUSRCLK2 已正确恢复；
必须结合 cplllock / txresetdone / gt_ready / txusrclk2_alive / freq_counter window。
```

## 7. MMCME2 500M / 1000M 参数确认

### 7.1 当前静态 MMCM 参数

| 参数 | 500M Profile0 | 1000M Profile1 |
| --- | ---: | ---: |
| MMCM input TXOUTCLK | 15.625 MHz | 31.25 MHz |
| DIVCLK_DIVIDE | 1 | 1 |
| CLKFBOUT_MULT_F | 39.0 | 20.0 |
| CLKOUT1_DIVIDE | 39 | 20 |
| CLKOUT0_DIVIDE_F | 78.0 | 40.0 |
| TXUSRCLK | 15.625 MHz | 31.25 MHz |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz |

本工程两个 helper 均使用整数分频、phase=0、duty=0.5，不涉及 fractional MMCM 输出。

### 7.2 MMCME2 DRP register 写入序列

Xilinx `xvphy_mmcme2.c` 中 `XVphy_MmcmWriteParameters()` 对 MMCME2 的写入序列如下：

| 顺序 | DRP addr | 含义 |
| ---: | ---: | --- |
| 1 | `0x28` | Power register |
| 2 | `0x14` | CLKFBOUT Reg1 |
| 3 | `0x15` | CLKFBOUT Reg2 |
| 4 | `0x16` | DIVCLK_DIVIDE |
| 5 | `0x08` | CLKOUT0 Reg1 |
| 6 | `0x09` | CLKOUT0 Reg2 |
| 7 | `0x0A` | CLKOUT1 Reg1 |
| 8 | `0x0B` | CLKOUT1 Reg2 |
| 9 | `0x0C` | CLKOUT2 Reg1 |
| 10 | `0x0D` | CLKOUT2 Reg2 |
| 11 | `0x18` | Lock Reg1 |
| 12 | `0x19` | Lock Reg2 |
| 13 | `0x1A` | Lock Reg3 |
| 14 | `0x4E` | Filter Reg1 |
| 15 | `0x4F` | Filter Reg2 |

说明：

```text
当前工程只使用 CLKOUT0/CLKOUT1，但 Xilinx VPHY 写序列同时写 CLKOUT2。若 RTL 实现复用该序列，CLKOUT2 可按 divider=1 的安全值写入；若手写最小序列，也必须确认未使用输出不会影响当前 MMCM。
```

### 7.3 MMCME2 DRP 候选写值

以下写值按 Xilinx `xvphy_mmcme2.c` 的整数分频编码函数复算。

#### 500M Profile0 MMCM 写值

| DRP addr | value | 含义 |
| ---: | ---: | --- |
| `0x28` | `0xFFFF` | POWER |
| `0x14` | `0x14D4` | CLKFBOUT Reg1 |
| `0x15` | `0x0080` | CLKFBOUT Reg2 |
| `0x16` | `0x1041` | DIVCLK_DIVIDE |
| `0x08` | `0x19E7` | CLKOUT0 Reg1, divide 78 |
| `0x09` | `0x0000` | CLKOUT0 Reg2 |
| `0x0A` | `0x14D4` | CLKOUT1 Reg1, divide 39 |
| `0x0B` | `0x0080` | CLKOUT1 Reg2 |
| `0x0C` | `0x1041` | CLKOUT2 Reg1 |
| `0x0D` | `0x00C0` | CLKOUT2 Reg2 |
| `0x18` | `0x00FA` | LOCK Reg1 |
| `0x19` | `0x7C01` | LOCK Reg2 |
| `0x1A` | `0x7DE9` | LOCK Reg3 |
| `0x4E` | `0x0800` | FILTER Reg1 |
| `0x4F` | `0x9000` | FILTER Reg2 |

#### 1000M Profile1 MMCM 写值

| DRP addr | value | 含义 |
| ---: | ---: | --- |
| `0x28` | `0xFFFF` | POWER |
| `0x14` | `0x128A` | CLKFBOUT Reg1 |
| `0x15` | `0x0000` | CLKFBOUT Reg2 |
| `0x16` | `0x1041` | DIVCLK_DIVIDE |
| `0x08` | `0x1514` | CLKOUT0 Reg1, divide 40 |
| `0x09` | `0x0000` | CLKOUT0 Reg2 |
| `0x0A` | `0x128A` | CLKOUT1 Reg1, divide 20 |
| `0x0B` | `0x0000` | CLKOUT1 Reg2 |
| `0x0C` | `0x1041` | CLKOUT2 Reg1 |
| `0x0D` | `0x00C0` | CLKOUT2 Reg2 |
| `0x18` | `0x00F4` | LOCK Reg1 |
| `0x19` | `0x7C01` | LOCK Reg2 |
| `0x1A` | `0x7DE9` | LOCK Reg3 |
| `0x4E` | `0x0800` | FILTER Reg1 |
| `0x4F` | `0x1800` | FILTER Reg2 |

### 7.4 MMCM reset / locked sequence

必须要求：

```text
写 MMCM DRP 前 assert MMCM reset；
写完全部 DRP register 后 release MMCM reset；
等待 tx_mmcm_locked_sync=1；
如果 timeout，进入 RATE_ERROR，不更新 current_rate。
```

不能只看 DRP done 就认为 clocking 生效。

## 8. txusrclk2_alive / freq_counter 验证窗口

目标窗口建议：

| 目标速率 | TXUSRCLK2 | 建议窗口 |
| --- | ---: | ---: |
| 500M | 7.8125 MHz | 7.70 MHz ~ 7.95 MHz |
| 1000M | 15.625 MHz | 15.40 MHz ~ 15.90 MHz |

实现要求：

```text
txusrclk2 counter 必须在 txusrclk2 域自由运行；
AXI/FCLK 域只能通过安全 CDC 读取 toggle/snapshot；
不要把 txusrclk2 域多 bit counter 未同步直接接 AXI ILA；
rate switch 成功条件必须包含 txusrclk2_alive=1 和 freq_counter 落入目标窗口。
```

## 9. 最小真实切换是否具备进入第二步条件

本轮参数确认结论：

| 项目 | 结论 |
| --- | --- |
| GTXE2 TXOUT_DIV DRP address | 已确认：`9'h088` |
| TXOUT_DIV bitfield | 已确认：`[6:4]` |
| TXOUT_DIV=8 encoding | 已确认：`3'b011` |
| TXOUT_DIV=4 encoding | 已确认：`3'b010` |
| RXOUT_DIV companion field | 已确认同地址 `[2:0]`，最小 TX-only 切换先保留不变 |
| CPLL divider 是否变化 | 不变化 |
| CPLL reset 是否必须 | 非强制，但建议保留 hook；最小实现至少做 TX reset |
| TX reset 是否必须 | 必须 |
| GTX DRP readback | 可做，读 `9'h088[6:4]` |
| MMCM 500M 参数 | 已确认 |
| MMCM 1000M 参数 | 已确认 |
| MMCM DRP register 序列 | 已确认，来自 Xilinx `xvphy_mmcme2.c` |
| MMCM reset / locked sequence | 必须实现 |
| txusrclk2 验证窗口 | 已给出建议窗口 |

因此：

```text
DRP 参数确认通过，可以进入第二步“最小真实切换状态机”设计与实现。
```

但第二步仍必须遵守：

```text
只支持 500M / 1000M；
不支持其它速率；
不接 AD9528；
不做 QPLL/CPLL 泛化；
不声明 RX/全双工动态切换；
实现后必须重新 synthesis/implementation/bit/LTX；
未上板前不得写成动态切换通过。
```

## 10. 第二步实现建议

### 10.1 必需 RTL 能力

下一步最小真实切换状态机需要新增或接入：

```text
GT channel DRP port 控制；
TXOUT_DIV read-modify-write；
MMCM DRP port 控制；
MMCM reset 控制；
GT TX reset / txuserrdy 控制；
rate_state / error_code / current_rate / target_rate；
GT/MMCM DRP readback；
txusrclk2_alive / freq_counter check。
```

### 10.2 状态机建议

```text
RATE_IDLE
RATE_REQUEST
RATE_VALIDATE
RATE_QUIESCE_TX
RATE_ASSERT_RESET
RATE_PROGRAM_GT_DRP
RATE_PROGRAM_MMCM_DRP
RATE_RELEASE_RESET
RATE_WAIT_LOCK
RATE_VERIFY_RATE
RATE_DONE
RATE_ERROR
```

### 10.3 错误码建议

```text
UNSUPPORTED_RATE
TX_QUIESCE_TIMEOUT
GT_DRP_TIMEOUT
GT_DRP_READBACK_MISMATCH
MMCM_DRP_TIMEOUT
MMCM_LOCK_TIMEOUT
TX_RESETDONE_TIMEOUT
GT_READY_TIMEOUT
TXUSRCLK2_NOT_ALIVE
TXUSRCLK2_FREQ_OUT_OF_WINDOW
```

## 11. 本轮未修改内容

```text
未修改 RTL；
未修改 BD；
未修改 XDC；
未修改 Vitis；
未修改 build 脚本；
未重新生成 bit；
未重新生成 ltx；
未执行 synthesis；
未执行 implementation；
未执行 timing；
未执行 hardware test。
```

## 12. 当前结论

本轮只读确认已完成。GTXE2 TXOUT_DIV 的 DRP address / bitfield、500M/1000M 编码、MMCME2 DRP 写序列与候选写值均已形成可追溯证据。

可以进入下一步最小真实动态切换 RTL 实现，但必须限制在：

```text
500M Profile0 <-> 1000M Profile1；
TX-only；
不扩展任意速率；
不接 AD9528；
不做 QPLL/CPLL 泛化。
```

第二步实现后必须重新生成 bit/LTX 并上板验证；未上板前不得声明真实动态切换通过。

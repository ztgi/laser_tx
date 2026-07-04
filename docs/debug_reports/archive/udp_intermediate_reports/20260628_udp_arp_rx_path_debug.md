# UDP / ARP / GEM RX Path 调试报告

## 1. 本轮问题现象

当前真实上板现象如下：

```text
PHY 100M link up：已通过
UDP server ready：已通过
main loop alive：已通过
xemacif_input 持续调用：已通过
xemacif_input_nonzero_count：仍为 0
ARP：未通过
UDP PING：未通过
READ_STATUS：未测
READ_GT_STATUS：未测
```

PC 端现象：

```text
ping 192.168.1.10 timeout
arp -a | findstr 192.168.1.10 没有出现 192.168.1.10 的 dynamic MAC
NetAssist / PowerShell UDP PING 无回包
```

当前结论不能写成 UDP 已通过。PHY link up 和 UDP server bind ready 已经通过，但 PC 端尚未通过 ARP 获取板卡 MAC，因此 UDP PING 不可能正常回包。

## 2. 当前已通过的层级

已通过层级：

| 层级 | 状态 | 证据 |
|---|---|---|
| PHY 100M link up | 已通过 | 串口显示 `link speed for phy address 0: 100` |
| UDP server ready | 已通过 | 串口显示 `UDP server ready. Fixed Profile 0 only.` |
| main loop alive | 已通过 | 串口周期性打印 `UDP loop alive` |
| `xemacif_input()` 持续调用 | 已通过 | heartbeat 中 `xemacif_input_called_count` 持续增加 |
| netif 基本配置 | 已确认 | IP/netmask/gateway/up/link/MAC 均已打印 |

串口关键证据：

```text
lwIP IRQ platform setup done
link speed for phy address 0: 100
MAC = 02:00:00:00:00:01
netif ip      = 192.168.1.10
netif netmask = 255.255.255.0
netif gateway = 192.168.1.1
netif flags   = 0x0F
netif is up   = 1
netif link up = 1
UDP server ready. Fixed Profile 0 only.
UDP loop alive: xemacif_input_called_count=..., xemacif_input_nonzero_count=0
```

## 3. 当前未通过的层级

未通过或未验证层级：

| 层级 | 状态 | 说明 |
|---|---|---|
| `xemacif_input()` 非零返回 | 未通过 | `xemacif_input_nonzero_count` 仍为 0 |
| GEM RX frame seen | 未确认 | 当前尚未看到 RX frame 进入 adapter 的证据 |
| ARP | 未通过 | PC ARP 表没有 `192.168.1.10` dynamic MAC |
| UDP PING | 未通过 | ARP 未通过时 UDP 不可能通 |
| READ_STATUS | 未测 | UDP PING 未通前暂不测业务命令 |
| READ_GT_STATUS | 未测 | UDP PING 未通前暂不测业务命令 |

## 4. 根因假设

当前 main loop 在跑，netif 配置正确，但 `xemacif_input_nonzero_count` 始终为 0，说明 lwIP 轮询入口没有取到任何 packet。

因此本轮重点怀疑：

1. PC 的 ARP request 没有真正进入目标网口；
2. GEM RX DMA 没有收到 frame；
3. RX DMA descriptor / BD ring 没有完成；
4. GEM RX interrupt handler 没有触发或没有把 pbuf 放入 RX queue；
5. `xemacif_input()` 轮询的是空 RX queue；
6. cache / descriptor / RX buffer invalidate 路径仍需确认。

为什么不是 UDP 命令解析问题：

- ARP 未通过时，PC 不知道 `192.168.1.10` 对应的 MAC；
- UDP packet 不会正常发到板卡；
- 因此此阶段继续改 UDP 命令解析没有意义。

为什么不是主循环未运行问题：

- 用户已经看到 `UDP loop alive` 周期性打印；
- heartbeat 说明程序没有在 ready 后 return、死等或停住。

## 5. 本轮修改内容

本轮修改过的文件：

```text
bringup/src/main.c
BSP lwIP adapter: xemacpsif.c
BSP lwIP adapter: xemacpsif_dma.c
bringup/Debug/bringup.elf
```

具体修改：

1. `bringup/src/main.c`

   - 增加 `xemacif_input_called_count`；
   - 增加 `xemacif_input_nonzero_count`；
   - 在 `xemacif_input()` 返回非 0 时打印 `xemacif_input ret=<ret>`；
   - 在 `UDP loop alive` 中低频打印两个计数器；
   - 打印 netif IP、netmask、gateway、flags、up、link up、name；
   - 打印当前 MAC 地址；
   - MAC 改成本地管理单播地址 `02:00:00:00:00:01`；
   - 增加 lwIP IRQ platform setup，初始化并打开 Zynq GIC/IRQ。

2. `BSP lwIP adapter: xemacpsif.c`

   - 在 `low_level_input()` 返回 pbuf 时打印：

     ```text
     low_level_input returned pbuf len=<len> tot_len=<tot_len>
     ```

   - 在 `xemacpsif_input()` 中打印：

     ```text
     RX pbuf len=<len> tot_len=<tot_len> eth_type=<type>
     xemacpsif_input fed packet to lwIP
     xemacpsif_input dropped eth_type=<type>
     ```

3. `BSP lwIP adapter: xemacpsif_dma.c`

   - 在 GEM RX DMA handler 中打印：

     ```text
     GEM RX frame seen: bd_processed=<n> rxsr=<status>
     RX BD status=<status> len=<len>
     RX pbuf len=<len> tot_len=<tot_len>
     RX pbuf queued to lwIP adapter
     RX pbuf enqueue failed
     ```

4. `bringup/Debug/bringup.elf`

   - 已重新 clean build 生成；
   - 新增调试字符串已确认进入 ELF。

注意：

```text
xemacpsif.c / xemacpsif_dma.c 是 BSP 生成源码，如果后续 Regenerate BSP Sources，这些调试打点可能被覆盖。
```

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| MAC 地址 | `00:0a:35:00:01:10` | `02:00:00:00:00:01` | 排除 MAC 可疑或重复干扰 |
| netif 状态 | 不打印 | 打印 IP/netmask/gateway/flags/up/link/name | 确认软件实际网络配置 |
| IRQ 初始化 | 应用层未显式按 lwIP 示例初始化 GIC/IRQ | 增加 `Xil_ExceptionInit` / `XScuGic_DeviceInitialize` / `Xil_ExceptionEnableMask` | 排查 GEM RX handler 不触发问题 |
| `xemacif_input()` 返回值 | 调用但不统计 | 统计 called/nonzero，非 0 打印 ret | 判断轮询入口是否取到 packet |
| RX DMA handler | 无串口证据 | 打印 RX BD / RX pbuf / enqueue | 判断 GEM 是否收到 frame |
| `low_level_input()` | 无串口证据 | 打印 pbuf len/tot_len | 判断 RX queue 是否有包 |
| `xemacpsif_input()` | 无串口证据 | 打印 eth_type 和 lwIP 投递结果 | 判断 ARP/IP 是否送到 lwIP |
| UDP callback | 保留已有 RX/TX 打印 | 未重点修改命令解析 | ARP 通过后再验证 UDP |
| RTL/BD/XDC/GT Wizard | 未修改 | 未修改 | 硬件链路不变 |

## 7. 为什么这样修改

这些修改的目的不是“修 UDP 命令”，而是把 ARP 失败路径拆成可观察层级：

1. 如果 `xemacif_input_called_count` 增加，但 `xemacif_input_nonzero_count=0`：

   - 主循环在跑；
   - `xemacif_input()` 在调用；
   - 但 lwIP adapter 没从 RX queue 取到 packet。

2. 如果出现 `GEM RX frame seen`：

   - 说明 GEM RX DMA/BD 层已经看到外部以太网 frame；
   - 下一步看是否 enqueue 到 RX queue。

3. 如果出现 `low_level_input returned pbuf`：

   - 说明 packet 已经从 RX queue 进入 lwIP input path；
   - 下一步看 eth_type 是否为 ARP/IP。

4. 如果出现 `xemacpsif_input fed packet to lwIP`：

   - 说明 packet 已投递给 lwIP；
   - 如果 PC ARP 表仍无 dynamic MAC，则下一步查 lwIP ARP 层和 low_level_output。

5. 如果 ARP 出现 dynamic MAC：

   - 再继续测 UDP PING；
   - 期望串口出现 `UDP RX callback fired`、`UDP RX len=<len>`、`UDP TX response=OK PONG`。

## 8. 硬件接口一致性说明

本轮明确：

```text
未修改 RTL
未修改 BD
未修改 XDC
未修改 GT Wizard
未修改 txusrclk2
未做 GTX 动态改速率
未改变 Profile 0 固定发送链路
未改变 GPIO / BRAM / GT status 地址
```

网络参数保持：

```text
board IP = 192.168.1.10
PC IP    = 192.168.1.100
netmask  = 255.255.255.0
gateway  = 192.168.1.1
UDP port = 5005
```

本轮只改变软件侧 MAC 地址为：

```text
02:00:00:00:00:01
```

这是本地管理单播 MAC，不是全 0、不是全 FF、也不是组播 MAC。

## 9. 构建验证记录

已执行 BSP rebuild：

```bat
call D:\Vitis\2022.2\settings64.bat
make -C D:\FPGA_Learn\laser_tx\vitis_bringup\laser_tx_system_top\ps7_cortexa9_0\standalone_ps7_cortexa9_0\bsp clean all
```

结果：通过。

已同步新的 `liblwip4.a` 到 export BSP lib。

已执行 bringup clean build：

```bat
make -C D:\FPGA_Learn\laser_tx\vitis_bringup\bringup\Debug clean all
```

结果：通过。

ELF size：

```text
text = 140419
data = 3432
bss  = 3201088
```

已确认以下新增字符串进入 ELF：

```text
lwIP IRQ platform setup done
MAC =
netif ip
xemacif_input ret
xemacif_input_called_count
GEM RX frame seen
RX BD status
low_level_input returned pbuf
xemacpsif_input fed packet to lwIP
UDP RX callback fired
UDP TX response
```

## 10. 上板验证记录

已通过 XSCT 下载并运行新的 ELF：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf
```

用户观察到的当前关键结果：

```text
lwIP IRQ platform setup done
link speed for phy address 0: 100
MAC = 02:00:00:00:00:01
netif ip      = 192.168.1.10
netif netmask = 255.255.255.0
netif gateway = 192.168.1.1
netif flags   = 0x0F
netif is up   = 1
netif link up = 1
UDP server ready. Fixed Profile 0 only.
UDP loop alive: xemacif_input_called_count=..., xemacif_input_nonzero_count=0
```

PC 端关键证据：

```text
ping 192.168.1.10 timeout
arp -a | findstr 192.168.1.10 没有出现 192.168.1.10 的 dynamic MAC
NetAssist / PowerShell UDP PING 无回包
```

当前不能把 build 通过写成上板通过，也不能把 PHY link up / UDP server ready 写成 UDP PING 已通过。

## 11. 当前分层结论

| 层级 | 当前状态 |
|---|---|
| PHY 100M link up | 已通过 |
| UDP server ready | 已通过 |
| main loop alive | 已通过 |
| `xemacif_input()` 持续调用 | 已通过 |
| `xemacif_input_nonzero_count` | 仍为 0 |
| ARP | 未通过 |
| UDP PING | 未通过 |
| READ_STATUS | 未测 |
| READ_GT_STATUS | 未测 |

当前 main loop 在跑，netif 配置正确，但 `xemacif_input_nonzero_count` 始终为 0，说明 lwIP 轮询入口没有取到任何 packet。

下一步不应继续改 UDP 命令解析，而应继续定位 GEM RX / DMA RX descriptor / interrupt handler / RX queue / PC ARP frame 是否进入板卡。

## 12. 风险说明

1. `xemacpsif.c` / `xemacpsif_dma.c` 是 BSP 生成源码，后续 Regenerate BSP Sources 可能覆盖本轮调试打点。
2. 当前调试打印有限流，但如果 RX frame 大量进入，前 16 次仍会产生较密集串口输出。
3. 如果 `xemacif_input_nonzero_count` 继续为 0，说明问题仍在 UDP callback 之前。
4. 如果 GEM RX frame 完全看不到，软件层仍可能无法单独证明是网线/交换机/PC 路由/GEM RX DMA/PHY RX 时钟中的哪一项，需要结合 PC 抓包或硬件侧进一步确认。
5. 当前没有修改硬件工程，因此不能通过本轮修改修复任何 BD/XDC/PHY wiring 级问题。

## 13. 下一步建议

下一步按串口现象分支处理：

| 现象 | 说明 | 下一步 |
|---|---|---|
| `xemacif_input_nonzero_count` 仍为 0，且无 `GEM RX frame seen` | GEM/lwIP RX path 未看到 PC ARP frame | 查 PC 是否从正确网卡发 ARP、网线/交换机、是否必须交换机中转、GEM RX DMA/IRQ/PHY RX 时钟 |
| 有 `GEM RX frame seen`，但无 `low_level_input returned pbuf` | RX BD 层看到 frame，但未进入 RX queue | 查 RX pbuf enqueue、BD free/setup、cache/descriptor |
| 有 `low_level_input returned pbuf`，但无 `xemacpsif_input fed packet to lwIP` | packet 到 adapter，但 eth_type 或 input 处理异常 | 查 eth_type、ARP/IP 过滤、netif input |
| 有 `xemacpsif_input fed packet to lwIP`，但 PC ARP 仍无 MAC | lwIP ARP reply 或 TX path 问题 | 查 `etharp_input`、`low_level_output`、GEM TX |
| PC ARP 出现 `192.168.1.10` dynamic MAC | ARP 通过 | 再测 UDP `PING`，期望 `OK PONG` |

在 ARP 未通过前，不应继续重点改 UDP 命令解析，不应声明 UDP 控制层通过。

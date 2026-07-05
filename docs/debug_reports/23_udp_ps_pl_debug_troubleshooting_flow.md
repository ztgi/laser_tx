# UDP / PS / PL 联合调试通用故障定位流程

## 1. 文档目的

本文用于在 Zynq + PL rate controller + UDP 控制链路调试时，快速定位问题属于哪一层，而不是把所有异常都混成“PL RTL 坏了”或“UDP 坏了”。

在本项目中，常见现象包括：

- Windows `ping` 不通；
- UDP `PING` 无回包；
- Vivado Hardware Manager 能连 ILA，但 UDP server 无响应；
- `rate set` 返回 `ERROR`；
- `rate set` 返回 `DONE`，但 `current_rate` 不符合预期；
- program 新 bit/LTX 后 UDP 突然失效；
- 循环切换若干次后失败。

这些现象分属不同层级。正确调试方式应该是从网络、PS 软件、Vitis/AXI、PL rate controller、GT/MMCM、debug 工具逐级定位，而不是越层猜测。

核心原则：

```text
越靠前的问题，越不应该直接归因于 PL RTL。
```

例如 UDP `PING` 无回包时，UDP packet 可能还没有进入 Vitis command parser，更不一定已经触发 PL rate controller。此时优先检查 PS ELF、lwIP、IP/端口、网线/PHY，而不是先看 GT DRP 或 RTL FSM。

## 2. 推荐定位顺序

推荐按下面链路逐层排查：

```text
PC 网络配置
-> UART 确认 PS ELF/main/lwIP 是否运行
-> UDP PING
-> UDP command parser 是否收到
-> Vitis AXI 写 PL 是否执行
-> PL rate controller 是否进入状态机
-> GT/MMCM DRP/reset/lock/ready 是否恢复
-> current_rate / error_code 是否正确回报
```

每一层通过后，再进入下一层：

| 层级 | 通过标志 | 未通过时不要急着查 |
| --- | --- | --- |
| PC 网络 | PC IP、板端 IP、端口明确，网线/PHY 正常 | PL RTL |
| UART / PS/lwIP | 串口启动打印正常，确认 ELF/main/lwIP/UDP server ready | rate controller |
| UDP PING | 工程 UDP `PING` 有回包 | GT/MMCM |
| UDP parser | UDP `PING` / `rate status` 有响应 | GT/MMCM |
| Vitis/AXI | ILA 能看到 AXI GPIO/BRAM/status 写入 | GT DRP |
| PL rate controller | `rate_state/target_rate/error_code` 有变化 | 外部光口 |
| GT/MMCM | DRP done、MMCM lock、GT ready、txusrclk2 freq 正常 | UDP parser |
| 状态回报 | `current_rate/error_code/gt_ready` 与 ILA 一致 | 任意速率能力 |

## 3. 标准 bring-up 流程

建议每次换 bit/LTX 后都按固定流程执行，避免 PS/PL 状态不同步：

1. Program 当前 bit/LTX。
2. 执行 `rst -processor`。
3. Download / run Vitis ELF。
4. 查看串口启动打印。
5. 确认 PC IP，例如 `192.168.1.100`。
6. 确认板端 IP，例如 `192.168.1.10`。
7. 确认 UDP 目标端口，例如 `5005`。
8. 先发 UDP `PING`。
9. 再发 `rate status`。
10. 再发 `rate set 1000`。
11. 再发 `rate status`。
12. 再发 `rate set 500`。
13. 再发 `rate status`。
14. 最后执行循环切换。

推荐记录顺序：

```text
bit/LTX 路径
ELF 路径
串口启动日志
UDP PING 返回
rate status 返回
rate set 返回
ILA trigger 条件
ILA 关键波形或截图
```

## 4. 故障定位总表

| 现象 | 优先怀疑 | 建议动作 |
|---|---|---|
| 串口完全无打印 | ELF 未下载、CPU 未运行、串口终端参数错误 | `rst -processor`，重新 download/run ELF，检查串口波特率 |
| 串口打印停在 main start 后 | platform/init 或外设初始化卡住 | 在 `init_platform`、网口初始化、lwIP 初始化前后加打印 |
| 串口打印 IP 地址正常，但 UDP PING 无回包 | UDP bind、端口、回包路径或 PC 网络配置问题 | 打印 UDP bind 结果、端口号、收到包长度 |
| 串口能打印收到 PING，但 PC 无回复 | UDP send/reply 路径问题 | 打印 `sendto` 返回值，检查远端 IP/port |
| 串口能打印收到 rate set，但 ILA 中 target_rate 不变 | Vitis 到 PL 的 AXI 写失败或地址错误 | 在 AXI 写寄存器前后打印地址、数据、返回值 |
| 串口显示 rate set 已写入，但 PL 没动作 | request toggle / enable / AXI register map 问题 | 查 AXI GPIO/BRAM、ILA 中 request/target/profile_id |
| 串口显示 rate set 后一直等待 | PS 轮询硬件 done 卡住 | 打印轮询 timeout、rate_state、error_code |
| 串口显示 rate_state=ERROR | PL rate controller 已执行但失败 | 结合 ILA 查 DRP、reset、lock、ready |
| program bit 后 UDP 不通，但 rst processor 后恢复 | PS/PL 状态未重新同步 | 固定流程：program bit/LTX -> rst -processor -> run ELF -> 看 UART |
| Vivado 能连 ILA，但 UDP PING 无回包 | PS ELF 未运行 / lwIP 未启动 | `rst -processor`，重新 run ELF，查看串口 |
| Windows ping 不通，但 UDP 正常 | ICMP 未启用或被防火墙拦截 | 以 UDP `PING` / `rate status` 为主 |
| UDP PING 无回包，串口也无启动打印 | PS 程序未下载或未运行 | 重新下载 ELF，`con` 运行，检查启动日志 |
| UDP PING 无回包，但串口显示程序已启动 | IP、端口、网线、PHY、PC 网卡配置问题 | 查 PC IP、目标 IP、端口 5005、网线/PHY 灯 |
| UDP PING 正常，但 rate status 无响应 | UDP 命令解析分支缺失或字符串不匹配 | 查 Vitis 命令 parser，确认命令格式和换行 |
| UDP PING 正常，但 rate set 无响应 | 命令解析或 rate controller 接口问题 | 查 Vitis 命令解析、AXI 寄存器、ILA |
| UDP PING 正常，但 rate set 无响应 | Vitis 命令解析或 AXI 写 PL 失败 | 查 Vitis 命令解析、AXI GPIO/BRAM 写入、ILA |
| rate set 返回 ERROR | PL rate controller 执行失败 | 查 `rate_state/error_code/DRP/reset/lock/ready` |
| rate set 返回 DONE，但 current_rate 不对 | 状态更新或 profile_id 问题 | 查 target/current/profile table |
| rate set 返回 DONE，但 gt_ready=0 | 软件状态提前更新或 ready 判断不严 | 查 `current_rate` 是否只在 lock/ready 后更新 |
| rate set 卡住不返回 | Vitis 阻塞等待硬件 done，或状态机未退出 | 查 timeout 机制、串口打印、ILA 中 `rate_state` |
| rate set 1000 成功，rate set 500 失败 | 反向路径 reset/DRP/timeout 不完整 | 单独抓 1000→500 的 `rate_state/error/reset/lock/ready` |
| 第一次切换成功，第二次切换失败 | 状态机清零、done flag、request toggle 没恢复 | 查 request/ack toggle、done/error 清除逻辑 |
| UDP 初始正常，program bit 后失效 | PS/PL 状态不同步 | program 后 `rst -processor` 并重新 run ELF |
| program bit 后 ILA 正常但 UDP 不通 | PL 已配置，PS 程序未重启 | 不要先怀疑 RTL，先重启 processor/ELF |
| ILA 中 rate_state 没变化，但 UDP 已发命令 | Vitis 没写到 PL，AXI 地址或寄存器错误 | 查 AXI GPIO/BRAM 地址、Vitis 写寄存器返回值 |
| ILA 中 target_rate 变化，但 DRP 不动 | rate controller 没识别 request 或 validate 失败 | 查 `profile_supported/requested_rate_id/RATE_VALIDATE` |
| DRP attempted=1，但 done=0 | DRP ready 没返回或 DRP 时序问题 | 查 `drp_en/we/rdy`、timeout counter |
| DRP done=1，但 readback 不对 | DRP 地址/bitfield/encoding 错误 | 查 DRP addr/data/readback/mask |
| MMCM DRP done=1，但 locked=0 | MMCM 参数错误、reset 未释放、TXOUTCLK 异常 | 查 `tx_mmcm_reset/txoutclk_alive/locked_raw/sync` |
| txoutclk_alive=0 | GT TXOUTCLK 未输出，GT/CPLL/reset 问题 | 查 `cplllock`、GT reset、TXOUT_DIV、GT status |
| txoutclk_alive=1 但 txusrclk2_alive=0 | MMCM 未 lock 或 user clocking 问题 | 查 MMCM reset、locked、CLKOUT 配置 |
| txusrclk2_alive=1 但频率不对 | MMCM 分频表或 profile 预期窗口错误 | 查 `txusrclk2_freq_counter` 与 profile expected window |
| MMCM_LOCK_TIMEOUT | reset sequence、MMCM 参数、TXOUTCLK 三选一 | 先看 reset，再看 TXOUTCLK alive，再看 locked raw/sync |
| GT_READY_TIMEOUT | MMCM 已 lock，但 GT resetdone/txuserrdy 没恢复 | 查 `rate_gt_tx_reset/txuserrdy_block/txresetdone` |
| current_rate 提前变了，但硬件没 ready | 软件/RTL 状态更新条件错误 | 规定只能 VERIFY 成功后更新 `current_rate` |
| UDP 循环几次后失败 | 状态未清、timeout 不够、频率窗口偶发不满足 | 增加循环日志，抓失败那一次的 ILA |
| Windows 能 ping，但 UDP 无响应 | UDP 端口错误或程序未监听目标端口 | 查远端端口、本地端口、Vitis UDP bind |
| 同一 bit 有时通有时不通 | PS/PHY 初始化时序、processor 未干净启动 | 固定 bring-up 顺序：program bit → rst processor → run ELF |
| 换 bit 后 rate status 信息异常 | ELF 与 PL register map 不匹配 | 确认是否需要更新 XSA/Platform/BSP/ELF |
| Vitis 下载 ELF 后覆盖 bit | Vitis 设置里启用了 Program FPGA | 禁止 Vitis 自动 program FPGA，先 Vivado program bit/LTX，再单独 run ELF |
| ILA 没有 probe 或 mismatch | bit 和 LTX 不匹配 | 用同一次实现生成的 `.bit` 和 `.ltx` 重新 program |
| ILA 抓不到切换过程 | trigger 位置/条件不对，或切换太快 | trigger `rate_state==ASSERT_RESET/PROGRAM_DRP`，position 10%~20% |
| 串口打印正常但 rate 命令异常 | 命令格式、大小写、换行符问题 | 明确 UDP 命令格式，例如 `rate set 1000` |

## 5. 分层判断原则

### 5.1 网络层问题

网络层问题通常发生在 PS/lwIP 和 PL rate controller 之前。典型检查项：

- PC IP 是否在同一网段；
- 板端 IP 是否正确；
- UDP 目标端口是否正确；
- 网线、交换机、PHY link 灯是否正常；
- Windows 防火墙是否拦截 ICMP 或 UDP；
- 当前测试使用的是 Windows `ping` 还是工程 UDP `PING`。

注意：Windows `ping` 是 ICMP，工程 UDP `PING` 是应用层 UDP 命令。ICMP 不通不一定代表 UDP 不通；UDP 通也不代表 ICMP 必须通。

### 5.2 UART / 串口打印层问题

UART / `xil_printf` 是 PS 侧调试手段，不是 PL Verilog 调试手段。它能证明 PS 软件执行到哪里、UDP/lwIP 是否初始化、命令是否被 Vitis 收到和解析，但不能直接证明 PL 内部状态机、GT DRP 或 MMCM lock 一定正确。

UART 的主要作用是把问题先限定在 PS 软件链路内：

- 判断 ELF 是否运行；
- 判断 `main()` 是否进入；
- 判断 `init_platform` 是否完成；
- 判断 lwIP / netif / UDP server 是否初始化；
- 判断 UDP packet receive callback 是否被触发；
- 判断 UDP 命令是否收到；
- 判断 `rate set` / `rate status` 是否进入命令解析；
- 判断 AXI 写 PL 前后是否执行；
- 判断 `rate_state` / `error_code` / `current_rate` 回读结果。

因此，UART 的定位价值在于：

```text
如果 UART 没有 main/lwIP/UDP server 打印，
问题大概率还在 PS 软件或启动阶段；

如果 UART 显示 UDP 命令已收到，
但 ILA 中 PL 状态不变，
问题才进入 Vitis/AXI/PL 接口排查范围。
```

### 5.3 PS 软件层问题

PS 软件层决定 UDP server 是否存在。典型检查项：

- ELF 是否已经下载；
- 是否执行了 `con`；
- 串口是否打印启动日志；
- lwIP 是否初始化；
- UDP server 是否 bind 到预期端口；
- program bit 后是否执行过 `rst -processor`；
- Vitis 是否意外勾选了 Program FPGA 并覆盖当前 bit。

如果串口没有任何启动打印，应优先怀疑 ELF 没有运行，而不是 PL RTL。

### 5.4 Vitis/AXI 控制层问题

Vitis/AXI 控制层负责把 UDP 命令转成 AXI GPIO/BRAM/status 访问。典型检查项：

- UDP parser 是否识别命令；
- 命令格式、大小写、换行符是否符合程序要求；
- AXI GPIO base address 是否来自当前 `xparameters.h`；
- BRAM base address 是否正确；
- status register 是否能读回；
- ILA 中 AXI GPIO 输出是否变化；
- BRAM write/readback 是否符合预期。

如果 UDP `PING` 正常但 `rate set` 无响应，应优先查命令 parser 与 AXI 写入路径。

### 5.5 PL rate controller 层问题

PL rate controller 层负责把请求速率转换为 profile，执行 DRP/reset/lock/ready 流程。典型检查项：

- `request/ack` 是否变化；
- `target_rate` 是否进入 PL；
- `profile_supported` 是否为 1；
- `rate_state` 是否离开 IDLE；
- `error_code` 是否为 NONE；
- `current_rate` 是否只在 VERIFY 成功后更新；
- `rate_error` 是否被正确清除。

如果 `rate_state` 没变化，问题通常在 Vitis/AXI 到 PL request 之间；如果 `rate_state` 变化但进入 ERROR，才进入 DRP/reset/lock/ready 定位。

### 5.6 GT/MMCM 层问题

GT/MMCM 层是动态切换最容易失败的位置。典型检查项：

- GT DRP attempted/done/error；
- GT DRP addr/data/readback；
- MMCM DRP attempted/done/error；
- MMCM DRP addr/data/readback；
- `rate_gt_tx_reset`；
- `txuserrdy_block`；
- `txoutclk_alive_axi`；
- `tx_mmcm_reset`；
- `tx_mmcm_locked_raw`；
- `tx_mmcm_locked_sync`；
- `txresetdone_sync`；
- `gt_ready`；
- `txusrclk2_freq_counter_axi`。

判断顺序建议：

```text
DRP 是否完成
-> TXOUTCLK 是否存在
-> MMCM reset 是否释放
-> MMCM locked raw 是否拉高
-> locked sync 是否正确
-> txresetdone / gt_ready 是否恢复
-> txusrclk2 frequency 是否落入 profile window
```

### 5.7 Debug 工具层问题

Debug 工具层问题容易伪装成硬件失败。典型检查项：

- bit/LTX 是否来自同一次 implementation；
- Hardware Manager 是否报 mismatch；
- debug hub clock 是否稳定；
- ILA trigger 是否设置在正确状态；
- waveform cursor 是否停在有效窗口；
- txusrclk2 域 ILA 是否因为切换过程掉时钟而暂时不可用；
- AXI/FCLK ILA 是否作为 bring-up 主观察窗口。

Vivado 能看到 ILA，只说明 JTAG/debug hub 路径可用，不代表 UDP server 正常；UDP 正常，也不代表 ILA 一定匹配当前 bit/LTX。

## 6. 推荐 UART 打印点

UART 打印应该覆盖 bring-up 关键边界，而不是在高速循环里刷屏。推荐打印点如下：

| 打印位置 | 目的 |
| --- | --- |
| `main()` 入口 | 证明 ELF 已运行，CPU 已进入应用程序 |
| `init_platform` 前后 | 判断 platform 初始化是否卡住 |
| lwIP / netif 初始化前后 | 判断网口和协议栈是否初始化 |
| IP 地址设置后 | 确认板端 IP、netmask、gateway |
| UDP server bind 后 | 确认 UDP 端口监听成功 |
| UDP packet receive callback | 确认 PC packet 进入 PS 软件 |
| command parser 入口 | 确认命令字符串被解析 |
| `PING` 处理 | 区分 UDP 基础链路与 rate 控制链路 |
| `rate status` 处理 | 确认状态读取路径有效 |
| `rate set` 处理 | 确认切换命令进入软件分支 |
| AXI 写 PL 前后 | 确认写地址、写数据、返回值 |
| 轮询 `rate_state/error_code/current_rate` 时 | 定位是否卡在 PL done/error 等待 |
| 返回 UDP response 前 | 确认软件准备发送什么响应 |

建议打印内容保持短而结构化，例如：

```text
MAIN start
lwIP init done
UDP server ready port=5005
UDP RX len=...
CMD rate set target=1000
AXI write addr=... data=...
RATE poll state=... error=... current=...
UDP TX response=...
```

## 7. UART 使用注意事项

- UART 适合 bring-up 和故障定位，不适合替代 ILA 或示波器。
- UART / `xil_printf` 是 PS 侧调试手段，不是 PL Verilog 调试手段。
- 不要在高速数据路径或高频循环里大量打印，否则会严重改变软件时序。
- UDP callback 中只打印命令摘要、长度、关键错误码和必要状态。
- 长时间循环测试时应降低打印频率，例如每 N 次循环打印一次摘要。
- 如果需要排查超时，可以打印 timeout counter 的阶段性值，但不要每轮都打印。
- UART 正常不等于 PL 功能正确，仍需 UDP status、AXI readback 和 ILA 证据。
- UART 无打印时，优先排查 ELF 是否运行、串口波特率、processor reset、Vitis run 配置。

## 8. 面对质疑时的回答模板

### 问题 1：“ping 不通是不是 PL RTL 改坏了？”

不一定。`ping` / UDP 首先依赖 PS 上的 lwIP 程序和网口初始化。当 UDP `PING` 都无回包时，问题发生在 rate controller 之前，应先确认 ELF 是否运行、processor 是否 reset、IP/端口是否正确。只有 UDP parser 和 AXI 写入都确认正常后，才应继续怀疑 PL rate controller 或 RTL。

### 问题 2：“Vivado 能看到 ILA，为什么 UDP 还不通？”

ILA 走 JTAG/debug hub，UDP 走 PS Ethernet/lwIP，两条链路不同。ILA 正常只说明 PL debug 通，不代表 PS UDP server 已启动，也不代表 ELF 正在运行。相反，UDP 正常也不代表 LTX 一定与 bit 匹配。

### 问题 3：“为什么 program bit 后要 rst -processor？”

Vivado Program Device 主要配置 PL，不一定让 PS 软件重新初始化。program bit 后 PS 可能停在旧状态，或者 PS 软件仍认为外设处于旧状态。执行 `rst -processor` 并重新 run ELF，可以让 lwIP、AXI 外设访问和 UDP server 回到干净状态。

推荐顺序：

```text
Program bit/LTX
-> rst -processor
-> run ELF
-> check serial boot log
-> UDP PING
-> rate status
```

### 问题 4：“rate set DONE 就一定说明硬件完全正常吗？”

不一定。`DONE` 只能说明软件可见状态返回完成。还应结合：

- `current_rate`；
- `error_code`；
- `gt_ready`；
- ILA 中 DRP/reset/lock/ready；
- `txusrclk2_freq_counter_axi`；
- 必要时的外部示波器或误码率测试。

`DONE` 不能替代外部光口闭环、示波器或长期稳定性验证。

### 问题 5：“UDP 循环通过是不是等于宽范围动态调速完成？”

不是。UDP 循环通过只说明当前已支持的 profile 在当前测试次数内可切换，不等于：

- 任意速率可调；
- 宽范围动态调速完成；
- AD9528/refclk 动态切换完成；
- 外部光口质量通过；
- 长期稳定性或误码率验证完成。

### 问题 6：“为什么你说不是 PL RTL 问题？”

如果串口没有 `main/lwIP/UDP server` 打印，或者 UDP `PING` 根本没有进入命令解析，说明问题发生在 PS 软件或网络层，rate controller 尚未参与。只有当 UART 显示 UDP 命令已收到并且 Vitis 已执行 AXI 写 PL 后，才进入 PL rate controller / GT / MMCM 的排查范围。

换句话说，UART 可以帮助确认问题有没有越过 PS 软件边界：

```text
没有 UART 启动打印
=> 先查 ELF/CPU/UART/lwIP；

UART 收到 UDP 命令，但 PL ILA 不动
=> 查 Vitis AXI 写 PL；

UART 写 PL 后，ILA 中 rate_state 进入 ERROR
=> 查 PL rate controller / GT / MMCM。
```

## 9. 与本项目当前阶段的关系

本项目中曾出现 program 新 bit 后 UDP/PING 不通的情况，后续通过 `rst -processor` 和重新运行 ELF 恢复。恢复后，profile table 重构后的 500M/1000M UDP 回归通过。

这说明当时 UDP 不通更像 PS/lwIP/processor 状态问题，不是 profile table RTL 的直接错误。这个经验应继续用于后续：

- 2G static bring-up；
- dynamic 2G profile 集成；
- 多速率 profile table 扩展；
- 长时间循环切换调试。

尤其在 2G static 阶段，build/timing 通过只说明 bit/LTX 可以生成。上板时仍应先按本文流程确认 PS/lwIP/UDP，再进入 GT/MMCM/ILA。

## 10. 当前边界

本文是调试流程文档，不是功能验证报告。

本文不证明：

- 2G static 上板通过；
- `rate set 2000` 可用；
- 宽范围动态调速完成；
- 外部光口链路通过；
- 示波器验证完成；
- 误码率验证完成；
- 长期循环稳定性完成。

本文也不把 UDP 正常等同于所有硬件功能完成。UDP 正常只是说明 PS/lwIP/命令链路至少部分可用，后续仍需结合 AXI/ILA/GT/MMCM/外部测量逐层确认。

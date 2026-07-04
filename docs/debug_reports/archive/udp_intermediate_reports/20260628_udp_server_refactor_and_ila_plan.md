# UDP Server 代码整理与 ILA 验证准备报告

## 1. 本轮问题现象

用户已确认当前 UDP 基础链路已经恢复：

```text
PS7 ENET0 MDIO / PHY / ARP / UDP 基础链路已经恢复
UDP 已经连上
PHY link up 已通过
UDP server ready 已通过
ARP 已恢复
```

本轮问题不是继续追 GEM RX / DMA / RX queue，而是当前 `bringup/src/main.c` 中堆叠了较多 UDP/lwIP 相关实现：

- lwIP include 与 `LASER_HAS_LWIP` 判断；
- GIC/IRQ 初始化；
- netif / MAC / IP debug 打印；
- UDP callback；
- UDP 命令解析；
- UDP 回包；
- UDP 主循环与 heartbeat。

这些内容集中在 `main.c` 中，不利于后续维护和固定 Profile 0 UDP 控制链路验证。

## 2. 为什么需要整理

整理目标是把“调试版 UDP server 代码”拆成可维护的软件结构，同时保留必要调试能力。

整理前：

- `main.c` 同时承担 UART_TEST、UDP server、命令协议、lwIP 初始化和 debug 打印；
- 后续继续增加 READ/WRITE/ILA 验证支持时，`main.c` 会越来越难维护；
- UDP 已经连通后，`UDP loop alive`、RX/TX 细节、netif 详情等打印需要可控，避免长期刷屏。

整理后：

- `main.c` 只保留应用模式选择、`LASER_HAS_LWIP` 打印、UART test 和 UDP server 薄 wrapper；
- UDP server 的初始化、协议解析、回包、lwIP/netif/GIC 逻辑移入 `laser_udp_server.c`；
- `LASER_UDP_DEBUG` 统一控制详细 debug 打印；
- 关键错误打印仍保留，不受 debug 宏关闭影响。

## 3. 修改目标

本轮只修改 Vitis / bare-metal 软件侧，目标如下：

1. 新增 `bringup/src/laser_udp_server.c` 与 `bringup/src/laser_udp_server.h`。
2. 将 UDP/lwIP/netif/GIC/命令解析/回包/主循环从 `main.c` 移出。
3. 保留原有 stub 机制，不删除 `LASER_HAS_LWIP` 判断。
4. 保持 UDP 命令协议和返回格式不变。
5. 保持固定 Profile 0 控制语义，不实现 GTX 动态改速率。
6. 保持现有网络参数不变：

```text
board IP = 192.168.1.10
UDP port = 5005
MAC      = 02:00:00:00:00:01
PHY link speed = CONFIG_LINKSPEED100
```

## 4. 修改文件列表

| 文件 | 类型 | 修改内容 |
|---|---|---|
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/main.c` | 应用源码 | 移除 UDP/lwIP 具体实现，只保留模式选择、UART 测试、`run_udp_server()` 薄 wrapper |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/laser_udp_server.h` | 新增应用头文件 | 定义 `LASER_HAS_LWIP` 检测、`LASER_UDP_DEBUG` 默认值、声明 `laser_udp_server_run()` |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/laser_udp_server.c` | 新增应用源码 | 承载 UDP server 初始化、lwIP init、xemac_add、netif setup、UDP bind、callback、命令解析、回包和主循环 |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/src/subdir.mk` | Vitis app 生成 makefile | 加入 `laser_udp_server.c` 的编译对象，保证命令行 `make clean all` 可直接构建 |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf` | 构建产物 | clean build 后重新生成 |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf.size` | 构建产物 | clean build 后重新生成 size 记录 |

说明：`Debug/src/subdir.mk` 是 Vitis 自动生成文件。由于本轮要求直接执行 `make -C ... clean all`，需要让当前命令行构建显式包含新增 `.c` 文件。若后续在 Vitis GUI 中重新生成 managed build files，需确认 `laser_udp_server.c` 仍被纳入 build。

## 5. 修改前后结构对比

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| `main.c` 职责 | UART_TEST + UDP server + lwIP + callback + 命令解析 + 回包 + debug | UART_TEST + 模式选择 + UDP 薄 wrapper | `main.c` 更清晰 |
| UDP 初始化 | 在 `main.c::run_udp_server()` 内 | `laser_udp_server_run()` 内 | 行为不变，位置变化 |
| lwIP include | `main.c` 中条件 include | `laser_udp_server.c` 中条件 include，`laser_udp_server.h` 保留 `LASER_HAS_LWIP` 检测 | 保留 stub 机制 |
| UDP callback | `main.c::laser_udp_recv()` | `laser_udp_server.c::laser_udp_recv()` | 协议行为不变 |
| 命令解析 | `main.c::handle_udp_command()` | `laser_udp_server.c::handle_udp_command()` | 返回格式不变 |
| netif debug 打印 | 无统一宏控制 | 受 `LASER_UDP_DEBUG` 控制 | 可减少刷屏 |
| 关键错误打印 | 始终打印 | 始终打印 | 保留故障定位能力 |
| BSP / XSA | 未修改 | 未修改 | 硬件平台依赖不变 |
| UDP 协议 | 已实现固定 Profile 0 控制命令 | 保持原协议 | 不改变 PC 端脚本/工具 |

## 6. UDP 命令协议说明

本轮整理保持以下 UDP 命令语义不变：

```text
PING
READ_STATUS
READ_GT_STATUS
WRITE_CONFIG
SELECT_CONFIG
APPLY
ENABLE
DISABLE
SOFT_RESET
```

返回格式保持不变：

```text
OK PONG
OK STATUS 0x...
OK GT_STATUS 0x...
OK WRITE_CONFIG <index>
OK SELECT_CONFIG <index> <direct_source> <direct_len_127>
OK APPLY
OK ENABLE
OK DISABLE
OK SOFT_RESET
ERR ...
```

最小 UDP 验证命令建议：

```text
PING
READ_GT_STATUS
WRITE_CONFIG 0 0x5A 1 0 1 6 0 0 0 0 0 0
SELECT_CONFIG 0 0 0
APPLY
READ_STATUS
ENABLE
READ_STATUS
DISABLE
READ_STATUS
```

命令作用：

- `PING`：验证 UDP 通信与回包路径。
- `READ_GT_STATUS`：读取 GT ready / lock / reset done 等状态。
- `WRITE_CONFIG`：写 BRAM 配置。
- `SELECT_CONFIG`：选择配置 index、direct/PRBS source、direct_len_127。
- `APPLY`：触发配置加载进入 PL。
- `READ_STATUS`：读取配置结果和状态位。
- `ENABLE`：置位 enable，启动发送侧状态机。
- `DISABLE`：清 enable，关闭发送。

## 7. APPLY / ENABLE 的软件含义

`APPLY` 的软件动作：

- 调用 `laser_gpio_toggle_apply()`；
- 在 AXI GPIO 控制口产生 apply 触发；
- 期望 PL 侧配置加载逻辑在 txusrclk2 域产生 `dbg_cfg_update_pulse_tx`。

`ENABLE` 的软件动作：

- 调用 `laser_gpio_set_enable(gpio, 1)`；
- 置位 enable 控制位；
- 在配置有效且 GT ready 的前提下，期望 TX engine 进入 busy 并输出 `valid_mask` / `txdata`。

注意：

- `OK APPLY` 只表示软件已执行 GPIO apply 写操作，不等同于 ILA 已抓到 `dbg_cfg_update_pulse_tx`。
- `OK ENABLE` 只表示软件已置位 enable，不等同于 TX 发送链路已完成 ILA 验证。
- 没有示波器实测时，不能声明外部同步引脚电气波形通过。

## 8. ILA 验证步骤

### APPLY 阶段

Vivado Hardware Manager 中 ILA2 trigger：

```text
dbg_cfg_update_pulse_tx == 1
```

操作步骤：

1. 在 Vivado Hardware Manager 中选择 TX 侧 ILA。
2. 设置 trigger 为 `dbg_cfg_update_pulse_tx == 1`。
3. 点击 Run Trigger。
4. PC 端发送：

```text
APPLY
```

观察信号：

```text
dbg_cfg_update_pulse_tx
dbg_pattern_valid_tx
dbg_current_state_tx
dbg_phase_offset_tx
```

### ENABLE 阶段

Vivado Hardware Manager 中 ILA2 trigger：

```text
dbg_busy_tx == 1
```

操作步骤：

1. 在 Vivado Hardware Manager 中选择 TX 侧 ILA。
2. 设置 trigger 为 `dbg_busy_tx == 1`。
3. 点击 Run Trigger。
4. PC 端发送：

```text
ENABLE
```

观察信号：

```text
dbg_busy_tx
dbg_done_tx
dbg_phase_active_tx
dbg_phase_start_pulse_tx
dbg_pattern_valid_tx
valid_mask[63:0]
txdata[63:0]
eom_out
soa_gate_out
acq_trig_out
acq_gate_out
```

判定口径：

- APPLY 通过只能说明 UDP 配置加载触发进入 PL。
- ENABLE + ILA 抓到 busy / valid_mask / txdata，才能说明 UDP 控制启动 TX。
- 没有示波器时，不能声明外部同步引脚电气波形通过。

## 9. 构建验证记录

已执行命令：

```bat
call D:\Vitis\2022.2\settings64.bat
make -C D:\FPGA_Learn\laser_tx\vitis_bringup\bringup\Debug clean all
```

执行结果：

```text
Build passed
```

ELF size：

```text
text    data    bss      dec      hex      filename
140095  3432    3201088  3344615  3308e7  bringup.elf
```

ELF 字符串检查结果：

| 字符串 | 是否存在 |
|---|---|
| `UDP server ready. Fixed Profile 0 only.` | 是 |
| `OK PONG` | 是 |
| `OK STATUS` | 是 |
| `OK GT_STATUS` | 是 |
| `OK APPLY` | 是 |
| `OK ENABLE` | 是 |
| `LASER_APP_MODE=%d` | 是 |
| `LASER_HAS_LWIP=%d` | 是 |

真实 UDP 分支 / stub 分支检查：

| 检查项 | 结果 |
|---|---|
| 真实 UDP 分支命令列表字符串存在 | 是 |
| `ERROR: current BSP does not provide lwIP headers/libraries.` stub 字符串存在 | 否 |

BSP include 检查：

| 文件 | 是否存在 |
|---|---|
| `lwip/init.h` | 是 |
| `lwip/udp.h` | 是 |
| `netif/xadapter.h` | 是 |

lwIP GEM 配置检查：

```text
XLWIP_CONFIG_INCLUDE_GEM = 1
XLWIP_CONFIG_EMAC_NUMBER = 0
```

本轮未修改 BSP generated source，因此未执行 BSP clean build。

## 10. 上板验证记录

本轮代码整理后未执行新的 hardware test。

```text
Hardware test was not run after this refactor
```

用户在本轮修改前已确认：

```text
UDP 已经连上
PS7 ENET0 MDIO / PHY / ARP / UDP 基础链路已经恢复
```

这些结论不能自动扩大为“本轮重构后的 UDP 控制链路已上板通过”。重构后的 ELF 仍需重新下载并执行最小 UDP 命令验证。

## 11. 当前分层结论

| 层级 | 当前结论 |
|---|---|
| PS7 ENET0 MDIO 修复 | 已完成，用户已确认基础链路恢复 |
| PHY link up | 已通过，用户已确认 |
| UDP server ready | 修改前已通过；本轮重构后 build 通过，待重新上板确认 |
| ARP | 修改前已通过；本轮重构后待重新上板确认 |
| UDP PING | 用户确认 UDP 已连上；本轮重构后待重新发送 `PING` 确认 |
| READ_STATUS | 本轮未执行 hardware test，待验证 |
| READ_GT_STATUS | 本轮未执行 hardware test，待验证 |
| APPLY + ILA | 待验证 |
| ENABLE + ILA | 待验证 |
| 外部同步引脚示波器验证 | 未执行 |

## 12. 风险说明

1. `Debug/src/subdir.mk` 是 Vitis 自动生成文件，后续若 Vitis 重新生成 managed build files，需要确认 `laser_udp_server.c` 仍在 build source list 中。
2. 本轮只做软件结构整理，未修改 RTL / BD / XDC / GT Wizard / txusrclk2。
3. UDP 协议字符串通过 ELF 检查确认仍存在，但这不是上板功能通过证明。
4. `LASER_UDP_DEBUG` 当前默认 1，便于继续命令验证；后续稳定后可改为 0 减少串口打印。
5. `laser_udp_init_control_hw()` 与 `main.c` 中 UART 测试初始化逻辑保持同等动作，但位于 UDP 模块内；后续若要进一步去重，可单独整理公共初始化模块，本轮未做该扩展。

硬件接口一致性说明：

```text
未修改 RTL
未修改 BD
未修改 XDC
未修改 GT Wizard
未修改 txusrclk2
未做 GTX 动态改速率
未改变 Profile 0 固定发送链路
未改变 GPIO / BRAM / GT status 地址
未改变 UDP 命令协议
```

## 13. 下一步建议

建议下一步按以下顺序执行上板验证：

1. 下载本轮重新构建的 `bringup.elf`。
2. 串口确认：

```text
LASER_APP_MODE=1
LASER_HAS_LWIP=1
UDP server ready. Fixed Profile 0 only.
```

3. PC 端依次发送：

```text
PING
READ_GT_STATUS
WRITE_CONFIG 0 0x5A 1 0 1 6 0 0 0 0 0 0
SELECT_CONFIG 0 0 0
APPLY
READ_STATUS
ENABLE
READ_STATUS
DISABLE
READ_STATUS
```

4. APPLY 前设置 ILA2 trigger：

```text
dbg_cfg_update_pulse_tx == 1
```

5. ENABLE 前设置 ILA2 trigger：

```text
dbg_busy_tx == 1
```

6. 若 UDP 回包正常但 ILA 未触发，不要先改 UDP 协议，应继续按 APPLY/ENABLE 分层检查 GPIO 控制位、TX 域 CDC、engine start 和 TX 状态机。

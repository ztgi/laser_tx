# Runtime-rate Vitis platform refresh report

## 1. 修改摘要

新增 `scripts/create_runtime_rate_artifact_vitis_platform.tcl`，使用 timing-clean XSA 在独立短路径 workspace `reports/runtime_rate_vitis` 中创建 Vitis 2022.2 hardware platform、standalone domain 和 BSP，并加载 `lwip211 v1.8`。旧 `vitis_bringup/laser_tx_system_top` 未被覆盖。

## 2. 修改前问题

旧 Vitis platform 的 `xparameters.h` 不包含 runtime dynamic mailbox 与 descriptor BRAM 的正式符号，应用只能依赖 `laser_hw.h` 中的手写 fallback。该状态不能作为正式 artifact 发布依据。

第一次全新 workspace 尝试还暴露两个 Vitis 2022.2 构建条件：

1. 必须先加载 `lwip211`，再设置 `dhcp_does_arp_check`/`phy_link_speed`；
2. Windows 下过深 workspace 路径导致 BSP core headers 未复制，表现为 `xpseudo_asm.h`、`xil_types.h`、`xparameters_ps.h` 缺失。

## 3. 修改后结构

脚本使用短路径 `reports/runtime_rate_vitis`，先生成基础 standalone BSP，再加载 lwIP、写入库参数并重新生成 platform。平台输入只来自：

`reports/ad9528_gt_rate_planner/artifact_build/artifacts/laser_tx_board_top_runtime_rate_switch.xsa`

生成结构：

- platform：`runtime_rate_artifact_platform`；
- processor：`ps7_cortexa9_0`；
- domain：`standalone_ps7_cortexa9_0`；
- OS：standalone；
- library：`lwip211 v1.8`；
- stdin：`ps7_uart_1`；
- Ethernet BSP配置：100 Mbps，DHCP ARP check=false。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| Platform来源 | 旧 XSA/多次 updatehw 历史 | 单一 timing-clean XSA | 消除旧平台污染 |
| Workspace | `vitis_bringup`旧工程 | 独立 `reports/runtime_rate_vitis` | 不覆盖旧平台 |
| Mailbox符号 | 旧 BSP缺失 | `XPAR_AXI_GPIO_DYNAMIC_MAILBOX_BASEADDR` | 正式地址可用 |
| Descriptor符号 | 旧 BSP缺失 | `XPAR_AXI_BRAM_DYN_DESC_S_AXI_BASEADDR` | 正式地址可用 |
| lwIP | 旧平台已有 | 新 BSP重新生成 `lwip211 v1.8` | 应用可 clean link |
| XSA / Platform / BSP | 旧依赖 | 新依赖 | 有意刷新 |
| 应用源码 | 未改 | 未改 | 下一提交处理 fallback/build |
| hardware test | 未执行 | 未执行 | `board_verified=0` |

## 5. 硬件接口一致性说明

新 `xparameters.h` 的正式地址：

| 外设 | 正式符号 | 地址 |
|---|---|---:|
| Dynamic mailbox AXI GPIO | `XPAR_AXI_GPIO_DYNAMIC_MAILBOX_BASEADDR` | `0x40040000` |
| Dynamic descriptor AXI BRAM | `XPAR_AXI_BRAM_DYN_DESC_S_AXI_BASEADDR` | `0x42000000` |
| 原配置BRAM | `XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR` | `0x40000000` |
| 原控制GPIO | `XPAR_AXI_GPIO_0_BASEADDR` | `0x41200000` |
| GT status GPIO | `XPAR_AXI_GPIO_GT_STATUS_BASEADDR` | `0x40020000` |
| AD9528 measure GPIO | `XPAR_AXI_GPIO_AD9528_MEASURE_BASEADDR` | `0x40030000` |

PS SPI1仍为 `0xE0007000`，UART1仍为 `0xE0001000`，Ethernet0仍为 `0xE000B000`。SPI controller、slave-select、CPOL/CPHA和应用初始化序列本阶段未改。

## 6. 时钟与复位说明

Clock/reset behavior unchanged。平台刷新没有改变硬件 XSA内容，只重新生成软件可见定义。没有新增软件或硬件时钟域，也没有改变 reset polarity/source。

## 7. AXI地址与软件影响

AXI address map unchanged。新 BSP首次正式暴露 dynamic mailbox 与 descriptor BRAM 符号；地址与目标 XSA一致。下一步应用必须删除硬件构建中的 silent fallback，使缺少这些正式符号时编译失败。

XSA / Platform / BSP dependency changed intentionally。应用必须使用本次新 platform/BSP重新 clean build。

## 8. 构建与测试验证

执行：

```text
D:\Vitis\2022.2\bin\xsct.bat scripts/create_runtime_rate_artifact_vitis_platform.tcl
```

最终结果：`RUNTIME_RATE_VITIS_PLATFORM=PASS`。基础 standalone BSP、FSBL BSP和 `lwip211 v1.8` 均完成编译。lwIP vendor source产生已有的 implicit-fallthrough warnings；没有 platform build error。

Hardware test was not run.

## 9. XSA / Platform / BSP影响

- XSA：使用本次新导出的 timing-clean XSA；
- platform：全新创建；
- BSP：全新生成；
- `xparameters.h`：已更新并含 mailbox/descriptor正式符号；
- linker script：应用尚未创建，本阶段未改；
- 旧 platform：保留但不作为候选 artifact输入。

## 10. 内存与启动风险说明

本阶段未构建应用 ELF，因此 `.text/.data/.bss/heap/stack` 尚未复核。Memory usage not confirmed; check ELF/map file is recommended.

## 11. 修改文件列表

| File | Change |
|---|---|
| `scripts/create_runtime_rate_artifact_vitis_platform.tcl` | 新建干净 platform/BSP生成脚本 |
| `reports/ad9528_gt_rate_planner/artifact_build/vitis_platform_manifest.txt` | 记录 XSA、platform与正式地址证据 |
| `docs/debug_reports/51_runtime_rate_vitis_platform_refresh_report.md` | 本报告 |

没有修改 BD、XDC、XCI、XPR、RTL或旧 Vitis platform generated files。

## 12. 风险与后续建议

1. 新应用尚未 clean build；必须确认16个源文件全部进入 managed object list。
2. 必须删除硬件应用的 mailbox/descriptor silent fallback。
3. 必须检查新 ELF/map 不引用旧 workspace/platform路径。
4. 本阶段没有上板；SPI、UDP、mailbox和runtime切换仍需匹配 bit/LTX/ELF首次回归。

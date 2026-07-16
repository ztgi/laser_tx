# Runtime-rate firmware artifact closure report

## 1. 修改摘要

本阶段使用 timing-clean XSA生成的新 platform/BSP clean build runtime-rate `bringup` 应用。修改 `laser_hw.h`，删除 dynamic mailbox 与 descriptor BRAM 的硬件应用静默地址 fallback；新增 clean app、linker map与release manifest脚本。最终得到16源文件 managed ELF、linker map和全套 SHA-256 manifest。

## 2. 修改前问题

旧 `laser_hw.h` 在 BSP缺少正式符号时静默使用 `0x40040000` 和 `0x42000000`。即使 firmware 与错误 XSA/platform组合，编译仍可能成功，无法在 artifact发布前暴露硬件/软件不匹配。

旧 workspace 还不能证明全部16个 runtime planner/coordinator/mailbox/AD9528源文件均由新 BSP clean重编译，也没有对应 linker map和统一 artifact SHA-256。

## 3. 修改后结构

`laser_hw.h` 现在只接受新 BSP 的正式符号：

- `XPAR_AXI_GPIO_DYNAMIC_MAILBOX_BASEADDR`；
- `XPAR_AXI_BRAM_DYN_DESC_S_AXI_BASEADDR`，兼容同一 BSP可能提供的无 `_S_AXI`正式别名。

缺少符号时编译以 `#error` 明确失败，不再继续使用手写地址。

`create_runtime_rate_artifact_vitis_app.tcl` 在全新 workspace创建 Empty Application、导入源目录并断言 `.c`数量为16。随后真实执行 `make clean` 和 `make all`。`generate_runtime_rate_linker_map.ps1`严格按 managed `src/subdir.mk` object顺序做 map-only relink，并要求临时 ELF与 managed ELF SHA-256完全一致后才接受 map。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| Mailbox地址 | BSP符号或静默 `0x40040000` | 只允许正式 BSP符号 | 平台不匹配时编译失败 |
| Descriptor地址 | BSP符号或静默 `0x42000000` | 只允许正式 BSP符号 | 平台不匹配时编译失败 |
| App workspace | 旧 workspace | clean独立 workspace | 消除旧 object污染 |
| Managed sources | 未对本候选证明 | 16个 `.c`全部重编译 | 完整软件闭环 |
| USER_OBJS | 历史风险 | generated `USER_OBJS :=`空 | 无手工注入 object |
| Linker map | 无本候选 map | 与 managed ELF同对象/同顺序生成 | 可追溯 |
| UDP/运行行为 | 现有实现 | 未改 | 预期不变 |
| XSA / Platform / BSP | 旧平台 | timing-clean XSA新 BSP | 有意更新依赖 |
| Hardware test | 未执行 | 未执行 | `board_verified=0` |

## 5. 硬件接口一致性说明

新 `xparameters.h` 与 XSA确认：

- dynamic mailbox：`XPAR_AXI_GPIO_DYNAMIC_MAILBOX_BASEADDR = 0x40040000`；
- descriptor BRAM：`XPAR_AXI_BRAM_DYN_DESC_S_AXI_BASEADDR = 0x42000000U`；
- AXI register access继续使用 Xilinx `Xil_In32/Xil_Out32`，32-bit volatile MMIO语义不变；
- mailbox data/tri/status offsets未改，write/read方向和toggle协议未改；
- AXI address map unchanged。

AD9528访问仍为 PS SPI1/EMIO路径，`XPAR_PS7_SPI_1_DEVICE_ID`，slave-select `1`，forced slave-select，SPI mode 0（CPOL=0、CPHA=0），prescaler 64。新 BSP给出 SPI input clock `166666672 Hz`，因此配置 SCLK约 `2.604 MHz`。本阶段没有改变 AD9528 reset、serial-port、IO_UPDATE、calibration或readback流程，也没有更换 chip-select。

## 6. 功能等价性说明

Expected software behavior unchanged。

初始化顺序、外设选择、SPI寄存器序列、readback、delay、error handling、UDP命令、mailbox/coordinator和runtime planner行为均未改。唯一有意变化是构建期安全行为：BSP缺少正式 mailbox/descriptor符号时立即失败，不再静默使用 fallback。

该等价性基于源码范围审计和 clean build；Hardware test was not run。

## 7. 构建与测试验证

执行结果：

- clean platform/BSP：PASS；
- Vitis managed app create/import：PASS；
- managed source count：16；
- `USER_OBJS`：空；
- `make clean`：PASS；
- `make all`：PASS；
- compiler errors：0；
- application compiler warnings：0；
- link：PASS；
- map-only relink与 managed ELF SHA-256：一致；
- ELF/map旧 `vitis_bringup/laser_tx_system_top`路径引用：0。

ELF size：

| Section | Bytes |
|---|---:|
| text | 261673 |
| data | 3528 |
| bss | 3201088 |
| total | 3466289 |

生成物：

- `reports/runtime_rate_vitis/bringup/Debug/bringup.elf`
- `reports/runtime_rate_vitis/bringup/Debug/bringup.map`

Hardware test was not run.

## 8. XSA / Platform / BSP影响

XSA / Platform / BSP dependency changed intentionally。

固件只针对本候选 XSA新生成的 `runtime_rate_artifact_platform/standalone_ps7_cortexa9_0`。`xparameters.h`、driver configuration tables和 BSP libraries均来自该平台。linker script由新 managed app生成；DDR内存区域未手工修改。

## 9. 内存与启动风险说明

`.bss=3,201,088 bytes`，主要全局/static buffer规模较大，但仍按当前 DDR linker布局完成链接。linker script未改，heap/stack未在本阶段扩大。由于未上板，尚未确认 PS DDR初始化、cache/MMU和启动至 `main()`；首次运行必须通过 UART确认 `main`、lwIP和UDP server启动。

## 10. Artifact SHA-256

| Artifact | SHA-256 |
|---|---|
| bit | `F9623218BF4B69CB7E332B3A07437C37F23BC981BE40D3A1572F6054EF07C4FA` |
| LTX | `B12D23A5C8BFC0A2D9D22FD531CC2462B4439254FFEF30E29F28748AEBDD735B` |
| XSA | `D60E66F4EDBC7BC8AA05E304E839027AA8923054D9FE59B58DAEC26DB6FB5508` |
| ELF | `3BED156E1900BEB0A8BE45F50AB18DC56BE119DE7E3C221D9805E055425379EF` |
| map | `BF86593676135E742AF109E68D89960AFEB61FBE0D1328414AA3177DE0E23337` |
| routed DCP | `9B160945D2F3AE88B1643D1D1605F72C53AC11230DB8E436E0F8CCE0A161E1C8` |
| OOC DCP | `5ACD41821583902652BF85E3D1535B38543191F5724FE5F1CB2B1BC612AE13F1` |
| timing summary | `169348A5B8175E432CEF82CAD88352DD533299927E804C5A0E3C535F74278BB0` |
| xparameters.h | `63E9CB47B21E57B25D41410C4918F39C6B291B6BD0FF500E8126FB0FC38428B5` |

完整15项哈希、约束/Tcl哈希、timing、warning和地址记录见 `reports/ad9528_gt_rate_planner/artifact_build/release_artifact_manifest.json`。

## 11. 修改文件列表

| File | Change |
|---|---|
| `vitis_bringup/bringup/src/laser_hw.h` | 删除硬件应用 silent fallback，缺符号时报错 |
| `scripts/create_runtime_rate_artifact_vitis_app.tcl` | clean managed app创建/16源文件门控 |
| `scripts/generate_runtime_rate_linker_map.ps1` | 按 managed object顺序生成并校验 linker map |
| `scripts/generate_runtime_rate_release_manifest.py` | 生成 release/software manifest与SHA-256 |
| `reports/.../release_artifact_manifest.json` | artifact正式manifest |
| `reports/.../software_build_manifest.txt` | managed build摘要 |
| `docs/debug_reports/52_runtime_rate_firmware_artifact_closure_report.md` | 本报告 |

没有修改 RTL、BD、XDC、XCI、XPR、GT/MMCM profile、planner、mailbox协议、UDP协议或速率范围。bit/LTX/XSA/ELF/map/DCP未提交 Git。

## 12. 风险与后续建议

1. 当前 WNS只有 `+0.028 ns`，首次上板必须使用本 manifest 中的匹配 bit/LTX/ELF。
2. Project 1-840仍为13个唯一 DCP，虽已逐项哈希闭环，后续 Vivado版本升级应重新评估 managed BD flow。
3. 尚未验证 UART启动、UDP、AD9528、dynamic mailbox、descriptor BRAM和最大速率运行。
4. 尚未执行 BER、眼图、光口或长期稳定性测试。
5. 本候选只能标记为 artifact candidate，`board_verified=0`，不能命名为 release或board-verified。

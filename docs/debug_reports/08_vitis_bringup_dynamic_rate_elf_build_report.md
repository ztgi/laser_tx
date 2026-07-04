# Vitis bringup.elf 动态速率切换口径 build 报告

生成时间：2026-07-01  
工程目录：`D:/FPGA_Learn/laser_tx`

## 1. 本轮问题现象

`dynamic_500m_1000m` Vivado bit/LTX 已生成且 timing 通过。进入上板前，需要先确认 Vitis `bringup.elf` 已经从早期 dry-run `rate set` 口径切换到真实 500M↔1000M 动态切换请求口径。

本轮只处理 Vitis bringup app clean/build 与 ELF 字符串检查。

本轮未做：

```text
未修改 RTL；
未修改 BD；
未修改 XDC；
未重新跑 Vivado；
未重新生成 bit/LTX；
未导出 XSA；
未重建 platform/BSP；
未执行上板验证。
```

## 2. 当前已通过的层级

| 层级 | 结论 |
| --- | --- |
| Vivado dynamic bit/LTX | 前序已生成，本轮未重跑 |
| Vitis bringup app clean/build | 已通过 |
| ELF strings 口径检查 | 已通过 |
| 默认速率一致性 | dynamic bit 与 ELF 均为 500M 默认 |
| 上板验证 | 本轮未执行 |

## 3. 当前未通过 / 未验证的层级

```text
Hardware test was not run.
UDP rate set 500/1000 was not tested on board.
GTX/MMCM DRP real switch was not verified on board.
```

## 4. 根因假设

进入上板前必须避免以下风险：

```text
1. ELF 仍然包含旧 dry-run rate set 返回口径；
2. ELF 默认启动速率与 dynamic bit 默认状态不一致；
3. 用户下载 dynamic bit 后，软件仍按 static 1000M 或 dry-run 逻辑解释状态；
4. 上板失败时无法区分软件口径错误与硬件 DRP/lock/txusrclk2 问题。
```

因此本轮先做 clean/build 和 ELF strings 检查。

## 5. 本轮修改内容

本轮未修改源码，只重新生成 Vitis app build artifact：

| 文件 | 操作 | 说明 |
| --- | --- | --- |
| `vitis_bringup/bringup/Debug/bringup.elf` | clean/build 重新生成 | 目标 ELF |
| `vitis_bringup/bringup/Debug/bringup.elf.size` | 重新生成 | size 记录 |

源码未改动：

```text
vitis_bringup/bringup/src/*.c 未修改；
vitis_bringup/bringup/src/*.h 未修改；
RTL/BD/XDC 未修改。
```

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| bringup.elf 时间 | 2026-06-30 18:44:28 | 2026-07-01 12:00:11 | ELF 已重新生成 |
| bringup.elf 文件大小 | 903892 bytes | 905556 bytes | build artifact 更新 |
| `.text` | 未在本轮记录旧值 | 146767 bytes | 当前 ELF size |
| `.data` | 未在本轮记录旧值 | 3432 bytes | 当前 ELF size |
| `.bss` | 未在本轮记录旧值 | 3201088 bytes | 当前 ELF size |
| rate set dry-run 旧字符串 | 需确认 | `DRY_RUN_ONLY` / `RATE_SET_DRY_RUN` 未匹配 | 不再作为 ELF 主返回口径 |
| 真实 rate set 字符串 | 需确认 | `OK RATE_SET` / `ERROR RATE_SET_FAILED` 等存在 | 软件口径已切换 |
| 默认速率 | 需确认 | 500M | 与 dynamic bit reset 默认一致 |

## 7. 为什么这样修改 / 检查

本轮没有改代码，而是用 clean build 和 ELF strings 验证当前软件是否真正进入动态切换口径。

如果 ELF 中仍出现旧主返回口径：

```text
DRY_RUN_ONLY
RATE_SET_DRY_RUN
```

则说明上板前软件仍存在 dry-run 残留，不能进入动态切换验证。

本轮 strings 检查中上述旧字符串未匹配。

## 8. 硬件接口一致性说明

本轮未修改硬件接口：

```text
未修改 RTL；
未修改 BD；
未修改 XDC；
未修改 GT Wizard；
未修改 txusrclk2；
未修改 AD9528；
未做 GTX 动态速率范围扩展；
未改变 GPIO / BRAM / GT status 地址；
未改变 Profile0/Profile1 static 回退 bitstream。
```

当前软件仍依赖现有 `xparameters.h` / BSP include 路径：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/laser_tx_system_top/export/laser_tx_system_top/sw/laser_tx_system_top/standalone_ps7_cortexa9_0/bspinclude/include
```

本轮未重新导出 XSA、未重建 platform/BSP。

## 9. 构建验证记录

执行命令：

```bat
call "D:\Vitis\2022.2\settings64.bat"
cd /d D:\FPGA_Learn\laser_tx\vitis_bringup\bringup\Debug
make clean
make all
```

build 结果：

```text
bringup.elf generated successfully.
```

size：

```text
   text    data      bss      dec      hex filename
 146767    3432  3201088  3351287   3322f7 bringup.elf
```

ELF 路径：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf
```

ELF 文件大小：

```text
905556 bytes
```

## 10. ELF strings 检查记录

执行检查：

```bat
arm-none-eabi-strings bringup.elf | findstr /C:DRY_RUN_ONLY /C:RATE_SET_DRY_RUN
```

结果：

```text
无匹配输出。
```

说明：

```text
旧的 DRY_RUN_ONLY / RATE_SET_DRY_RUN 不再作为当前 ELF 主返回口径。
```

执行检查：

```bat
arm-none-eabi-strings bringup.elf | findstr /C:"OK RATE_SET" /C:"ERROR RATE_SET_FAILED" /C:already_current_rate /C:unsupported_rate /C:current_rate /C:rate_state /C:error_code
```

关键匹配：

```text
OK RATE_SET target=%lu already_current_rate=1 current_rate=%lu
OK RATE_SET target=%lu current_rate=%lu state=DONE gt_drp_written=%lu mmcm_drp_written=%lu
ERROR RATE_SET_FAILED target=%lu state=SOFTWARE_QUIESCE error_code=TX_QUIESCE_TIMEOUT current_rate=%lu
ERROR RATE_SET_FAILED target=%lu state=%s error_code=RATE_BUSY current_rate=%lu
ERROR RATE_SET_FAILED target=%lu state=PRECHECK error_code=GT_NOT_READY current_rate=%lu
ERROR RATE_SET_FAILED target=%lu state=%s error_code=TIMEOUT current_rate=%lu raw=0x%08lx
ERROR RATE_SET_FAILED target=%lu state=%s error_code=%s current_rate=%lu raw=0x%08lx
ERROR unsupported_rate target=%lu
OK RATE_STATUS mode=dynamic_500m_1000m current_rate=%lu current_rate_id=%lu rate_state=%s error_code=%s ...
```

结论：

```text
ELF 已包含真实 dynamic rate set 的成功、失败、already-current、unsupported-rate 和状态查询返回口径。
```

## 11. 默认速率确认

dynamic bit 默认启动速率来自 RTL reset：

```verilog
current_rate_id   <= RATE_ID_500M;
current_rate_mbps <= 16'd500;
```

对应文件：

```text
D:/FPGA_Learn/laser_tx/laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v
```

ELF 侧默认打印宏：

```c
#ifndef LASER_STATIC_RATE_MBPS
#define LASER_STATIC_RATE_MBPS 500U
#endif
```

对应文件：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/laser_udp_server.c
```

结论：

```text
当前 dynamic bit 默认速率 = 500M；
当前 bringup.elf 默认显示/假设速率 = 500M；
二者一致。
```

## 12. 当前分层结论

| 项目 | 结论 |
| --- | --- |
| Vitis app clean/build | 通过 |
| bringup.elf 生成 | 通过 |
| ELF strings 旧 dry-run 主口径 | 未匹配 |
| ELF strings 真实 rate set 口径 | 已匹配 |
| dynamic bit 默认速率 | 500M |
| ELF 默认速率 | 500M |
| RTL/BD/XDC 修改 | 本轮无 |
| Vivado build | 本轮未重跑 |
| XSA/platform/BSP | 本轮未更新 |
| 上板验证 | Hardware test was not run |

## 13. 风险说明

1. 本轮只证明 ELF build 和 strings 口径正确，不证明 GTX/MMCM DRP 实际上板切换成功。
2. 本轮未重建 BSP。如果后续重新导出 XSA 或 platform，必须重新 clean/build BSP 和 bringup app。
3. 当前 `.bss` 为约 3.2 MB，属于 lwIP/裸机 app 当前内存占用，需要继续确保 linker script 与 DDR 运行环境一致。
4. 上板时必须确保下载的是匹配的 dynamic bit/LTX，而不是旧 static bit/LTX。

## 14. 下一步建议

下一步可以进入最小上板验证：

```text
1. Program FPGA:
   D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
   D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx

2. Vitis/XSCT 下载:
   D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf

3. 先 READ_GT_STATUS / rate status，确认 current_rate=500。

4. 执行 rate set 1000，观察 OK RATE_SET 或 ERROR RATE_SET_FAILED。

5. 再执行 rate set 500，做 1000->500 回切。
```

若失败，优先记录：

```text
rate_state；
error_code；
current_rate；
gt_drp_written / mmcm_drp_written；
gt_drp_done / mmcm_drp_done；
gt_ready；
raw GT status。
```


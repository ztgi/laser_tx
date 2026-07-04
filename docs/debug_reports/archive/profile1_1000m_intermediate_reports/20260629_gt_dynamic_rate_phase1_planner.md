# GT 动态速率第一阶段：速率规划器与工程可行性核查报告

## 1. 本轮问题现象

当前工程已经完成固定 500 Mb/s Profile 0 的有效发送 case 上板 ILA 验证，UDP 控制层也已经从“基础通信”阶段推进到可维护的软件结构阶段。

但当前工程仍明确属于固定 Profile 0：

```text
fixed GT Profile 0
no GTX dynamic rate change
AD9528 dynamic : not configured in UDP mode
Runtime rate set : UNSUPPORTED_RUNTIME_RATE_CHANGE
```

本轮目标不是直接切换 GT 速率，而是先建立可复用的 dry-run 速率规划器，并核查当前 Vivado/Vitis 工程距离真实动态速率还缺哪些条件。

## 2. 当前已通过的层级

| 层级 | 当前状态 |
|---|---|
| 固定 Profile 0 有效发送 ILA | 已完成收口 |
| UDP/lwIP 基础通信 | 用户已确认已连上 |
| UDP 固定 Profile 0 控制层 | 已有 PING/READ/WRITE/APPLY/ENABLE 等命令 |
| AD9528 SPI 最小 readback 代码 | 已存在 |
| GT status GPIO | 已存在并可由软件读取 |

## 3. 当前未通过的层级

| 层级 | 当前状态 |
|---|---|
| 真实 GT DRP 写入 | 未实现 |
| 运行时 GTX line rate 切换 | 未实现 |
| AD9528 动态 clock-tree 配置 | 未实现 |
| QPLL/common DRP 访问路径 | 当前未暴露为可控接口 |
| 多速率 timing/clocking 验证 | 未执行 |
| 动态切换上板验证 | 未执行 |

## 4. 根因假设

不能直接实现 `rate set <Mbps>` 的根因不是 UDP 命令解析，而是硬件可控面还没有准备好：

1. GT channel DRP 端口在 XCI 中存在，但 wrapper 当前把 `drpen/drpwe/drpaddr/drpdi` tie-off；
2. QPLL/common DRP 未形成可由 PL/PS 访问的控制面；
3. AD9528 仅有 SPI readback 和占位 `apply_rate_profile()`，不能动态生成 MGTREFCLK；
4. TXUSRCLK/TXUSRCLK2 会随 line rate 变化，必须重新设计 clocking/reconfiguration 方案；
5. 缺少切换失败 rollback、lock/resetdone/ready 观察和恢复流程。

因此第一阶段只做 `gt_rate_plan()` 和 UDP dry-run 是合理边界。

## 5. 本轮修改内容

| 文件 | 修改内容 |
|---|---|
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/gt_rate_plan.h` | 新增速率规划器接口、枚举和 `GtRatePlan` 数据结构 |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/gt_rate_plan.c` | 新增典型速率查表、字符串转换和规划结果打印函数 |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/src/laser_udp_server.c` | 新增 `rate status` / `rate plan <Mbps>` dry-run 命令；`rate set` 返回不支持 |
| `D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/src/subdir.mk` | 将 `gt_rate_plan.c` 加入当前 Vitis app build |
| `D:/FPGA_Learn/laser_tx/docs/gt_dynamic_rate_phase1_plan.md` | 新增阶段性可行性核查报告 |
| `D:/FPGA_Learn/laser_tx/docs/udp_protocol.md` | 补充当前真实 UDP 命令和 rate dry-run 命令说明 |
| `D:/FPGA_Learn/laser_tx/docs/debug_reports/20260629_gt_dynamic_rate_phase1_planner.md` | 新增本轮调试/变更报告 |

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| 速率规划模块 | 无独立模块 | 新增 `gt_rate_plan.c/h` | 后续 `rate set` 可复用 |
| UDP rate status | 无 | 返回固定 Profile 0 / dynamic_hw not enabled | 明确当前硬件边界 |
| UDP rate plan | 无 | 支持 9 个典型点 dry-run | 可先验证协议和规划结果 |
| UDP rate set | 不存在 | 明确返回 `ERR RATE_SET_UNSUPPORTED_DRY_RUN` | 防止误以为已经切速率 |
| GT DRP | 未控制 | 未控制 | 保持硬件不变 |
| AD9528 动态配置 | 未实现 | 未实现 | 保持硬件不变 |
| Profile 0 | 固定 500 Mb/s | 完全保留 | 不破坏已验证回退路径 |
| UDP response buffer | 192 bytes | 256 bytes | 容纳 rate plan dry-run 回包 |
| Vitis build | 未包含规划器 | 包含 `gt_rate_plan.o` | ELF 包含新命令 |

## 7. 为什么这样修改

本轮改动验证三件事：

1. 软件协议层可以接受面向用户的 `rate plan <Mbps>`，而不是暴露内部 profile id；
2. 典型速率点可以先被规划和打印，非典型点可以明确拒绝；
3. `rate set` 在硬件未准备好之前不会假成功，避免把 dry-run 包装成动态速率实现。

如果 PC 发送 `rate plan 1000` 收到 `OK RATE_PLAN ... dry_run=1`，说明 UDP 命令解析和速率规划表工作。

如果 PC 发送 `rate plan 1375` 收到 `ERR RATE_PLAN_UNSUPPORTED target=1375`，说明 unsupported path 工作。

如果 PC 发送 `rate set 1000` 收到 `ERR RATE_SET_UNSUPPORTED_DRY_RUN`，说明本阶段没有误打开真实切速率入口。

## 8. 硬件接口一致性说明

本轮明确未修改：

```text
未修改 RTL
未修改 BD
未修改 XDC
未修改 GT Wizard
未修改 txusrclk2
未写 GT DRP
未配置 AD9528 动态 clock-tree
未做 GTX 动态改速率
未改变 Profile 0 固定发送链路
未改变 GPIO / BRAM / GT status 地址
```

软件仍使用当前 `xparameters.h` 中的 GPIO、BRAM、GT status、SPI、GEM 宏。本轮没有引入新的硬件寄存器地址，也没有改变 AXI address map。

## 9. 当前 Vivado / GT / AD9528 核查记录

### 9.1 GT Wizard / GTX

| 项目 | 结果 |
|---|---|
| line rate | 0.5 Gb/s |
| TXDATA 外部宽度 | 64 bit |
| TX_INT_DATAWIDTH | 32 |
| 编码 | None，无 8b/10b |
| PLL | 当前 Profile 0 使用 CPLL |
| TXOUT_DIV | 8 |
| TXUSRCLK | 15.625 MHz |
| TXUSRCLK2 | 7.8125 MHz |
| 关系 | `TXUSRCLK = 2 * TXUSRCLK2` |

### 9.2 DRP

XCI 中 `gt0_val_drp = true`，但当前 wrapper 中：

```text
gt0_drpaddr_in = 9'd0
gt0_drpdi_in   = 16'd0
gt0_drpen_in   = 1'b0
gt0_drpwe_in   = 1'b0
gt0_drpdo_out  = unused
gt0_drprdy_out = unused
```

因此当前不具备软件可控的 DRP 写入路径。

### 9.3 AD9528

`laser_ad9528_apply_rate_profile()` 当前返回 `XST_NO_FEATURE`，说明 AD9528 动态速率配置尚未具备。本轮没有改动该函数。

## 10. 新增 UDP dry-run 命令

```text
rate status
rate plan <Mbps>
```

示例返回：

```text
OK RATE_STATUS mode=fixed_profile0 dynamic_hw=not_enabled
OK RATE_PLAN target=1000 actual_kbps=1000000 ref=LOCAL_125 pll=CPLL txout_div=4 txusrclk2_hz=15625000 dry_run=1
ERR RATE_PLAN_UNSUPPORTED target=1375
ERR RATE_SET_UNSUPPORTED_DRY_RUN
```

## 11. 支持和暂不支持的速率

当前查表支持：

```text
500
1000
1250
2000
2500
3125
5000
6250
10000
```

暂不支持示例：

```text
1375
3680
9000
```

暂不支持的原因是：第一阶段没有 AD9528 可变参考时钟，也没有 CPLL/QPLL 全搜索算法和 DRP bitfield 验证。

## 12. 构建验证记录

执行命令：

```bat
call D:\Vitis\2022.2\settings64.bat
make -C D:\FPGA_Learn\laser_tx\vitis_bringup\bringup\Debug clean all
```

构建结果：

```text
Build passed
```

ELF size：

```text
text   = 143015
data   = 3432
bss    = 3201088
dec    = 3347535
hex    = 33144f
```

本轮未重新 Build BSP，因为 XSA/platform/BSP 没有改变。

## 13. 上板验证记录

Hardware test was not run.

本轮仅完成软件构建和工程结构核查，不声明 UDP rate dry-run 已上板通过，也不声明任何 GT 速率切换成功。

## 14. 当前分层结论

| 层级 | 结论 |
|---|---|
| PHY / UDP 基础链路 | 用户此前已确认连通；本轮未复测 |
| UDP `rate status` | 已编译进 ELF，待上板发送验证 |
| UDP `rate plan` | 已编译进 ELF，待上板发送验证 |
| UDP `rate set` | 明确不支持，仅返回 dry-run 错误 |
| GT 真实速率切换 | 未实现 |
| AD9528 动态配置 | 未实现 |
| Profile 0 固定发送链路 | 未修改 |

当前是否真正改变 GT 速率：否，本阶段仅规划。

## 15. 风险说明

1. `GtRatePlan` 中除 500 Mb/s Profile 0 以外的速率均为候选 dry-run 点，不是已验证 GT Wizard/DRP bitfield；
2. 156.25 MHz 参考路径和 AD9528 输出到 MGTREFCLK 的实际板级连接仍需确认；
3. QPLL/common DRP 尚未暴露，5G/6.25G/10G 不能据此直接切换；
4. TXUSRCLK/TXUSRCLK2 会随 line rate 改变，后续真实切换需要重新设计 clocking/reconfiguration；
5. 本轮只改 Vitis app，未重新生成 bitstream 和 XSA。

## 16. 下一步建议

建议下一阶段先做“CPLL + 本地 125 MHz REFCLK 的典型点真实切换可行性验证”，范围限定为：

1. 设计 PL DRP/reset 状态机；
2. 暴露最小 rate control/status 寄存器；
3. 先验证一个低风险典型点；
4. 切换前强制 disable TX，切换后等待 lock/resetdone/ready；
5. 再决定是否引入 AD9528 可变 REFCLK。

不建议下一阶段直接叠加 AD9528 动态 clock-tree、QPLL、多 profile、UDP `rate set` 全流程。

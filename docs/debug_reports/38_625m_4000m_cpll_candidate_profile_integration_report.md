# 625M / 4000M 125MHz CPLL 候选 Profile 主工程集成报告

## 1. 本阶段目标与边界

本阶段将两个已经由隔离 GT Wizard 参数包确认的 125MHz CPLL profile 接入主工程动态执行器：625Mbps 与 4000Mbps。两者均为 **candidate**，而非正式 supported profile。

本轮不改变现有 RATE_ID，不改变已验证 profile 的 GT/MMCM 参数，不改变 QPLL、REFCLK、AD9528、板级时钟架构、GPIO 位域、BD、XDC 或发送数据路径。普通 `rate set <Mbps>` 继续只接受 `board_verified=1` 的九档正式 profile。

参数来源为 [37 号隔离参数确认报告](37_625m_4000m_cpll_candidate_parameter_report.md) 与其中保存的 Wizard/generated HDL、用户时钟 helper 及 MMCM DRP 生成结果；本报告没有重新推导或猜测 DRP magic number。

## 2. RATE_ID 与候选状态

旧 ID `0..9` 原样保留。候选 ID 在当前最大值之后追加：

| Profile | RATE_ID | planner board_verified | 普通 `rate set` | 工程 bring-up |
| --- | ---: | ---: | --- | --- |
| 625M | 10 | 0 | 拒绝 | `rate candidate set 625` |
| 4000M | 11 | 0 | 拒绝 | `rate candidate set 4000` |

PL 的 `profile_supported` 包含两项，使显式工程请求可进入既有 executor；PS 的正式 `rate list` 与 `gt_rate_plan_exact()` 只遍历 `board_verified=1` 项。因此候选不会被普通命令静默选择，也不会加入正式 supported 列表。

## 3. 625M 参数核对表

| 项目 | 值 | 隔离 Wizard / 生成依据 |
| --- | --- | --- |
| MGT REFCLK / PLL | 125MHz / CPLL | 隔离 625M package |
| CPLL M / N1 / N2 | 1 / 4 / 5 | CPLL divider group `0x1003` |
| TXOUT_DIV / encoding | 8 / `3'b011` | generated GTXE2 channel |
| Line rate | 625Mbps | generated channel/XDC clock period |
| TXOUTCLK | 19.53125MHz | generated user clocking |
| TXUSRCLK / TXUSRCLK2 | 19.53125MHz / 9.765625MHz | generated user clocking |
| MMCM | DIVCLK=1, MULT=31, OUT0=62, OUT1=31, VCO=605.46875MHz | generated helper |
| MMCM sequence | sequence ID 10，15 笔 VPHY/XAPP888 格式写入 | 隔离生成脚本 |
| 初始频率窗口 | 9600..9950 / 约 1ms | 9,765,625Hz 目标计数 |

## 4. 4000M 参数核对表

| 项目 | 值 | 隔离 Wizard / 生成依据 |
| --- | --- | --- |
| MGT REFCLK / PLL | 125MHz / CPLL | 隔离 4000M package |
| CPLL M / N1 / N2 | 1 / 4 / 4 | CPLL divider group `0x1002` |
| TXOUT_DIV / encoding | 1 / `3'b000` | generated GTXE2 channel |
| Line rate | 4000Mbps | generated channel/XDC clock period |
| TXOUTCLK | 125MHz | generated user clocking |
| TXUSRCLK / TXUSRCLK2 | 125MHz / 62.5MHz | generated user clocking |
| MMCM | DIVCLK=1, MULT=5, OUT0=10, OUT1=5, VCO=625MHz | generated helper |
| MMCM sequence | sequence ID 11，15 笔 VPHY/XAPP888 格式写入 | 隔离生成脚本 |
| 初始频率窗口 | 61400..63600 / 约 1ms | 62,500,000Hz 目标计数 |

## 5. 软件执行接口

`rate plan 625` 与 `rate plan 4000` 可显示 candidate 参数，并返回 `verified=0`。`rate list` 仅显示正式九档 profile；普通 `rate set 625` / `rate set 4000` 返回 `ERROR RATE_SET_UNSUPPORTED`，不翻转 GPIO request toggle。

候选上板使用专用且显式的工程命令：

```text
rate candidate set 625
rate candidate set 4000
```

该接口复用现有安全 precheck、request toggle、DONE/current-rate 校验与 error-code 回读；它不修改 UDP 端口、GPIO 位域或 PL DRP 接口。候选命令只允许 `board_verified=0` 项，已验证 profile 不通过该入口执行。

## 6. 工程上板 bring-up 路径（待执行）

每档都必须单独完成，不能以另一档的成功代替：

1. Program 本轮匹配 bit/LTX，执行 `rst -processor` 并运行匹配 ELF。
2. 记录 `rate status`；执行 `rate list`，确认 625/4000 未列入正式 supported。
3. 执行 `rate plan <candidate>`，确认 `verified=0`；执行普通 `rate set <candidate>`，确认软件拒绝且不触发 GT/MMCM DRP。
4. 625M：`rate set 1000` → `rate candidate set 625` → `rate set 1000`。
5. 4000M：`rate set 2000` → `rate candidate set 4000` → `rate set 2000`。
6. 每次切入与回切均在 AXI/FCLK ILA 检查 GT/MMCM DRP done/error、CPLL lock、MMCM lock、TXRESETDONE、GT ready、TXUSRCLK2 频率窗口、`RATE_VERIFY_RATE` 与 `RATE_DONE`；保留 UDP 和 ILA 截图。
7. 两档均独立完成切入、频率验证、回切及 error-code 检查后，才允许在后续独立任务中将对应 `board_verified` 改为 1 并进入正式 `rate list`。

## 7. 构建与验证

已执行一次主工程 Vivado synthesis、implementation、write_bitstream、write_debug_probes 和报告导出。结果如下：

| 项目 | 结果 |
| --- | --- |
| `synth_1` | Complete，无 ERROR |
| `impl_1` | `write_bitstream Complete!` |
| Setup WNS / TNS | 7.029ns / 0.000ns |
| Hold WHS / THS | 0.032ns / 0.000ns |
| bit / LTX | 已生成于 `laser_tx.runs/impl_1/laser_tx_board_top.bit` 与同目录 `.ltx` |
| DRC | 0 Errors；`write_bitstream` 前检查为 5 Warnings，均需按既有 debug/IP 警告继续跟踪，不作为候选 profile 上板通过证据 |
| Debug core | `dbg_hub`、`ila_laser_axi_cfg`、`ila_laser_tx` 均仍为 implemented |
| 资源 | LUT 22,858（8.24%）、FF 21,661（3.90%）、BRAM Tile 61（8.08%）、DSP 0 |

已执行 Vitis `make clean && make all`。`bringup.elf` 链接成功，size 为 `.text=152335`、`.data=3432`、`.bss=3201088` bytes。XSA、Platform、BSP、AXI 地址与 GPIO 位域均未改变，因此没有重建 XSA/BSP。

主机 planner 单元测试脚本在本机缺少 host `gcc` 而未运行；这不影响 Vitis ARM 目标 clean build 已完成。`scripts/check_rate_profile_consistency.py` 已通过，验证 RTL/PS RATE_ID、profile 升序、候选 `board_verified=0`、频率窗口和 3000M exclusion。

## 8. 当前结论与边界

本次是两个已确认参数 profile 的主工程 candidate 集成，不是新增正式 supported rate。625M/4000M 尚未上板，尚未完成 MMCM DRP readback、频率计数、VERIFY_RATE、DONE 或回切验证。

本阶段不涉及 QPLL 参数、156.25MHz REFCLK、AD9528 动态输出、任意连续速率、第三候选档或外部光口/BER 验证。

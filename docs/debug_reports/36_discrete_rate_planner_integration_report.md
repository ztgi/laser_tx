# 多档离散速率规划器集成报告

## 1. 目标与边界

本阶段将九个已启用 profile 整理为 Vitis 统一 planner。PL RTL、GT/CPLL/QPLL/MMCM DRP、GPIO bitfield、AXI 地址、BD、XDC、ILA 和 profile 硬件参数均未修改。

## 2. 修改前结构

`gt_rate_plan.c` 有一张未带 rate_id/verified/counter-window 的表；`laser_udp_server.c` 另有 Mbps→rate_id if-chain、手写 `rate list` 字符串；`laser_gt.c` 另有 rate_id→Mbps switch。该分散结构会增加 profile 增删时的软件一致性风险。

## 3. 修改后结构

`GtRateProfile` 是唯一 Vitis 侧 profile 表，按 Mbps 升序保存 rate_id、PLL、125MHz refclk、TXUSRCLK2 预期、RTL 约 1ms counter window、CPLL DRP group、TXOUT_DIV、MMCM profile、QPLL/AD9528 标记和 `board_verified`。`laser_gt.c` 与 UDP 都通过该表查询。

| 规则 | 行为 |
|---|---|
| EXACT | 精确匹配 verified profile；`rate set` 才允许执行。 |
| NEAREST | 仅 `rate plan <Mbps> nearest`；只返回建议。 |
| UNSUPPORTED | 返回上下临近档和原因；不写 GPIO、不翻转 request toggle。 |

3000M 返回 `NO_LEGAL_VERIFIED_125M_CPLL_PROFILE`，不会自动选 3125M。

## 4. UDP 变化

- `rate list` 仍保留 `supported=...`，后附由表生成的 `profiles=rate:PLL:125M:verified:id`。
- `rate plan <Mbps>` 返回 EXACT 或 UNSUPPORTED。
- `rate plan <Mbps> nearest` 返回建议但不执行。
- `rate set <Mbps>` 使用 exact planner 的 `selected_rate_id`；UNSUPPORTED 时返回 `ERROR RATE_SET_UNSUPPORTED`，不调用 `laser_gpio_rate_request()`。
- 数值解析使用十进制 `strtoul`，检查负号、`errno`、尾字符和 `UINT32_MAX`，避免 `atoi` 的静默错误。

## 5. 一致性与测试

`scripts/check_rate_profile_consistency.py` 只读检查 RTL/Vitis RATE_ID、九档升序唯一性、10000M=QPLL、其余=CPLL 和 3000M 未入表。`vitis_bringup/bringup/tests/test_gt_rate_plan.c` 覆盖九个 EXACT、UNSUPPORTED 邻近边界及 NEAREST 规则；本机没有 host `gcc`，该 host test 未执行。

执行 Vitis clean build：

```text
call D:\Vitis\2022.2\settings64.bat
cd D:\FPGA_Learn\laser_tx\vitis_bringup\bringup\Debug
make clean && make all
```

结果：通过；ELF `bringup.elf` size 为 text=150559、data=3432、bss=3201088、dec=3355079。

## 6. 硬件接口与平台影响

AXI 地址、GPIO bitfield、rate_id 编码、UDP 端口和 PL executor 均未改变。XSA / Platform / BSP dependency unchanged；不需要重新导出 XSA 或运行 Vivado build。

## 7. 上板状态与边界

Hardware rate-switch regression was not run。本阶段仅完成 Vitis build；尚需验证 `rate list`、EXACT 500/10000、`rate plan 3000`、`rate plan 3000 nearest`、`rate set 3000` 不触发 PL request，以及 CPLL/QPLL 已验证路径不退化。

本阶段只能描述为“九档已验证固定 profile 的离散规划与安全执行接口”，不能描述为 0.5G～10G 任意连续速率可调。

## 8. 软件收口：blocked rate 与统一打印

`gt_rate_plan_exact()` 不再对 3000M 保留速率专用 if/else；已知 blocked 速率改由小型只读 `GtBlockedRate` 表查询。3000M 仍不进入正式 profile，仍返回 `NO_LEGAL_VERIFIED_125M_CPLL_PROFILE`；其它未支持值返回 `NO_VERIFIED_EXACT_PROFILE`。NEAREST 仍只给出建议，不能触发硬件切换。

启动 banner 已从“fixed 125MHz CPLL profiles only”修正为固定 verified 125MHz CPLL/QPLL profile 的选择、GT/MMCM 重配置、PLL/reset/lock 处理与 TXUSRCLK2 frequency verification。启动时的 profile 摘要和 UDP `rate list` 均遍历同一 `gt_rate_profile_table`，不再维护手写九档速率字符串。

`GT_RATE_PROFILE_COUNT` 改为 `sizeof(gt_rate_profile_table) / sizeof(gt_rate_profile_table[0])` 推导；`gt_rate_pll_source_name()` 对非法 enum 返回 `UNKNOWN_PLL`。当前 ARM GCC Vitis build 支持 designated initializer，profile 表已采用字段名初始化以减少字段错位风险。

`GT_RATE_PLAN_HOST_TEST` 为脱离 Xilinx BSP 的 host 编译保留 RATE_ID 宏副本；本轮未大规模移动公共头文件。`scripts/check_rate_profile_consistency.py` 会比较该正式软件 RATE_ID 与 RTL localparam，但 host 宏副本仍是需维护的低风险测试辅助结构。

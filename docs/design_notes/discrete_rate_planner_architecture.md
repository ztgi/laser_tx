# 多档离散速率规划器与安全执行接口

## 职责划分

规划器只在 PS/Vitis 侧处理用户输入和已验证 profile 元数据；PL executor 仍独占 GPIO request、CPLL/QPLL/GT/MMCM DRP、reset/lock/ready 和 VERIFY_RATE。UDP 不提供 DRP addr/data 写入能力。

```text
rate plan / rate set <Mbps>
        -> Vitis planner
        -> EXACT verified profile?
        -> GPIO rate_id + request toggle
        -> PL dynamic executor
        -> VERIFY_RATE
        -> current_rate update
```

`rate set` 仅接受 EXACT 且 `board_verified=1` 的 profile。`rate plan <Mbps> nearest` 只返回建议，绝不触发 GPIO 或硬件切换。

## 正式 profile

| Mbps | rate_id | PLL | REFCLK | TXUSRCLK2 | profile 状态 |
|---:|---:|---|---:|---:|---|
| 500 | 1 | CPLL | 125MHz | 7.8125MHz | verified |
| 1000 | 2 | CPLL | 125MHz | 15.625MHz | verified |
| 1250 | 4 | CPLL | 125MHz | 19.53125MHz | verified |
| 2000 | 3 | CPLL | 125MHz | 31.25MHz | verified |
| 2500 | 5 | CPLL | 125MHz | 39.0625MHz | verified |
| 3125 | 7 | CPLL | 125MHz | 48.828125MHz | verified |
| 5000 | 6 | CPLL | 125MHz | 78.125MHz | verified |
| 6250 | 8 | CPLL | 125MHz | 97.65625MHz | verified |
| 10000 | 9 | QPLL | 125MHz | 156.25MHz | verified |

3000M 不在 supported 表中：125MHz CPLL 的数学候选会落入不满足当前 GTX CPLL 输出范围/验证要求的组合，且没有 GT Wizard、实现和上板验证的 3000M profile。

## 规划结果

- `EXACT`：请求值精确匹配正式 verified profile，可由 `rate set` 执行。
- `NEAREST`：仅由 `rate plan <Mbps> nearest` 显式请求；选择绝对误差最小的 verified profile，误差相同取较低速率。
- `UNSUPPORTED`：无精确 profile；返回上下相邻已验证速率，但不返回可执行 rate_id。

普通 `rate set 3000` 必须拒绝，不会自动切换至 3125M。

## 新 profile 准入

新速率必须依次完成：PLL 合法组合搜索、GT Wizard 参数确认、GT/CPLL/QPLL 参数提取、MMCM/DRP sequence 生成、frequency window、RTL/Vitis rate_id 同步、implementation/timing、UDP/ILA 上板验证，随后才可标记 `board_verified` 并加入 supported 表。未完成者只能是 candidate、blocked 或 unsupported。

## 边界

本架构是九档固定 profile 的离散规划与切换接口，不是任意连续 Mbps 参数生成；不包含 AD9528 动态输出、156.25MHz MGT REFCLK 切换或新增 QPLL profile。

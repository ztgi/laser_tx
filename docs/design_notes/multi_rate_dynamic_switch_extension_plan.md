# 多速率动态切换扩展只读方案

> 本文档仅做后续方案分析，不修改 RTL、BD、XDC、Tcl、Vitis、ILA probe、DRP 参数表或 rate controller。当前阶段先完成 500M/1000M 双速率动态切换收口；本文只讨论未来如果要扩展多速率，应如何分阶段推进与验证。

## 1. 当前基线

当前已经收口的动态切换范围是 500M 与 1000M 两档速率：

- 500M -> 1000M：已有 ILA 代表性波形证明 DRP、reset release、MMCM lock、GT ready 链路闭环；
- 500M <-> 1000M：已有 UDP 往返循环截图证明当前测试次数内软件状态回到 `RATE_DONE`、`error_code=NONE`、`gt_ready=1`；
- 现阶段不声明任意速率动态切换完成；
- 现阶段不声明长期稳定性、外部光口闭环或示波器验证完成。

后续多速率扩展必须以这个双速率基线为起点，不能跳过基线验证直接扩展到宽范围动态调速。

## 2. 扩展目标与非目标

### 2.1 目标

后续如果要扩展多速率，建议目标定义为：

1. 支持有限集合的离散速率 profile，而不是任意实数速率；
2. 每个速率 profile 有明确的 GT/MMCM 参数、时钟频率、TXUSRCLK2 预期值和 reset/lock 超时预算；
3. 每一对相邻或常用速率切换路径都有独立 ILA/UDP 证据；
4. 软件命令层能清楚报告 `target_rate`、`current_rate`、`rate_state`、`error_code`、DRP written flags、`gt_ready`；
5. debug-only probe 仍保持只观察、不参与功能控制。

### 2.2 非目标

下列内容不应被默认包含在下一阶段：

- 任意速率动态切换；
- 连续可调 line rate；
- 自动搜索 GT/MMCM DRP 参数；
- 外部 AD9528 动态时钟树重配置；
- 光口闭环误码率验证；
- 示波器眼图/抖动验证；
- 任意 direct pattern 长度；
- FIFO / 预展开架构重构；
- 将 debug-only probe 变成功能控制路径。

## 3. 推荐扩展原则

多速率扩展建议遵循“先表格化、再状态机化、最后系统化验证”的原则。

### 3.1 速率 profile 表格化

每个速率 profile 至少需要定义：

| 字段 | 说明 |
|---|---|
| `rate_id` | 软件/RTL 可见的速率编号 |
| `rate_mbps` | 目标速率，例如 500、1000 |
| GT DRP 参数 | TXOUT_DIV、CPLL/QPLL 相关写值等 |
| MMCM DRP 参数 | 分频、倍频、相位、lock 相关写值 |
| 预期 `txusrclk2` | 用于 alive/frequency counter 校验 |
| reset hold cycles | DRP 后 reset 保持/释放预算 |
| lock timeout | MMCM/GT ready 等待超时 |
| 验证状态 | 未实现、已 build、已 ILA、已 UDP、已循环 |

表格化的好处是让“支持哪些速率”变成可审查清单，而不是散落在状态机分支和软件 magic number 中。

### 3.2 切换路径显式化

多速率不是只增加 N 个 profile，还要考虑 N×N 的切换路径。建议至少显式记录：

- A -> B 是否允许；
- 是否需要经过中间安全速率；
- 是否需要特殊 reset sequence；
- 是否需要特殊 CPLL/QPLL 处理；
- 是否要求重新初始化外部时钟；
- 当前路径是否已有 ILA/UDP 证据。

例如：

| Path | 允许状态 | 最低验证要求 |
|---|---|---|
| 500 -> 1000 | 已验证 | ILA + UDP |
| 1000 -> 500 | 当前有 UDP 状态证据，建议补 ILA | UDP + 反向 ILA |
| 500 -> 新速率 X | 未定义 | 先 static build，再 dynamic |
| 新速率 X -> 1000 | 未定义 | 独立路径验证 |

## 4. 建议阶段划分

### Phase 0：冻结 500M/1000M 基线

目标是保证当前双速率成果不会被后续扩展冲掉：

- 固化 500M/1000M 的报告、图片、bit/LTX 路径；
- 保存当前 rate controller reset sequence 结论；
- 记录当前 timing/QoR；
- 增加回归检查清单：`rate set 1000`、`rate set 500`、`rate status`、ILA 关键 probe。

### Phase 1：候选新速率静态验证

每新增一个速率，先做 static build/bring-up，而不是直接进入动态切换：

1. 独立 Vivado static profile；
2. timing 通过；
3. bit/LTX 匹配；
4. `txusrclk2` alive/frequency counter 符合预期；
5. GT ready 能恢复；
6. basic APPLY/ENABLE 发送链路可观察。

只有 static bring-up 通过后，才允许进入 dynamic profile 表。

### Phase 2：单向动态切换

对每个新速率，先选一个最小路径，例如：

```text
500M -> rate_X
```

验证重点：

- GT DRP attempted/done/error；
- MMCM DRP attempted/done/error；
- reset release 顺序；
- `txoutclk_alive_axi`；
- `tx_mmcm_locked_raw/sync`；
- `txresetdone_sync`；
- `gt_ready`；
- `current_rate` 更新；
- UDP `rate_state=RATE_DONE`、`error_code=NONE`。

### Phase 3：反向动态切换

单向通过后，再验证：

```text
rate_X -> 500M
rate_X -> 1000M
1000M -> rate_X
```

每条路径都应至少有 UDP 证据；关键路径应有 ILA 代表性波形。

### Phase 4：循环与异常保护

在有限路径均通过后，再做循环和异常保护：

- 多次循环；
- 非法 rate id；
- DRP timeout；
- MMCM lock timeout；
- GT ready timeout；
- busy 状态下重复请求；
- request toggle 抖动或连续命令。

## 5. Debug / ILA 观测建议

后续扩展多速率时，不建议一开始扩大 ILA 到不可控规模。建议分层：

### 5.1 常驻最小 probe

- `target_rate_mbps`；
- `current_rate_mbps`；
- `rate_state`；
- `rate_error_code`；
- `gt_drp_done/error`；
- `mmcm_drp_done/error`；
- `tx_mmcm_reset_rate`；
- `tx_mmcm_reset_wizard`；
- `tx_mmcm_reset`；
- `txoutclk_alive_axi`；
- `tx_mmcm_locked_raw/sync`；
- `txresetdone_sync`；
- `gt_ready`。

### 5.2 临时细节 probe

仅在定位某个新速率失败时打开：

- GT/MMCM DRP `addr` / `di` / `do` / `en` / `we` / `rdy`；
- DRP readback；
- reset hold counter；
- lock timeout counter；
- request/ack toggle；
- txusrclk2 frequency counter。

## 6. 软件/UDP 层扩展建议

软件层应避免只回显“OK”，建议保持状态可诊断：

- `rate plan <Mbps>`：只计算/显示将使用哪个 profile，不执行切换；
- `rate set <Mbps>`：执行切换；
- `rate status`：显示 current/target/id/state/error/ready/DRP flags；
- `rate list`：列出当前固化支持的 profile；
- `rate paths`：列出允许的动态切换路径。

这些是后续设计建议，不代表当前代码已经实现。

## 7. 验证证据模板

每个新速率或新路径至少应归档：

| 证据 | 内容 |
|---|---|
| static timing | WNS/TNS/failing endpoints |
| bit/LTX | 文件路径和生成时间 |
| UDP screenshot/log | `rate set` / `rate status` |
| ILA overview | state/current/target/error |
| ILA reset/lock | reset、TXOUTCLK、locked、ready |
| DRP detail | addr/di/do/en/we/rdy/done/error |
| 边界声明 | 只声明该路径，不扩大到其它路径 |

## 8. 风险清单

后续扩展多速率的主要风险：

1. profile 参数正确性风险：新速率 GT/MMCM 参数必须独立确认；
2. reset sequence 差异风险：不同速率可能需要不同 hold/timeout；
3. debug hub/ILA 资源风险：probe 过多可能影响实现和调试稳定性；
4. CDC 风险：rate request、status、frequency counter 均跨时钟域；
5. 软件状态一致性风险：`current_rate` 不能早于硬件 ready 更新；
6. 外部时钟风险：如果引入 AD9528 动态重配，系统边界会明显扩大；
7. 验证膨胀风险：N 个速率意味着 N×N 路径，不应默认全覆盖。

## 9. 建议结论

建议当前先冻结并提交 500M/1000M 双速率动态切换阶段成果。后续若扩展多速率，应先建立 profile 表、路径表和证据模板，再逐个新增 static profile 与 dynamic path。

在没有完成 profile 参数确认、static bring-up、单向/反向 ILA、UDP 循环和异常保护前，不应声明：

- 任意速率动态切换完成；
- 宽范围动态调速完成；
- 长期稳定性完成；
- 外部光口闭环完成；
- AD9528 动态时钟树完成。

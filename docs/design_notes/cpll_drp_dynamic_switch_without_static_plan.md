# 不新建 static 工程的 125MHz CPLL 参数动态切换路线

## 1. 文档目标

本文定义下一阶段 125MHz REFCLK + CPLL 速率扩展的实施路线。核心变化是：后续不再为每一个新的 125MHz CPLL 候选速率新建独立 static board 工程，也不复制主工程生成新的 static top / bit / LTX。下一阶段聚焦于补齐 CPLL 参数动态 DRP 能力，并在确认参数可追溯后直接进入 dynamic profile 集成。

当前已通过的 500M / 1000M / 2000M 三档 dynamic profile 证明了如下链路已经具备工程基础：

- UDP `rate set` / `rate status` 控制链路；
- PL rate controller profile table / executor；
- GTX TXOUT_DIV DRP；
- MMCM DRP；
- reset / lock / ready sequence；
- `VERIFY_RATE`；
- `current_rate` 只在硬件 ready 后更新；
- AXI/FCLK ILA 下的状态观测。

因此，后续新增 125MHz CPLL 速率时，真正缺口不是“再证明一个固定配置能综合实现”，而是“CPLL feedback/refclk divider 参数能否被安全、可回读、可恢复地动态写入”。

## 2. 为什么不再做 static board 工程

不再为 125MHz CPLL 新速率建立独立 static board 工程，原因如下：

1. 500M / 1000M / 2000M 已经完成 dynamic 初步验证，说明当前动态执行链路可用；
2. static 工程只能证明某个固定 GT/MMCM 配置可以实现和下载，不能证明 CPLL 参数 DRP 动态写入、readback、reset/relock 可以在运行时恢复；
3. 当前剩余候选速率的核心风险不在 static top，而在 CPLL DRP address / bitfield / reset-relock sequence；
4. 每个速率都复制 static 工程会增加工程维护成本，并把注意力从真正缺失的 CPLL DRP 能力上移开；
5. 当前目标不是扩大板级工程数量，而是在已有 dynamic executor 内加入 CPLL 参数变化能力。

因此，下一阶段不做：

- 新建完整 static board 工程；
- 复制主工程生成新的 static top；
- static synthesis / implementation / bitstream；
- static ILA；
- 把“static build 通过”作为新增 dynamic profile 的前置路线。

## 3. 不做 static 不等于跳过参数确认

不做 static 工程并不意味着可以直接把 CPLL 参数写进 RTL。恰恰相反，CPLL 参数确认必须更严格。下一阶段必须确认：

| 项目 | 必须确认的内容 |
|---|---|
| `CPLL_REFCLK_DIV` | DRP address、bitfield、合法值、readback mask/value |
| `CPLL_FBDIV_45` | DRP address、bitfield、合法值、readback mask/value |
| `CPLL_FBDIV` | DRP address、bitfield、合法值、readback mask/value |
| `TXOUT_DIV` | 继续沿用已验证 address/bitfield，并确认与新 CPLL 参数组合一致 |
| `CPLLLOCK` | raw/sync 观察路径、timeout 条件 |
| `CPLLRESET` | 何时 assert/release、与 GT reset 的关系 |
| `GTTXRESET` | CPLL relock 前后是否需要保持或释放 |
| `TXUSERRDY` | MMCM lock 与 GT ready 前后的释放时机 |
| `txresetdone` | reset sequence 结束条件 |
| `gt_ready` | 最终可用状态判断 |
| MMCM DRP 顺序 | CPLL 参数改变后，MMCM DRP 应在稳定 TXOUTCLK 条件下执行还是先写后等 lock |
| readback | 每个关键 DRP 字段必须有 mask/value，失败时不能更新 `current_rate` |

如果这些字段无法可靠确认，不能把新增 CPLL 参数 profile 加入 supported list。

## 4. 允许使用的参数来源

允许使用以下来源做 CPLL DRP 参数确认：

- 当前已有 GT Wizard generated HDL；
- 当前 500M / 1000M / 2000M dynamic 工程；
- 已有 2G static 提取结果；
- UG476 / Xilinx 官方 GT DRP 资料；
- 已有工程报告中的 DRP map；
- 轻量 reference / XCI 参数提取；
- 已有 `project_gtx` 搜索结果作为候选线索。

需要注意：`project_gtx` 搜索结果只能证明某个 line rate 在公式和候选参数上存在，不等价于当前 `laser_tx` 工程已经具备对应 CPLL DRP 动态写入能力。

## 5. 禁止使用的方式

下一阶段禁止：

- 新建完整 static board 工程；
- 跑 static synth / impl / bitstream；
- 生成 static LTX；
- 靠公式直接手写无法追溯的 magic number；
- 引入 QPLL；
- 引入 156.25MHz REFCLK；
- 引入 AD9528 动态输出；
- 修改 `laser_tx_core`；
- 修改 `pattern_tx_engine`；
- 把未确认的 CPLL 参数加入 `rate list` / `rate set` supported list。

## 6. 下一步执行顺序

### Step 1：CPLL DRP read-only 确认

先只读确认以下字段：

- `CPLL_REFCLK_DIV`；
- `CPLL_FBDIV_45`；
- `CPLL_FBDIV`；
- `TXOUT_DIV`；
- `CPLLLOCK`；
- `CPLLRESET`；
- `GTTXRESET`；
- `TXUSERRDY`；
- `txresetdone`；
- `gt_ready`。

输出文档：

```text
docs/design_notes/cpll_drp_address_bitfield_confirmation.md
```

如果 CPLL DRP address / bitfield / readback 无法确认，立即停止，不继续写 RTL。

### Step 2：选择一个 CPLL 参数变化的代表速率

优先选择 1.25G 或 2.5G 作为第一个 CPLL 参数变化代表 profile。选择原则：

- 仍使用 125MHz REFCLK；
- 仍使用 CPLL；
- 不需要 QPLL；
- 不需要 AD9528；
- 不需要 156.25MHz REFCLK；
- 参数来源可追溯；
- TXUSRCLK2 不要高到显著增加 `laser_tx_core` timing 风险。

### Step 3：CPLL DRP 确认后再修改 dynamic profile

只有在 CPLL DRP 参数确认通过后，才允许修改：

- dynamic rate controller；
- profile table；
- CPLL DRP sequence；
- MMCM DRP sequence；
- Vitis `rate list` / `rate plan` / `rate set`；
- 报告和 bring-up 文档。

仍然不允许修改：

- AD9528；
- 156.25MHz REFCLK；
- QPLL；
- GT refclk switching；
- `laser_tx_core`；
- `pattern_tx_engine`；
- static 工程。

### Step 4：上板验证

生成 dynamic bit/LTX 后，按以下流程验证：

```text
Program dynamic bit/LTX
rst -processor
run ELF
UDP PING
rate list
rate plan <new_rate>
rate set <new_rate>
rate status
rate set 1000
rate status
rate set <new_rate>
rate status
```

AXI/FCLK ILA 重点观察：

- `rate_state`；
- `error_code`；
- `target_rate_mbps`；
- `current_rate_mbps`；
- CPLL reset / lock；
- GT DRP `addr/di/do/en/we/rdy`；
- GT DRP readback；
- MMCM DRP `addr/di/do/en/we/rdy`；
- `tx_mmcm_reset`；
- `txoutclk_alive_axi`；
- `txusrclk2_alive_axi`；
- `txusrclk2_freq_counter_axi`；
- `tx_mmcm_locked_raw/sync`；
- `txresetdone_sync`；
- `gt_ready`。

### Step 5：报告边界

报告中必须明确：

- 本阶段不是 static profile 验证；
- 不是 QPLL；
- 不是 156.25MHz REFCLK；
- 不是 AD9528；
- 不是任意速率；
- 不是宽范围连续调速；
- 只是尝试在 125MHz REFCLK + CPLL 条件下，把 CPLL 参数动态 DRP 能力加入现有 dynamic executor。

如果 CPLL DRP 确认失败，结论应写为：

```text
当前不具备安全加入新增 CPLL 参数 profile 的依据，因此保持 500M/1000M/2000M 为 supported profile。
```

如果 CPLL DRP 确认成功并完成上板，结论应写为：

```text
新增一个 125MHz CPLL 参数变化 profile 的 dynamic 切换验证通过。
```

## 7. 当前推荐

下一步最合适的动作不是新建 static 工程，而是生成：

```text
docs/design_notes/cpll_drp_address_bitfield_confirmation.md
```

该文档需要把 CPLL 参数 DRP 的 address、bitfield、mask/value、reset/relock sequence 和 readback 路径讲清楚。只有这一步完成后，才进入第一个 CPLL 参数变化 profile 的 dynamic RTL/Vitis 集成。

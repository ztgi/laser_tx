# 625M / 4000M 125MHz CPLL Profile 上板验证与正式支持收口报告

## 1. 目标与结论

本报告收口 625Mbps 与 4000Mbps 两个固定 125MHz REFCLK + CPLL profile。两档在此前以工程 candidate 接口完成首次上板切入；本轮代码审查确认 candidate 请求没有绕过既有动态执行器、lock/ready 检查或 `VERIFY_RATE`，因此两档提升为正式离散 supported rate。

当前正式列表按 Mbps 升序为：

```text
500, 625, 1000, 1250, 2000, 2500, 3125, 4000, 5000, 6250, 10000
```

625M 和 4000M 固定 125MHz CPLL profile 已完成初步上板验证，并加入正式离散 supported rate 列表。

## 2. 参数来源与最终核对

GT CPLL、TXOUT_DIV、user clocking 与 MMCM DRP 数据来自已提交的隔离 Wizard 参数确认包和当前 RTL；没有在本轮重新推导或手写 DRP magic number。

| 项目 | 625M | 4000M |
| --- | --- | --- |
| RATE_ID | 10 | 11 |
| REFCLK / PLL | 125MHz / CPLL | 125MHz / CPLL |
| CPLL M / N1 / N2 | 1 / 4 / 5 | 1 / 4 / 4 |
| CPLL DRP value | `0x1003` | `0x1002` |
| TXOUT_DIV / encoding | 8 / `3'b011` | 1 / `3'b000` |
| MMCM profile ID | 10 | 11 |
| MMCM 关键参数 | DIVCLK=1, MULT=31, OUT0=62, OUT1=31 | DIVCLK=1, MULT=5, OUT0=10, OUT1=5 |
| TXUSRCLK2 | 9.765625MHz | 62.5MHz |
| 约 1ms counter 中心值 | 约 9766 | 约 62500 |
| frequency window | 9600..9950 | 61400..63600 |

## 3. candidate 路径与正式 executor 一致性检查

代码审查结论如下：

1. 原 `rate candidate set <Mbps>` 与普通 `rate set <Mbps>` 均在完成 planner 选择后调用同一个 `laser_gpio_rate_request()`，通过同一 GPIO rate ID / request-toggle 将请求发往 PL。
2. 两类请求均调用 `laser_rate_wait_done_or_error()`；UDP 成功条件为 `RATE_DONE`、`current_rate_id == requested_rate_id`、无 `rate_error`、且 `error_code == NONE`。
3. PL 根据同一 `target_rate_id` 装载 CPLL、TXOUT_DIV、MMCM profile 和 frequency window，随后经过 GT DRP、MMCM DRP、MMCM reset release、CPLL/MMCM lock、`txresetdone_sync`、`gt_ready_ctrl` 与 `RATE_VERIFY_RATE`。
4. `RATE_VERIFY_RATE` 会先检查 `txusrclk2_alive_axi`，再比较 `txusrclk2_freq_counter_axi` 与 target window；仅成功后才更新 `current_rate_id`、`current_rate_mbps`、`active_pll_type` 与 `active_cpll_drp_value`，并进入 `RATE_DONE`。
5. CPLL DRP readback 成功时更新 `programmed_cpll_drp_value`；这与 last-good `active_cpll_drp_value` 的语义仍保持区分。

因此，candidate 路径没有绕过 GT/MMCM DRP、CPLL/MMCM lock、TXRESETDONE、GT ready、frequency VERIFY 或 current-rate 提交规则。

## 4. 已取得的上板证据

本轮收到的 ILA/UDP 观察记录表明：

- 500M 请求 625M 时，`target_rate` 先变为 625，`current_rate` 在 VERIFY 前保持 500；状态机进入 `RATE_ASSERT_RESET`，GT TX reset、TXUSERRDY block、MMCM reset 按既有流程动作。
- 该路径出现 GT DRP attempted/done、MMCM DRP attempted/done，随后进入 MMCM reset release / lock 等待流程。
- DRP detail ILA 已观察到 CPLL/GT DRP、625M CPLL divider、MMCM DRP address/data/EN/WE/RDY，且 GT/MMCM DRP 未报告 error。
- UDP 已返回 `rate candidate set 625`：`current_rate=625 state=DONE`；以及 `rate candidate set 4000`：`current_rate=4000 state=DONE`。

上述信息是用户提供的已观察上板证据。本仓库当前未保存对应 625M/4000M 截图文件，因此本报告不编造 Markdown 图片路径。

## 5. 回切证据边界

已确认的记录覆盖 500M → 625M DONE 及后续切入 4000M DONE。仓库与本轮输入中没有发现 `4000M -> 1000M` 的 UDP 响应或 ILA DONE 截图；只有 `rate set 1000` 的发送动作不足以证明回切完成。

因此：**4000M → 1000M 的最终回切证据等待补充。** 该缺口不改变本轮对两档切入和 shared executor 的代码收口结论，但不得写成该特定回切已完成。

## 6. 正式软件接口

625M/4000M 已设为 `board_verified=1`：

- `rate list` 自动从统一 profile table 输出两档；
- `rate plan 625` 与 `rate plan 4000` 返回 `EXACT`；
- 普通 `rate set 625` / `rate set 4000` 走唯一正式 planner 和唯一 PL executor；
- 原仅用于两档 bring-up 的 `rate candidate set` 命令已移除；未保留第二套 Mbps-to-rate-ID、DRP 或完成判定逻辑；
- 3000M 保持 `UNSUPPORTED`，不会写 GPIO request 或触发 PL 切换。

## 7. 构建、平台与回归

本轮只修改 Vitis/planner/profile metadata、UDP 文本接口、测试与文档；RTL、MMCM sequence、GT 参数、BD、XDC、AXI 地址、GPIO 位域均未修改。因此不需要重新运行 Vivado synthesis/implementation；沿用候选集成阶段已生成的匹配 bit/LTX。`git diff --name-only` 已确认无 RTL 文件变化。

已执行 Vitis `make clean && make all`，ARM target 编译和链接通过；`bringup.elf` size 为 `.text=151095`、`.data=3432`、`.bss=3201088` bytes。XSA / Platform / BSP dependency unchanged。

需要执行 Vitis clean build。正式上板回归清单为：

```text
rate list
rate plan 625
rate plan 4000
rate set 500
rate set 625
rate status
rate set 4000
rate status
rate set 1000
rate status
rate set 3000
rate status
```

应分别保存 625M/4000M 的稳态 frequency counter、各次 DONE/error=NONE、以及 4000M → 1000M 回切 DONE 的 UDP/ILA 证据。`rate set 3000` 必须被软件拒绝，且拒绝后 current rate 仍为 1000M。该“正式普通 rate set ELF”回归尚未在本轮执行。

## 8. 未验证边界

本报告不声明任意速率动态调节、76 个候选全部支持、AD9528 动态时钟、156.25MHz REFCLK 动态切换、示波器眼图、BER、外部光口质量或长期循环稳定性已通过。

# 现有动态 rate-switch 控制链路鲁棒性修复报告

## 1. 本阶段目标

本阶段目标是在不增加新速率、不启用 10G/QPLL profile、不修改 GT/MMCM/CPLL profile 参数的前提下，修复现有 CPLL dynamic rate-switch 控制链路中的三个鲁棒性问题：

1. Vitis 侧不能把上一轮残留的 `RATE_DONE` 误判为本轮 `rate set` 成功；
2. PL rate controller 正在切换时，新的 request toggle 不能覆盖当前 transaction 的 target profile 参数；
3. CPLL DRP 已经写入硬件、但后续 MMCM lock / GT ready / VERIFY_RATE 失败时，需要区分“最后验证通过的 active CPLL”和“最近实际写入硬件的 programmed CPLL”。

本阶段不是 10G/QPLL dynamic profile 集成，也不是宽范围任意速率控制。

## 2. 修改前的三个风险

### 2.1 Vitis 旧 RATE_DONE 误判

修改前，Vitis `rate set` 等待逻辑主要观察 `rate_state == RATE_DONE`。如果上一轮切换已经处于 DONE，而新的 request 尚未被 PL 接收或尚未完成，软件存在把旧 DONE 当作本轮成功的风险。

### 2.2 PL 忙时 request 覆盖 target

修改前，RTL 中 `request_event` 出现时会直接装载新的 `target_rate_id`、`target_rate_mbps`、`target_cpll_drp_value`、`target_txout_div`、频率窗口和 MMCM profile。若此时状态机正在 `PROGRAM_GT_DRP`、`WAIT_LOCK`、`VERIFY_RATE` 等阶段，新的 request 可能覆盖当前正在执行的 transaction 参数。

### 2.3 active CPLL 与实际 programmed CPLL 混淆

修改前，`active_cpll_drp_value` 表示最后一次通过 `VERIFY_RATE` 的 last-good CPLL profile，并被用来判断下一次是否需要执行 CPLL DRP。

风险场景是：

```text
last-good active CPLL = 0x1002
请求切换到 CPLL = 0x1003
CPLL DRP write + readback 已经成功
后续 MMCM lock / GT ready / VERIFY_RATE 失败
```

此时 last-good active 仍应保持 0x1002，但硬件 CPLL 可能已经实际停在 0x1003。下一次请求如果仍只比较 target 与 active，就可能漏掉必要的 CPLL restore。

## 3. 修改前实际代码位置

| 项目 | 文件 | 实际位置 / 函数 |
|---|---|---|
| UDP `rate set` 入口 | `vitis_bringup/bringup/src/laser_udp_server.c` | `handle_rate_command()` 的 `SET` 分支 |
| Mbps 到 rate_id 转换 | `vitis_bringup/bringup/src/laser_udp_server.c` | `laser_rate_id_from_mbps()` |
| PS->PL rate request | `vitis_bringup/bringup/src/laser_gpio.c` | `laser_gpio_rate_request()` |
| 等待 DONE/ERROR | `vitis_bringup/bringup/src/laser_udp_server.c` | `laser_rate_wait_done_or_error()` |
| GT_NOT_READY / RATE_BUSY precheck | `vitis_bringup/bringup/src/laser_udp_server.c` | `handle_rate_command()` |
| UDP OK RATE_SET 判断 | `vitis_bringup/bringup/src/laser_udp_server.c` | `handle_rate_command()` 最终响应生成前 |
| RTL request_event | `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | `request_event = gpio_ctrl[17] ^ rate_req_toggle_d` |
| target 参数装载 | 同上 | `if (request_event ...) begin` |
| active CPLL 定义/更新 | 同上 | `active_cpll_drp_value`，仅 `RATE_VERIFY_RATE` 成功后更新 |
| CPLL DRP write/readback | 同上 | `RATE_PROGRAM_GT_DRP` 内 `GT_STEP_*_CPLL*` |
| RATE_DONE / RATE_ERROR 行为 | 同上 | `RATE_VERIFY_RATE` 成功分支与 `set_error()` task |

## 4. Vitis 旧 DONE 修复

### 4.1 等待条件修改

修改后，`laser_rate_wait_done_or_error()` 接收预期目标 `expected_rate_id`：

```c
static int laser_rate_wait_done_or_error(
    uint32_t expected_rate_id,
    uint32_t *final_status);
```

成功条件变为同时满足：

```text
rate_state == RATE_DONE
current_rate_id == expected_rate_id
rate_error == 0
error_code == NONE
```

错误条件仍优先识别：

```text
rate_error == 1
或 rate_state == RATE_ERROR
或 error_code != NONE
```

等待超时后，软件会再读一次最终状态，并在 UDP 错误响应中返回最终 `state/current/target/error_code`，不会把 timeout 写成成功。

### 4.2 same-rate 请求处理

修改后，如果请求速率已经是当前生效速率，并且硬件状态满足：

```text
current_rate_id == requested_rate_id
rate_state == RATE_DONE
rate_error == 0
error_code == NONE
gt_ready == 1
```

则按“目标速率已经生效”直接返回成功，不再依靠旧 DONE 假装完成一轮新的切换。这是低风险策略，因为相同速率下不需要重复 DRP；若后续需要强制重新执行同速率 DRP，应另行定义 request acknowledge 或 transaction id。

### 4.3 ERROR 状态恢复策略

修改后，正常非 ERROR 状态下 `GT_NOT_READY` 仍阻止新切换；但如果 PL 已经处于 `RATE_ERROR`，软件允许用户再次发送有效 `rate set` 尝试恢复：

```text
if (!gt_ready && rate_state != RATE_ERROR) {
    return GT_NOT_READY;
}
```

`RATE_BUSY` 仍然不允许新 request。

### 4.4 precheck 状态重读

修改后，软件先等待 TX idle，再重新读取 `gt_status`，再做 `RATE_BUSY` / `GT_NOT_READY` / `RATE_ERROR` / `current_rate` 判断，避免使用 quiesce 前的旧状态。

## 5. RTL busy request guard

### 5.1 新增接收条件

RTL 新增：

```verilog
wire can_accept_rate_request =
    (rate_state == RATE_IDLE) ||
    (rate_state == RATE_DONE) ||
    (rate_state == RATE_ERROR);
```

只有：

```verilog
request_event && can_accept_rate_request
```

时才装载新的 target profile。

### 5.2 忙状态 toggle 处理

`rate_req_toggle_d <= gpio_ctrl[17]` 仍每个 `clk` 周期更新。因此忙状态下出现的 request toggle 会被同步/消费，但不会装载 target，也不会在状态机回到 DONE/IDLE 后被重复识别为新事件。

本阶段没有加入 FIFO、pending request 队列或第二套 target profile。软件侧仍负责正常发送前 precheck，RTL guard 作为最后一道保护。

## 6. active 与 programmed CPLL 状态语义

### 6.1 新增 programmed CPLL 状态

RTL 新增：

```verilog
reg [15:0] programmed_cpll_drp_value;
reg        programmed_cpll_drp_valid;
```

语义区分如下：

| 状态 | 含义 | 更新时机 |
|---|---|---|
| `active_cpll_drp_value` | 最后一次通过 `VERIFY_RATE` 的 last-good CPLL profile | 仅 `VERIFY_RATE` 成功后更新 |
| `programmed_cpll_drp_value` | 最近一次 CPLL DRP write + readback 成功后，实际写入硬件的 CPLL value | CPLL DRP readback/mask check 成功后更新 |

### 6.2 CPLL DRP required 判断

修改后：

```verilog
cpll_drp_required =
    !programmed_cpll_drp_valid ||
    (target_cpll_drp_value != programmed_cpll_drp_value);
```

target profile 装载时，`target_gt_drp_seq_id` 也基于 `programmed_cpll_drp_value` 决定是否执行 `GT_DRP_SEQ_CPLL_TXOUT_DIV`。

这样可以覆盖：

```text
1000 -> 1250：programmed 0x1002，target 0x1003，执行 CPLL DRP
1250 -> 1000：programmed 0x1003，target 0x1002，执行 CPLL DRP restore
同 CPLL 参数组内切换：programmed 与 target 相同，只写 TXOUT_DIV/MMCM
```

### 6.3 programmed valid 的处理

当 CPLL DRP readback 与目标 mask/value 匹配时：

```verilog
programmed_cpll_drp_value <= target_cpll_drp_value;
programmed_cpll_drp_valid <= 1'b1;
```

如果 CPLL DRP read、write、readback timeout 或 readback mismatch：

```verilog
programmed_cpll_drp_valid <= 1'b0;
```

这样下一次合法切换会强制重新写完整 CPLL 配置，不会在 readback 未确认时猜测硬件状态。

### 6.4 reset 初始语义

本轮采用保守 reset 语义：

```text
programmed_cpll_drp_valid = 0
```

也就是说，rate controller reset 后不声称硬件 CPLL DRP 寄存器已经恢复为某个软件默认值。第一次动态切换会重新执行 CPLL write/readback，确保 programmed 状态重新建立。

`active_cpll_drp_value` 仍初始化为当前 last-good 默认 profile 的 0x1002，用于软件可见 current-rate 语义。

## 7. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| Vitis DONE 判断 | 只要看到 `RATE_DONE` 存在误判风险 | 必须 `RATE_DONE + current_rate_id 匹配 + no error` | 避免旧 DONE 被当作本轮成功 |
| Same-rate 处理 | 可能依赖旧 DONE | DONE/ready/error-free 时直接视为已生效 | 明确语义，减少无意义 DRP |
| ERROR 恢复 | `gt_ready=0` 可能永久阻止恢复请求 | `RATE_ERROR` 下允许新 `rate set` 尝试恢复 | 保留恢复入口 |
| Precheck 状态 | 可能使用 quiesce 前旧状态 | TX idle 后重新读取状态 | 降低 stale status 风险 |
| PL request 装载 | 任意状态 request_event 都可覆盖 target | 仅 IDLE/DONE/ERROR 可装载 | 防止切换中 target 被覆盖 |
| Toggle 处理 | 忙时 toggle 可能破坏 transaction | 忙时 toggle 被消费但不装载 | 不引入 FIFO，保持接口不变 |
| CPLL 状态 | active 同时承担 last-good 和实际写入判断 | active/programmed 分离 | 修正失败路径 restore 判断 |
| CPLL DRP required | target vs active | target vs programmed 或 programmed invalid | 覆盖 DRP 成功但 VERIFY 失败场景 |
| pipeline/latency | 无新增 datapath pipeline | 无新增 datapath pipeline | 不影响 laser_tx_core 数据路径 |
| 外部接口 | 不变 | 不变 | UDP/GPIO/AXI bitfield 不变 |

## 8. 功能等价性说明

本轮没有修改：

- supported rate list；
- UDP 命令格式；
- GPIO bitfield；
- AXI 地址；
- GT/MMCM/CPLL profile 参数；
- GT Wizard XCI；
- BD；
- XDC；
- ILA probe 连接；
- `laser_tx_core` 数据路径；
- `pattern_tx_engine`。

对现有 CPLL profiles 的正常成功路径，目标行为保持一致：`current_rate` 仍只在 `VERIFY_RATE` 成功后更新；失败时保持 last-good current rate。

行为变化是有意的控制鲁棒性增强：

1. 软件不再把旧 DONE 当作新 request 成功；
2. PL 忙时不再允许新 request 覆盖当前 target；
3. CPLL restore 判断基于实际 programmed CPLL，而不是 last-good active CPLL。

上述结论基于代码结构检查、Vivado build 和 Vitis build；busy-request 硬件行为和 failure-path CPLL 状态语义尚未通过故障注入上板验证。

## 9. 构建与测试验证

### 9.1 Vitis build

执行目录：

```text
D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug
```

执行命令：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && make clean && make all"
```

结果：

```text
bringup.elf build passed
text = 148855
data = 3432
bss  = 3201088
dec  = 3353375
```

### 9.2 Vivado build

执行命令：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source scripts\run_qpll_wrapper_architecture_project_flow.tcl"
```

结果：

```text
synth_1_STATUS = synth_design Complete!
impl_1_STATUS  = write_bitstream Complete!
impl_1_first_ERROR =
```

生成本地 bit/LTX：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

脚本也复制了 artifacts 到：

```text
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/artifacts/
```

这些 bit/LTX/artifacts 均为本地生成物，不纳入 Git 提交。

### 9.3 Debug core report

报告路径：

```text
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/debug_cores_qpll_wrapper_architecture.rpt
```

确认：

```text
dbg_hub/clk = gt_ctrl_clk
ila_laser_axi_cfg/clk = u_system_wrapper/system_i/gt_ctrl_clk
ila_laser_tx 存在
```

本轮没有新增或重连 ILA probe。

### 9.4 Hardware test

```text
Hardware CPLL regression was not run.
```

因此本报告不能声明上板回归通过，也不能声明所有错误恢复路径已经上板验证。

## 10. QoR / timing 对比

本轮没有保留修改前后两份完整 QoR 对照，因此只记录修改后实现结果。

| Metric | After | Interpretation |
|---|---:|---|
| Setup WNS | 7.029 ns | timing met |
| Setup TNS | 0.000 ns | no setup failing endpoint |
| Hold WHS | 0.054 ns | hold met |
| Hold THS | 0.000 ns | no hold failing endpoint |
| Failing endpoints | 0 | no reported timing failure |

Timing/QoR result is confirmed for this build only. Timing 通过只说明当前实现满足已约束时序，不等价于长期硬件稳定性或上板功能通过。

## 11. 修改文件列表

| 文件 | 修改内容 |
|---|---|
| `vitis_bringup/bringup/src/laser_udp_server.c` | rate set 等待条件、same-rate 处理、ERROR 恢复 precheck、最终 OK 前 current_rate 匹配检查 |
| `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | busy request guard、programmed CPLL 状态跟踪、CPLL DRP required 判断修复 |
| `docs/debug_reports/33_rate_switch_control_hardening_report.md` | 本阶段工程调试报告 |

## 12. 未验证边界

尚未执行：

- UDP 上板完整 CPLL profile 回归；
- `1000 -> 1250 -> 1000` 修复后再回归；
- `5000 -> 1000`、`6250 -> 500` 等跨 CPLL 参数组路径上板回归；
- RATE_BUSY 状态下第二 request 的板级压力测试；
- DRP 成功但后续 VERIFY 故障注入测试；
- 外部光口质量、BER、长期稳定性测试。

因此不能声明所有错误恢复路径均已上板验证。

## 13. 下一阶段建议

建议下一阶段单独做示波器调试口任务，不与本次控制逻辑修复混在一起。随后再做上板回归：

```text
rate set 500
rate set 1000
rate set 1250
rate set 1000
rate set 2000
rate set 2500
rate set 5000
rate set 6250
rate set 3125
rate set 500
```

重点补充：

- 同一速率重复 `rate set`；
- ERROR 状态后的恢复请求；
- RATE_BUSY 状态下第二次 request；
- CPLL DRP 成功但 VERIFY 失败后的下一次 restore 行为。

## 14. 当前边界声明

本阶段是现有 CPLL dynamic rate-switch 控制链路的鲁棒性修复，不是系统架构重构，也不是 10G/QPLL profile 集成。

当前不能声明：

- 10G 已支持；
- QPLL dynamic switching 已通过；
- 任意速率动态调速完成；
- 宽范围连续调速完成；
- 所有错误恢复路径都已上板验证；
- 外部串行眼图、BER 或长期稳定性已通过。

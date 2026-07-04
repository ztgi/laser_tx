# 500M/1000M profile table 功能等价重构工程报告

## 1. 修改摘要

本轮按“路线 B：先 Level 3，再 Level 2”执行，只对当前已经验证通过的 500M/1000M 双速率动态切换做 profile table 功能等价重构。

修改文件：

```text
laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v
docs/design_notes/wide_range_dynamic_rate_control_roadmap.md
docs/debug_reports/21_profile_table_refactor_500m_1000m.md
```

本轮没有新增速率，没有新增 156.25MHz profile，没有实现 AD9528 动态 SPI 配置，没有实现 GT refclk 动态切换，没有修改 Vitis/UDP 协议。

重新运行并通过：

```text
synth_1
impl_1
write_bitstream
write_debug_probes
report_timing_summary
report_utilization
report_debug_core -full_path
```

生成同源 bit/LTX：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

## 2. 修改前问题

修改前，500M/1000M 已经可以动态切换，但速率参数组织方式仍偏“两个 profile 的工程验证实现”：

- `request_event` 中直接按 `requested_rate_id` case 分支写入 `target_rate_mbps`；
- `target_txout_div_enc` 在分支中直接赋值；
- `expected_min_count` / `expected_max_count` 在分支中直接赋值；
- MMCM DRP 数据由 `mmcm_data_for_target(rate_id, index)` 根据目标速率选择；
- reset/lock timeout 直接使用全局参数；
- RTL 内没有明确表达 profile 中应预留的 `refclk_id`、`refclk_freq_hz`、`pll_type`、`gt_drp_seq_id`、`mmcm_drp_seq_id`、`flags` 等字段。

这种写法对 500M/1000M 最小验证是合理的，但继续扩展时容易把速率参数、timeout、reset 策略和状态机流程混在一起。后续新增第三速率时，如果继续复制分支，会增加维护风险。

本轮问题不是功能 bug，而是架构演进问题：需要把当前 500M/1000M 特例状态机整理为 profile-driven Rate Switch Executor 的雏形。

## 3. 修改后结构

### 3.1 profile table accessor

本轮新增 profile accessor，将 500M/1000M 的参数集中描述：

```verilog
profile_supported(rate_id)
profile_rate_mbps(rate_id)
profile_refclk_id(rate_id)
profile_refclk_freq_hz(rate_id)
profile_pll_type(rate_id)
profile_gt_drp_seq_id(rate_id)
profile_mmcm_drp_seq_id(rate_id)
profile_txout_div_enc(rate_id)
profile_expected_txusrclk2_hz(rate_id)
profile_freq_min_count(rate_id)
profile_freq_max_count(rate_id)
profile_lock_timeout(rate_id)
profile_reset_timeout(rate_id)
profile_flags(rate_id)
```

当前两个 profile 均固定为 125MHz refclk：

| Profile | rate_mbps | refclk_id | refclk_freq_hz | AD9528 dynamic |
|---|---:|---|---:|---:|
| 500M | 500 | `REFCLK_125M` | 125000000 | 0 |
| 1000M | 1000 | `REFCLK_125M` | 125000000 | 0 |

### 3.2 request 捕获改为 profile_id 取参数

修改后，`request_event` 不再在 case 分支中逐项写 500/1000 参数，而是：

```text
requested_rate_id
-> profile accessor
-> latch target profile fields
```

锁存字段包括：

```text
target_rate_mbps
target_txout_div_enc
expected_min_count / expected_max_count
target_refclk_id
target_refclk_freq_hz
target_pll_type
target_gt_drp_seq_id
target_mmcm_drp_seq_id
target_expected_txusrclk2_hz
target_lock_timeout
target_reset_timeout
target_profile_flags
```

### 3.3 通用状态机执行流程保持不变

状态机仍执行原有闭环：

```text
RATE_VALIDATE
RATE_QUIESCE_TX
RATE_ASSERT_RESET
RATE_PROGRAM_GT_DRP
RATE_PROGRAM_MMCM_DRP
RATE_RELEASE_RESET
RATE_WAIT_MMCM_RESET_RELEASE
RATE_WAIT_LOCK
RATE_VERIFY_RATE
RATE_DONE / RATE_ERROR
```

没有改变 reset sequence，没有改变 GT/MMCM DRP 写序列，没有改变 `current_rate` 更新条件。

### 3.4 profile 预留字段的边界

本轮只预留并校验 profile 字段，不启用 AD9528/refclk 动态切换：

```text
target_refclk_id 必须为 REFCLK_125M
target_refclk_freq_hz 必须为 125000000
target_pll_type 必须为 PLL_TYPE_CPLL
target_gt_drp_seq_id 必须为 GT_DRP_SEQ_TXOUT_DIV
target_profile_flags 不允许包含 AD9528_DYNAMIC_REQUIRED
```

这保证本阶段仍只覆盖当前已验证的 125MHz refclk 下 500M/1000M 动态切换。

### 3.5 Profile 参数来源分层

本阶段的软件/硬件分工需要明确：当前不是“Vitis 计算所有 GT/MMCM DRP 数值后传给 PL”。

当前阶段：

```text
Vitis/UDP 只发送目标速率或 profile_id，例如 rate set 500 / rate set 1000；
PL 内部通过固化的 profile table / profile accessor 选择已验证 profile；
PL rate controller 根据选中的 profile 执行 GT DRP、MMCM DRP、reset release、MMCM lock wait、GT ready wait、txusrclk2 frequency verify、current_rate update；
Vitis 只负责命令下发和状态回读，不直接写 GT/MMCM DRP addr/data。
```

下一阶段新增第三速率时，仍建议保持同样分工：

```text
软件仍只下发 rate/profile_id；
第三速率的 GT/MMCM/refclk/timeout/frequency window 仍先固化在 RTL profile table；
先完成 static build，再加入 dynamic path 验证。
```

长期 Level 4 阶段才可以考虑升级 profile 来源：

```text
PC/Vitis/离线工具生成 profile；
通过 AXI BRAM 或 AXI-Lite 写入 PL；
PL 侧执行 profile validator；
校验版本、CRC、合法性、refclk 匹配、GT/MMCM 参数范围；
失败时执行 rollback；
扩展错误码和状态回读。
```

因此，本轮主要修改 Verilog 是合理的：profile 数据仍然固化在 PL 内部，没有改变 Vitis/UDP 协议、AXI 地址、BD 或 XSA。只有未来改成 Vitis 下载 profile 参数时，才需要修改 Vitis、AXI register/BRAM 接口、BD/XSA/BSP，并重新做软硬件联合验证。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| 请求速率译码 | `requested_rate_id` case 分支直接写参数 | `requested_rate_id` 作为 profile_id，经 profile accessor 取参数 | 结构更适合扩展 |
| 500M/1000M 参数值 | 直接分散在分支中 | 集中在 profile accessor 中 | 参数值不变 |
| GT TXOUT_DIV | 500M=`3'b011`，1000M=`3'b010` | 仍为 500M=`3'b011`，1000M=`3'b010` | 功能等价 |
| MMCM DRP 表 | `mmcm_data_for_target(rate_id,index)` | `mmcm_data_for_seq(target_mmcm_drp_seq_id,index)` | 数据表不变，选择方式更抽象 |
| refclk 字段 | 未显式表达 | 预留 `REFCLK_125M / 125000000` | 不实现 refclk 切换 |
| AD9528 字段 | 未显式表达 | 预留 flag，当前必须为 0 | 不实现 AD9528 动态输出 |
| timeout | 使用全局参数 | profile latch 后使用 `target_lock_timeout/target_reset_timeout` | 当前数值等价 |
| reset sequence | 已修复互锁后的流程 | 保持不变 | 不退化 |
| `current_rate` 更新 | VERIFY 成功后更新 | 仍在 VERIFY 成功后更新 | 不提前假成功 |
| UDP 协议 | `rate set/status` 现有行为 | 不变 | Vitis 不需要修改 |
| ILA probe | rate/reset/lock/ready probe 已存在 | 未修改 probe，报告确认仍存在 | debug 结构不变 |
| 是否新增 pipeline | 无 | 无 | pipeline latency 不变 |

## 5. 功能等价性说明

本轮预期功能行为不变：

- `rate set 1000` 仍应触发 500M -> 1000M；
- `rate set 500` 仍应触发 1000M -> 500M；
- 500M/1000M 的 GT/MMCM 参数不变；
- 125MHz refclk 不变；
- reset sequence 不变；
- `current_rate` 仍只在 `txusrclk2_alive`、频率窗口、MMCM lock、GT ready 等验证成功后更新；
- error_code 行为不应退化；
- UDP rate set/status 协议不变。

本轮功能等价性目前基于 RTL 结构检查和 Vivado synthesis/implementation 结果。尚未重新执行上板 UDP 往返回归，因此不能把 build 通过写成硬件回归通过。

## 6. 测试与验证

### 6.1 执行命令

使用 Vivado 2022.2 project flow 临时 Tcl 执行：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source %TEMP%\laser_tx_profile_table_build.tcl"
```

临时 Tcl 位于用户临时目录，仅作为本轮命令驱动使用；未修改工程 build 脚本。

### 6.2 build 结果

```text
synth_1_STATUS=synth_design Complete!
synth_1_first_ERROR=

impl_1_STATUS=write_bitstream Complete!
impl_1_first_ERROR=
```

bit/LTX：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx

D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

### 6.3 debug core 检查

`report_debug_core -full_path` 路径：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/profile_table_refactor/impl1_debug_core_full_path.rpt
```

结果摘要：

```text
debug_cores = dbg_hub, ila_laser_axi_cfg, ila_laser_tx
dbg_hub/clk = gt_ctrl_clk / clk_fpga_0
ila_laser_axi_cfg/clk = gt_ctrl_clk
```

报告中确认 AXI/FCLK ILA 仍包含：

```text
dbg_rate_state
dbg_target_rate_mbps
dbg_current_rate_mbps
dbg_rate_error
dbg_rate_error_code
dbg_tx_mmcm_reset_wizard/rate/final
dbg_txoutclk_alive_axi
```

### 6.4 未执行项

```text
Simulation was not run
Hardware test was not run
```

尚未重新执行：

```text
rate set 1000
rate set 500
500M <-> 1000M UDP 循环
上板 ILA capture
```

这些是下一步硬件回归项。

## 7. QoR / timing 对比

修改前参考值来自上一轮 reset sequence 修复后的实现报告；修改后来自本轮 `profile_table_refactor` 实现报告。

| Metric | Before | After | Interpretation |
|---|---:|---:|---|
| Setup WNS | 7.029 ns | 7.029 ns | 持平 |
| Setup TNS | 0.000 ns | 0.000 ns | 无 setup violation |
| Setup failing endpoints | 0 | 0 | 无退化 |
| Hold WHS | 0.042 ns | 0.049 ns | 仍通过 |
| Hold THS | 0.000 ns | 0.000 ns | 无 hold violation |
| LUT | 22527 | 22557 | 增加约 30 LUT，符合 profile 字段/译码增加预期 |
| FF | 21527 | 21527 | 持平 |
| BRAM Tile | 61 | 61 | 持平 |
| DSP | 0 | 0 | 持平 |
| BUFGCTRL | 6 | 6 | 持平 |
| MMCME2_ADV | 1 | 1 | 持平 |

当前 timing 结果：

```text
All user specified timing constraints are met.
```

Timing/QoR 说明：本轮没有声明 QoR 改善；只确认 profile table 重构后当前实现仍满足已约束时序。当前 clock constraint 仍沿用已有工程约束，未在本轮修改。

## 8. XSA / Platform / BSP / 软件影响

本轮未修改 BD、AXI 地址、Vitis、BSP、UDP 协议或软件可见 register map。

```text
XSA / Platform / BSP dependency unchanged
```

不需要因本轮 profile table 重构重新导出 XSA 或重建 Vitis platform/BSP。软件侧仍使用现有 `rate set 500` / `rate set 1000` / `rate status` 流程。

## 9. 修改文件列表

| File | Change |
|---|---|
| `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | 将 500M/1000M 参数组织方式重构为 profile accessor/table 形式；状态机流程保持不变 |
| `docs/design_notes/wide_range_dynamic_rate_control_roadmap.md` | 增加本阶段 profile table 预留 refclk_id、但不实现 AD9528/refclk 切换的说明 |
| `docs/debug_reports/21_profile_table_refactor_500m_1000m.md` | 新增本轮工程变更报告 |

生成/更新报告与产物：

```text
reports/dynamic_rate_500m_1000m/profile_table_refactor/
reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

## 10. 风险与后续建议

### 10.1 残留风险

1. 本轮重构已通过 synthesis/implementation/timing，但尚未重新上板执行 UDP 回归；
2. `profile_refclk_id/refclk_freq_hz/pll_type/flags` 当前为预留字段，不表示已经实现 AD9528/refclk 切换；
3. profile accessor 在综合后可能仍实现为比较器、mux、LUT 或 case，这是正常硬件实现，不是问题；
4. 后续新增第三速率前仍必须先做 static profile build/ILA 验证；
5. 本轮没有改变 error_code 编码，但硬件回归仍需确认错误路径没有退化。

### 10.2 下一步建议

建议下一步只做 500M/1000M 功能等价上板回归：

```text
1. Program 本轮 bit/LTX；
2. UDP 执行 rate status；
3. rate set 1000；
4. rate status 确认 current_rate=1000、RATE_DONE、error_code=NONE、gt_ready=1；
5. rate set 500；
6. rate status 确认 current_rate=500、RATE_DONE、error_code=NONE、gt_ready=1；
7. 执行 500M <-> 1000M 循环；
8. 必要时用 AXI/FCLK ILA 观察 target/current/state/error/reset/lock/ready。
```

只有上述回归通过后，再进入 Level 2：选择第三速率并先做 static build/ILA 验证。

当前仍不建议引入 AD9528 动态输出、156.25MHz refclk 切换或宽范围任意速率。

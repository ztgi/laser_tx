# AD9528 Runtime Rate 最大速率时序收敛报告

## 1. 本阶段目标与边界

本阶段只处理 AD9528 runtime rate planner 已有实现的最大 TX user clock 静态时序收敛。planner、mailbox、dynamic executor、rollback、PS coordinator、UDP 语义、支持速率范围和 `board_verified` 状态均保持冻结；未进行上板验证，也未增加新 profile。

最大运行点按现有工程约束覆盖：

- `TXUSRCLK = 322.265625 MHz`，period `3.103 ns`；
- `TXUSRCLK2 = 161.1328125 MHz`，period `6.206 ns`。

本阶段未使用 `set_false_path`、`set_multicycle_path`、`set_max_delay -datapath_only` 或降低最大规划速率来规避真实逐周期数据路径。

## 2. 完整约束审计

Vivado routed design 中的真实时钟对象为：

| Clock | Period | 施加对象 |
|---|---:|---|
| `GT_TXUSRCLK_RUNTIME_MAX` | 3.103 ns | `u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk_bufg/O` |
| `GT_TXUSRCLK2_RUNTIME_MAX` | 6.206 ns | `u_laser_gt_tx_profile0/u_tx_usrclk_profile0/u_txusrclk2_bufg/O` |

`check_timing -verbose` 结果中 `no_clock=0`、`multiple_clock=0`。约束审计未发现旧宽松时钟覆盖上述 runtime maximum clock；AXI/FCLK 与动态 GT user clock 域之间保持工程既有异步 clock-group 定义。

## 3. 修改前 baseline

完整约束 clean synthesis/implementation 的结果：

| Metric | Baseline |
|---|---:|
| Setup WNS | -3.183 ns |
| Setup TNS | -495.623 ns |
| Setup failing endpoints | 295 |
| Hold WHS | +0.051 ns |
| Hold THS | 0 ns |
| Unrouted nets | 0 |

Setup top-100 全部聚集在同一功能路径簇：

| Path cluster | Count | Clock | Worst slack | Logic levels | Logic delay | Route delay |
|---|---:|---|---:|---:|---:|---:|
| `phase_pos_reg[*] -> pattern_cursor_reg[*]` | 100 | `GT_TXUSRCLK2_RUNTIME_MAX` | -3.183 ns | 最高 28 | 最高 2.404 ns | 最高 6.848 ns |

该路径负责逐 TXUSRCLK2 word 更新 pattern cursor，属于真实单周期反馈，不能通过 timing exception 放宽。

## 4. RTL 修改

### 4.1 修改前结构

`pattern_tx_engine` 保存 127-bit `phase_pattern` 和 127-bit `pattern_cursor`。每个 word 都根据 `phase_pos`、gap 宽度和有效 bit 数，对 cursor 执行 254-bit doubled-vector variable rotate，并把新的 127-bit cursor 在同一周期反馈到寄存器。该结构形成 27～28 级逻辑和大范围宽总线路由。

### 4.2 修改后结构

周期 pattern 在 sequence 启动时锁存为不变的 `pattern_base_active[126:0]`；逐周期反馈状态改为 `pattern_index[6:0]`。此外，phase/gap 的宽位绝对位置运算被拆到寄存化 word-geometry descriptor，当前 word 的 gap 边界、remaining bits 和 pattern index 更新只使用已锁存的小位宽描述。index 使用限定范围的 add/compare/subtract 完成 63/127 modulus advance：

- 63-bit 模式最多跨越 modulus 两次，显式比较 63/126；
- 127-bit 模式最多跨越一次，显式比较 127；
- 不推导通用 divider/modulo；
- output word 仍在当前寄存边界生成，稳态吞吐仍为每周期一个 64-bit word；
- 未增加 pipeline latency。

### 4.3 OOC module-reference 一致性

`laser_tx_core` 在 BD 中作为 module-reference IP，implementation 会加载其 OOC DCP。初次 iteration 发现仅 reset top-level run 会继续使用旧 IP cache，日志中仍出现已删除的 `pattern_cursor_reg`，因此该次 run 被判定无效并停止。

收敛脚本随后增加：

1. 仅对 `system_laser_tx_core_0_0` 禁用 IP synthesis cache；
2. 先重建 `system_laser_tx_core_0_0_synth_1`；
3. 打开 OOC run，断言 `pattern_index_reg` 存在且 `pattern_cursor_reg` 为 0；
4. 断言通过后才运行 top-level clean synth/impl。

该处理不修改 BD、端口、AXI 地址或 XSA 接口。

## 5. 修改前后差异

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| pattern 状态 | 127-bit rotating phase/cursor | 固定 127-bit base + 7-bit index | 移除宽 cursor 反馈 |
| cursor advance | 254-bit variable rotate | 7/8-bit add/compare/subtract | 降低反馈逻辑与路由 |
| 稳态吞吐 | 1 word/cycle | 1 word/cycle | 不变 |
| pipeline latency | 0 个新增 stage | 0 个新增 stage | 不变 |
| valid/data 边界 | 同一输出寄存边界 | 同一输出寄存边界 | 不变 |
| reset/quiesce | reset 清零；disable 返回 IDLE | 不变 | 不变 |
| planner/mailbox/UDP | 既有实现 | 未修改 | 不变 |

## 6. 功能等价性验证

新增 direct self-checking regression，直接实例化 `pattern_tx_engine` 并使用独立 golden model 检查：

- 63-bit pattern、phase shift、gap、wrap；
- 127-bit direct pattern、gap、wrap；
- disable/quiesce 后回到 IDLE 并重新启动；
- active sequence 中 reset；
- runtime user-clock period 改变后的数据序列。

结果为 `PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS`。由于没有增加 pipeline stage，比较关系为同周期逐 word/逐 lane 一致，`PIPELINE_LATENCY=0`。

## 7. 时序迭代结果

| Iteration | RTL/strategy | Setup WNS | Setup TNS | Failing endpoints | Hold WHS | 结论 |
|---|---|---:|---:|---:|---:|---|
| baseline | 完整 runtime clocks，默认 strategy | -3.183 ns | -495.623 ns | 295 | +0.051 ns | 失败 |
| 1 | 127-bit cursor 改为 7-bit index | -1.869 ns | -125.056 ns | 以 timing report 为准 | +0.048 ns | 显著改善，仍失败 |
| 2 | 增加 word-geometry descriptor | -0.339 ns | -6.146 ns | 37 | +0.009 ns | 接近收敛，仍失败 |
| 3 | iteration 2 routed DCP + post-route `AggressiveExplore` | -0.153 ns | 仍为负值 | 仍有失败端点 | +0.009 ns | strategy 不能替代剩余 RTL 优化 |
| 4 | descriptor + `Performance_Explore` | -0.234 ns | -3.219 ns | 以 timing report 为准 | +0.054 ns | 未优于 post-route physopt |
| 5 | 单 bit 63/127 mode + `Performance_Explore` | -0.222 ns | -1.099 ns | 以 timing report 为准 | +0.014 ns | 仍未签核 |
| 6 | `pattern_index` 并行 modulo 候选 + `Performance_Explore` | -0.267 ns | -5.884 ns | 46 | +0.045 ns | A 类基本消除，但 C 类路由失败扩大，整体仍未签核 |
| 7 | 分离 63/127 output-word 网络 + 末级 mode mux | +0.028 ns | 0 ns | 0 | +0.034 ns | setup/hold 首次全部通过 |

另有两次探索性结构/strategy run 未纳入有效候选：一次切换 strategy 后未恢复 `OPT_DESIGN` 约束 hook，runtime clocks 缺失，结果无效；一次寄存整组 rotated pattern 导致 WNS 退化到 `-1.847 ns`，已撤销。当前尚未达到最低通过标准，未生成 release artifact。

## 8. QoR / utilization 对比

| Metric | Baseline | Word descriptor iteration | 变化 |
|---|---:|---:|---:|
| Top LUT | 28503 | 27860 | -643 |
| Top FF | 28216 | 28359 | +143 |
| Pattern engine LUT | 7784 | 7150 | -634 |
| Pattern engine FF | 554 | 699 | +145 |
| RAMB36 | 68 | 68 | 0 |
| RAMB18 | 2 | 2 | 0 |

LUT 降低来自移除 127-bit cursor feedback 和宽变量旋转反馈；FF 增加来自 word-geometry descriptor。资源变化未涉及 BRAM/DSP。

## 9. Build 与生成物

Vivado synthesis、implementation、route、timing、utilization、route status 和 DRC 已运行多轮；direct self-checking simulation 通过。最终有效候选仍存在负 setup slack，因此：

- bit/LTX 未生成；
- XSA 未刷新；
- Vitis platform/BSP/ELF 未刷新；
- Hardware test was not run。

时序通过前不生成 release bit/LTX/XSA/ELF。

## 10. 当前边界与风险

- Hardware test was not run.
- `board_verified` 保持 0；
- 未验证 BER、眼图、外部光口或长期稳定性；
- 未扩展 planner/profile/rate 范围；
- `Project 1-840` OOC DCP 警告不是本轮功能主线，但时序通过后仍需规范化 build flow；
- 只有 setup/hold 同时通过后，才允许生成 timing-clean bit/LTX/XSA 并刷新 Vitis platform。

## 11. Iteration 5 中断恢复与可复现性确认

额度中断时 Vivado implementation 仍在运行；恢复现场后确认该 run 已正常完成，未启动第二个 implementation，也未重新运行 baseline。完成后的 routed design 被显式归档到：

`reports/ad9528_gt_rate_planner/timing_iteration5_reproduced/iteration5_routed.dcp`

归档前重新打开 `system_laser_tx_core_0_0_synth_1` OOC DCP，并检查 RTL 签名：

| 签名项 | 数量 | 判定 |
|---|---:|---|
| `pattern_index_reg` | 23 | 存在 |
| `pattern_cursor_reg` | 0 | 已删除 |
| `next_phase_pattern_base_q` | 0 | 失败实验结构不存在 |
| `cross_next_valid_count_q` | 0 | 失败实验结构不存在 |
| `current_pattern_q` | 0 | 失败实验结构不存在 |
| `rotated_pattern_reg` | 0 | 失败实验结构不存在 |

复现配置保持为 `Performance_Explore`，`opt_design/place_design/phys_opt_design/route_design` 均使用该 strategy 对应的 `Explore` directive；原 `gt_profile0_impl_pre.tcl` hook 保持生效，约束时钟仍为 `TXUSRCLK=3.103 ns`、`TXUSRCLK2=6.206 ns`。本轮未执行 post-route physopt，未生成 bit/LTX/XSA。

| Metric | 原 iteration 5 | 复现结果 | 差异 |
|---|---:|---:|---:|
| Setup WNS | -0.222 ns | -0.222 ns | 0.000 ns |
| Setup TNS | -1.099 ns | -1.096 ns | +0.003 ns |
| Setup failing endpoints | 未单独记录 | 15 | — |
| Hold WHS | +0.014 ns | +0.014 ns | 0.000 ns |
| Hold THS | 0 ns | 0 ns | 0 ns |

复现差异远小于 0.15 ns，最差路径仍位于 `pattern_tx_engine` 的 `remaining_rel_q -> pattern_index` 逻辑锥，runtime clocks、strategy、hook 和 OOC RTL 签名均一致，因此标记为：

`ITERATION5_REPRODUCTION_CONFIRMED`

Routed design 中 unrouted net 为 0。DRC error 为 0；存在 4 个 warning，均来自 debug hub 的 `PDCN-1569`/`RTSTAT-10`，不是新增 DRC error。归档 DCP 的 SHA-256 为：

`36cc6458c3821132800074b85347feaef126d342da1fc527545486f0713a73d3`

完整 manifest、约束文件 SHA-256、关键报告 SHA-256 和 OOC 签名保存在同一归档目录。

## 12. 最新失败路径聚类

本节只使用复现后的 setup top-100，不再引用 baseline 已删除的 `phase_pos_reg -> pattern_cursor_reg` 路径。复现 design 共 15 个 setup failing endpoints，TNS 为 -1.096 ns，集中为两个真实逻辑锥：

| 分类 | 路径数 | Worst slack | Cluster TNS | TNS 占比 | 代表路径 | 结构特征 |
|---|---:|---:|---:|---:|---|---|
| A：`pattern_index` next-state feedback | 3 | -0.222 ns | -0.301 ns | 27.5% | `remaining_rel_q_reg[4]_rep__12/C -> pattern_index_reg[3]/D` | 14～15 levels，最多 4 个 CARRY4；代表路径 logic 1.640 ns、route 4.393 ns |
| C：pattern base/index 到 output word 动态选择 | 12 | -0.172 ns | -0.795 ns | 72.5% | `phase_offset_reg[3]/C -> txdata_reg[53]/D` | 11～12 levels，以 LUT6 variable-select/rotate 网络为主；代表路径 logic 0.739 ns、route 5.302 ns |

高扇出关联包括：

- A 类：`remaining_rel_q_reg[4]_rep__12_n_0` fanout 129，以及中间节点 fanout 95；
- C 类：`p_2_out[5]`/`p_2_out[6]` fanout 162；
- 两类都使用 TXUSRCLK2 clock net，但这不是数据逻辑优化对象。

Top 10 失败路径分类为 `A,C,C,C,C,C,A,C,C,C`，因此不属于单一逻辑锥。最紧 hold path 为 AXI/FCLK ILA 内部路径，WHS 为 +0.014 ns；去除 clock resource 后，它与 setup 失败路径没有共享单元或网络。ILA/debug 不是当前 setup 失败端点，当前证据不支持将主要失败归因于 ILA probe。

详细字段、dominant primitives、route/logic delay 和建议动作见：

`reports/ad9528_gt_rate_planner/timing_iteration5_reproduced/final_failing_path_clusters.csv`

## 13. 下一轮最小 RTL 修改方案

下一轮先只处理当前 WNS 最差的 A 类路径，保持 `PIPELINE_LATENCY=0`：在 `pattern_tx_engine.v` 的 `advance_pattern_index()` 中，将当前串行 `compare -> subtract -> compare/select` 结构改为并行候选结构。

具体表达式为：

1. 并行计算 `sum = index + count`；
2. 同时计算扩展位宽的 `sum-63`、`sum-126`、`sum-127`；
3. 从三个减法结果的 borrow 位产生 `ge63/ge126/ge127`；
4. 63-bit 模式末级只在 `sum`、`sum-63`、`sum-126` 中选择；
5. 127-bit 模式末级只在 `sum`、`sum-127` 中选择；
6. 禁止 `%`、通用 divider 和串行 compare/subtract 链。

该改动只重写局部组合表达式，不改变寄存器边界、接口、valid/data 对齐、reset、quiesce 或每周期吞吐。完成后先运行 self-checking regression，再强制重建 OOC DCP 并重新分类 routed path。由于 C 类仍占 72.5% TNS，本次 A 类优化即使消除当前 WNS，也不能预先声明整体时序一定通过；如果最差路径转移到 C 类，再单独实施 63/127 选择网络分离，不在本轮同时引入 output pipeline。

## 14. Iteration 6：A 类 `pattern_index` 并行候选优化结果

### 14.1 实际 RTL 修改

本轮只修改 `advance_pattern_index()` 的组合实现，没有继续修改 C 类 output-word 网络。修改前，63/127 modulus advance 的比较与减法存在串行依赖；修改后先并行形成：

```text
sum      = index + count
sub63    = sum - 63
sub126   = sum - 126
sub127   = sum - 127
```

`ge63/ge126/ge127` 直接取自 9-bit 无符号减法结果的 borrow 语义。63-bit 模式的末级只在 `sum/sub63/sub126` 中选择，127-bit 模式的末级只在 `sum/sub127` 中选择。实现中未使用 `%`、divider、串行 compare→subtract 链、timing exception 或新 pipeline stage；`PIPELINE_LATENCY` 保持 0。

### 14.2 功能回归与 OOC 一致性

修改后运行现有 direct self-checking regression，覆盖 63/127-bit、phase、gap、wrap、disable/quiesce、reset 和 runtime clock period change，结果为：

`PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS`

随后强制重建 `system_laser_tx_core_0_0_synth_1`，并在 OOC DCP 中确认：

| RTL 签名 | 数量 | 判定 |
|---|---:|---|
| `pattern_index_reg` | 21 | 新结构存在 |
| `pattern_cursor_reg` | 0 | 旧 cursor 结构不存在 |
| `next_phase_pattern_base_q` | 0 | 失败实验结构不存在 |
| `cross_next_valid_count_q` | 0 | 失败实验结构不存在 |
| `current_pattern_q` | 0 | 失败实验结构不存在 |
| `rotated_pattern_reg` | 0 | 失败实验结构不存在 |

implementation 继续使用 iteration 5 相同配置：`TXUSRCLK=3.103 ns`、`TXUSRCLK2=6.206 ns`、`Performance_Explore` 和原 runtime clock hook。上述时钟约束是当前最大运行点的实际 sign-off 约束，不是为了实验临时放宽的约束。

### 14.3 Routed timing 与失败路径迁移

| Metric | Iteration 5 reproduced | Iteration 6 parallel index | 变化与解释 |
|---|---:|---:|---|
| Setup WNS | -0.222 ns | -0.267 ns | 整体退化 0.045 ns；最差路径已转移到 C 类 |
| Setup TNS | -1.096 ns | -5.884 ns | C 类 output-word 路由失败显著扩大 |
| Failing endpoints | 15 | 46 | 增加 31 个，主要为 C 类 `txdata_reg` endpoint |
| Hold WHS | +0.014 ns | +0.045 ns | hold 仍通过 |
| Hold THS | 0 ns | 0 ns | hold 仍通过 |
| Unrouted nets | 0 | 0 | route 完整 |

iteration 6 setup top-100 的重新聚类结果为：

| 分类 | 路径数 | Worst slack | Cluster TNS | TNS 占比 | 代表路径 |
|---|---:|---:|---:|---:|---|
| A：`pattern_index` next-state feedback | 1 | -0.025 ns | -0.025 ns | 0.4% | `gap_present_active_reg_rep__4/C -> pattern_index_reg[3]/D` |
| C：pattern base/index 到 output word 动态选择 | 45 | -0.267 ns | -5.855 ns | 99.6% | `len_active_reg[5]/C -> txdata_reg[30]/D` |

与 iteration 5 相比，A 类由 3 条、cluster TNS `-0.301 ns` 降为 1 条、`-0.025 ns`，说明并行候选改写确实基本消除了目标 feedback 逻辑锥；但整体 timing 没有通过，且不能把局部结构改善写成全局 QoR 改善。

新的 C 类最差路径有 12 个 logic levels，logic delay 约 `0.759 ns`，route delay 约 `5.388 ns`，route 占主要部分；`p_0_in[5]` 和 `p_0_in[6]` fanout 均为 162。该证据表明下一轮应单独处理 63/127 output-word 动态选择和高扇出，而不是继续改 A 类算术。

### 14.4 Resource 对比

| Resource | Iteration 5 | Iteration 6 | 变化 |
|---|---:|---:|---:|
| Top LUT | 27944 | 27843 | -101 |
| Top logic LUT | 24378 | 24277 | -101 |
| Top FF | 28368 | 28361 | -7 |
| Pattern engine LUT | 7228 | 7134 | -94 |
| Pattern engine FF | 706 | 699 | -7 |
| RAMB36 | 68 | 68 | 0 |
| RAMB18 | 2 | 2 | 0 |

资源减少与局部算术/选择结构简化一致，但 setup timing 仍由 C 类长路由主导。

### 14.5 归档与停止条件

新的 routed DCP 和全部诊断报告保存于：

`reports/ad9528_gt_rate_planner/timing_iteration6_parallel_index/`

归档 DCP：

`reports/ad9528_gt_rate_planner/timing_iteration6_parallel_index/iteration6_parallel_index_routed.dcp`

SHA-256：

`83a0c86dcbfefefd7a4193c5011cfc9c7302a9bd5934c0037938f504680684e7`

本轮未达到 `WNS>=0`、`TNS=0`，因此停止生成 timing-clean bit/LTX/XSA，也未刷新 Vitis platform/BSP/ELF，未执行硬件测试。

下一轮 C 类最小修改应保持独立：分别构造 63-bit 与 127-bit output-word 选择网络，只在末级选择模式，并优先用局部单 bit mode/geometry 信号替代 `len_active` 宽字段对输出网络的直接驱动；同时将仅供 ILA/debug 的扇出从功能组合锥隔离。只有该无 pipeline 方案仍无法得到稳定正裕量时，才评估增加一级 pattern-word pipeline，并同步处理 valid、enable、laser gate、mode、frame boundary 和 idle/quiesce 对齐。

## 15. Iteration 7：分离 63/127 output-word 网络

### 15.1 修改前 C 类 routed 结构确认

修改 RTL 前，仅打开 iteration 6 归档 DCP 进行结构审计，没有重跑 baseline 或 implementation。审计报告保存于：

`reports/ad9528_gt_rate_planner/timing_iteration6_c_path_audit/`

确认结果如下：

- C 类 setup top-50 全部终止于 `txdata_reg[*]/D`；
- 最差路径为 `len_active_reg[5]/C -> txdata_reg[30]/D`，slack `-0.267 ns`；
- 该路径有 12 个 logic levels，logic delay `0.739 ns`、route delay `5.388 ns`；
- 完整 `len_active` 参与 `last_phase_calc`，然后进入 phase-offset 和 output-word 组合锥；
- `p_0_in[5]`、`p_0_in[6]` 是 phase-offset 相关综合网，各有 162 fanout，并驱动大量 `txdata` 选择 LUT；
- 原 RTL 使用一个带 `sequence_is_63` 输入的通用 `rotate_sequence()`，63/127 模式判断被综合进输出网络；
- `len_active`、`phase_offset`、`pattern_index` 相关功能节点没有直接驱动 ILA load，因此当前 C 类失败不能归因于 ILA probe。

该证据支持只处理 C 类 output-word 网络，不再改动 iteration 6 已完成的 A 类并行 modulo 结构。

### 15.2 Iteration 7 RTL 结构

sequence 启动时只锁存单 bit `pattern_mode_63_active`；原 `len_active[7:0]` 状态及高速发送期间的完整长度比较被删除。固定长度网络改为：

1. `rotate_sequence_63()` 只接收 `pattern_base_active[62:0]` 和 `pattern_index[5:0]`；
2. `rotate_sequence_127()` 只接收 `pattern_base_active[126:0]` 和 `pattern_index[6:0]`；
3. 分别形成 `word_63_comb/valid_63_comb` 与 `word_127_comb/valid_127_comb`；
4. 63/127 各自独立处理 current pattern、next-phase pattern、gap 对齐和 phase-boundary valid；
5. 只在完整 candidate word 形成后，由 `pattern_mode_63_active` 在末级选择 `txdata_calc`、`valid_mask_calc` 和 `phase_start_calc`。

两个专用网络内部没有 `len_active` 动态判断、动态 modulus、`%`、divider 或通用可变长度 rotate。`advance_pattern_index()` 的 iteration 6 并行 `sum/sub63/sub126/sub127` 实现保持不变。未增加 pipeline，`PIPELINE_LATENCY=0`。

### 15.3 功能回归

修改后重新运行完整 direct self-checking regression，覆盖：

- 63-bit phase/gap/wrap；
- 127-bit direct/gap/wrap；
- disable/quiesce 后 restart；
- reset；
- runtime clock period change；
- 同周期 data/valid golden-model 比较。

结果：

`PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS`

因此当前自动验证支持 `PIPELINE_LATENCY=0` 下的功能等价性结论；尚未执行硬件波形或板级回归。

### 15.4 OOC 与实现配置

强制重建 `system_laser_tx_core_0_0_synth_1` 后，OOC 签名为：

| RTL 签名 | 数量 | 判定 |
|---|---:|---|
| `pattern_index_reg` | 21 | A 类优化仍存在 |
| `pattern_cursor_reg` | 0 | 旧结构不存在 |
| `pattern_mode_63_active` | 2 | 单 bit mode 寄存器存在 |
| `len_active_reg` | 0 | 完整长度状态已退出高速网络 |
| 失败实验结构 | 0 | 未混入历史失败结构 |

implementation 使用与 iteration 6 完全相同的 `Performance_Explore`、runtime clock hook、`TXUSRCLK=3.103 ns` 和 `TXUSRCLK2=6.206 ns`。没有改变时钟约束，也没有使用 timing exception。

### 15.5 Timing、失败路径与 fanout

| Metric | Iteration 6 | Iteration 7 | 解释 |
|---|---:|---:|---|
| Setup WNS | -0.267 ns | +0.028 ns | setup 首次通过 |
| Setup TNS | -5.884 ns | 0 ns | 无 setup failing endpoint |
| Setup failing endpoints | 46 | 0 | A/C 失败路径均清零 |
| Hold WHS | +0.045 ns | +0.034 ns | hold 通过 |
| Hold THS | 0 ns | 0 ns | hold 通过 |
| Unrouted nets | 0 | 0 | route 完整 |
| DRC errors | 0 | 0 | 无 DRC error |

由于 iteration 7 没有负 slack，A 类失败路径数/TNS 为 `0/0 ns`，C 类失败路径数/TNS 也为 `0/0 ns`。最新 setup top-20 均为正 slack：其中 16 条仍属于 C 类 output-word 路径，3 条属于 word-geometry descriptor，1 条属于 gap/control；最差路径为：

`phase_offset_reg[3]/C -> txdata_reg[62]/D`

其 slack 为 `+0.028 ns`，11 个 logic levels，logic delay `0.878 ns`、route delay `4.919 ns`。相比 iteration 6 的 C 类最差路径，route delay 从 `5.388 ns` 降为 `4.919 ns`，且完整 `len_active` 已不再作为起点。

iteration 6 的 `p_0_in[5]/p_0_in[6]` fanout-162 网络在 iteration 7 归档的 selected-net 审计中不再出现。新的 `pattern_mode_63_active` fanout 为 161 个 loads（flat pin count 162），但这些负载属于专用 candidate word 完成后的末级选择，且 ILA load count 为 0；它没有形成负 slack endpoint。

### 15.6 Resource 变化

| Resource | Iteration 6 | Iteration 7 | 变化 |
|---|---:|---:|---:|
| Top LUT | 27843 | 29140 | +1297 |
| Top logic LUT | 24277 | 25574 | +1297 |
| Top FF | 28361 | 28362 | +1 |
| Pattern engine LUT | 7134 | 8437 | +1303 |
| Pattern engine FF | 699 | 700 | +1 |
| RAMB36 | 68 | 68 | 0 |
| RAMB18 | 2 | 2 | 0 |

LUT 增加来自同时实现两个固定 modulus output-word 网络；FF 仅增加单 bit mode 状态。该修改以组合资源换取较短、较局部的固定选择网络，没有增加 pipeline 或 BRAM/DSP。

### 15.7 归档、结论与停止点

iteration 7 routed DCP 和报告已独立归档到：

`reports/ad9528_gt_rate_planner/timing_iteration7_split_output_network/`

归档 DCP：

`iteration7_split_output_network_routed.dcp`

SHA-256：

`85c585c413abc8522c262a93e09f78a7288d5e38139ed5e4f95e74a6d21b8a8a`

当前结果满足本轮最低停止条件：

```text
WNS >= 0
TNS = 0
WHS >= 0
THS = 0
DRC error = 0
unrouted net = 0
```

因此停止继续修改 RTL，不增加 pattern-word pipeline，也不再盲试 implementation strategy。当前 WNS 只有 `+0.028 ns`，低于建议的 `+0.15 ns` 工程余量，所以在后续生成 timing-clean artifact 时仍需保留该风险说明，并确认重新生成 bitstream 的实现结果没有发生负向漂移。

本轮尚未生成 bit/LTX/XSA，未刷新 Vitis platform/BSP/ELF，也未执行 hardware test。下一独立阶段才进行 timing-clean artifact、XSA 和软件平台刷新，不与本轮 C 类 RTL 提交混合。

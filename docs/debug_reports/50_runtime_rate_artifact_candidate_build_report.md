# Runtime-rate artifact candidate build report

## 1. 修改摘要

本阶段没有修改功能 RTL、profile、planner、mailbox、dynamic executor、PS coordinator、UDP、速率范围或 pattern 数据语义。工作集中在 Vivado managed OOC 构建流规范化、Iteration 7 RTL 签名门控、最大运行时钟 clean implementation、Project 1-840 溯源，以及同一次 routed design 的 bit/LTX/XSA 生成。

构建基线为 `timing-clean-rtl-baseline`（`07f2f00`），当前 artifact 构建分支为 `feature/runtime-rate-artifact-candidate-v1`。

## 2. 修改前问题

原工程的 Vivado 2022.2 managed BD composite flow 在实现脚本中直接 `add_files` 由 BD 导出的 child-IP DCP，因此出现 13 个唯一的 `Project 1-840` 诊断。风险不在于警告文字本身，而在于如果 generated DCP 与对应 managed OOC run 不一致，顶层可能消费陈旧 checkpoint。

此外，Iteration 7 的 setup 裕量只有 `+0.028 ns`，任何旧 OOC cache、自动 incremental checkpoint 或宽松时钟覆盖都会使 artifact 失去可追溯性。

## 3. 修改后结构

正式脚本执行以下门控：

1. clean regenerate `system.bd` targets；
2. 创建并重建全部 14 个 managed OOC runs；
3. 对每个 run DCP 与 BD exported DCP 计算 SHA-256并要求相同；
4. 强制 `system_laser_tx_core_0_0_synth_1` 重建并检查 Iteration 7 RTL 签名；
5. top synthesis 明确使用 `-incremental_mode off`，不接受自动 incremental checkpoint；
6. 使用 `Performance_Explore` 与 runtime clock hook 完成 place/route；
7. timing、DRC、route、OOC signature、regression 全部通过后才生成 bit/LTX/XSA。

Vivado 2022.2 生成的 implementation Tcl 仍会对 13 个 child-IP generated DCP 产生 `Project 1-840`。本阶段没有 suppress 或降级这些 Critical Warning，而是对每一个 DCP建立 managed-run/export 哈希一致性证据。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| OOC依赖 | generated DCP freshness 无统一门控 | 14个 managed OOC run clean rebuild，并与 BD export SHA-256逐项匹配 | 排除旧 checkpoint 污染 |
| top synthesis | 可能使用自动 incremental checkpoint | 明确 `incremental_mode off` | clean reproducibility |
| RTL签名 | 实现后人工判断 | top build 前自动检查 | 错误 RTL 立即停止 |
| runtime clocks | Iteration 7 hook | 继续使用 3.103/6.206 ns hook | 约束未放宽 |
| pipeline | 0 | 0 | 接口延迟不变 |
| 功能行为 | Iteration 7 | 未改 | 预期不变 |
| artifact | 尚未生成正式同源三件套 | 同一 routed design 生成 bit/LTX/XSA | 可进入软件平台闭环 |
| hardware test | 未执行 | 未执行 | `board_verified=0` |

## 5. 功能等价性说明

Expected system behavior unchanged。

本阶段未改动数据/valid 对齐、start/end、reset、trigger pulse、状态机、gap/partial-word、CDC 或外部接口。`PIPELINE_LATENCY=0`。功能回归得到 `PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS`，覆盖 63/127-bit、restart/quiesce 与 runtime period。功能等价结论由 self-checking regression 与 RTL 签名共同支持；尚未执行本候选 artifact 的硬件回归。

## 6. Project 1-840审计

- 唯一 DCP：13 个；
- `impl_1/runme.log` 文本出现次数：39（同一组诊断在多个 implementation 阶段重复输出）；
- 调用来源：Vivado 自动生成的 `laser_tx.runs/impl_1/laser_tx_board_top.tcl:add_files`；
- 仓库自定义脚本没有 `read_checkpoint` 或硬编码 child DCP；
- 14 个 OOC run/export 对全部 `match=1`；
- 结论：警告没有消除，但其陈旧 DCP 风险已通过 clean rebuild、来源审计和逐项哈希闭环。逐项记录见 `project_1_840_audit.csv` 与 `ooc_dcp_freshness.tsv`。

## 7. OOC RTL签名

| 签名 | 数量 | 判定 |
|---|---:|---|
| `pattern_index_reg` | 21 | >0，通过 |
| `pattern_mode_63_active` | 2 | >0，通过 |
| `pattern_cursor_reg` | 0 | 通过 |
| `len_active_reg` | 0 | 通过 |
| 历史失败实验节点 | 0 | 通过 |

## 8. 构建与测试验证

- Vivado：2022.2 build 3671981；
- device：`xc7z100ffg900-2`；
- top：`laser_tx_board_top`；
- strategy：`Performance_Explore`；
- TXUSRCLK：`3.103 ns`；
- TXUSRCLK2：`6.206 ns`；
- top synthesis log：`Incremental flow is disabled.`；
- pattern regression：`PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS`；
- artifact flow：`RUNTIME_RATE_ARTIFACT_BUILD=PASS`。

Hardware test was not run.

## 9. QoR / timing 对比

| Metric | Iteration 7 baseline | Clean artifact build | Interpretation |
|---|---:|---:|---|
| Setup WNS | +0.028 ns | +0.028 ns | 可重复 |
| Setup TNS | 0.000 ns | 0.000 ns | 通过 |
| Setup failing endpoints | 0 | 0 | 通过 |
| Hold WHS | +0.034 ns | +0.034 ns | 通过 |
| Hold THS | 0.000 ns | 0.000 ns | 通过 |
| Hold failing endpoints | 0 | 0 | 通过 |
| LUT | 29140 | 29140 | 本阶段未改 RTL |
| FF | 28362 | 28362 | 本阶段未改 RTL |
| RAMB36 / RAMB18 | 68 / 2 | 68 / 2 | 本阶段未改 RTL |
| DSP | 0 | 0 | 无变化 |

当前运行时钟约束为本阶段正式最大运行约束，不是临时宽松约束。WNS 仅 `+0.028 ns`，仍低于建议的 `+0.15 ns` 工程余量，首次上板和后续任何 Vivado/IP变化都必须重新确认 timing。

## 10. DRC、route 与 debug warning

- DRC errors：0；
- unrouted nets：0；
- `no_clock`：0；
- `multiple_clock`：0；
- unconstrained internal endpoints：0；
- `PDCN-1569`：3，均位于 generated `dbg_hub` LUT；
- `RTSTAT-10`：1个汇总、36个 no-routable-load nets，主要属于 debug/优化后无负载分支，不是 unrouted net。

没有为了消除 warning 修改高速数据路径。接受依据与剩余风险见 `reports/ad9528_gt_rate_planner/artifact_build/debug_warning_acceptance.md`。

## 11. 同源硬件产物

以下本地产物来自同一次 timing-clean routed implementation：

- `reports/ad9528_gt_rate_planner/artifact_build/artifacts/laser_tx_board_top.bit`
- `reports/ad9528_gt_rate_planner/artifact_build/artifacts/laser_tx_board_top.ltx`
- `reports/ad9528_gt_rate_planner/artifact_build/artifacts/laser_tx_board_top_runtime_rate_switch.xsa`
- `reports/ad9528_gt_rate_planner/artifact_build/routed.dcp`

bit/LTX/XSA/DCP 是本地构建产物，默认不提交 Git。SHA-256 将在 Vitis ELF 完成后统一写入 `release_artifact_manifest.json`。

## 12. 接口、时钟、复位、AXI与软件影响

- 外部端口：未改；
- BD端口/连接：未改；
- clock/reset topology：未改；
- AXI address map unchanged；
- wrapper：未改；
- XDC功能约束：未改；
- XSA：由当前 implemented design 重新导出；
- Vitis platform/BSP：下一提交使用该 XSA 在干净 workspace 中重新生成。

## 13. 修改文件与生成报告

构建流脚本和审计工具：

- `scripts/audit_project_1_840_sources.tcl`
- `scripts/generate_project_1_840_audit.py`
- `scripts/run_runtime_rate_artifact_candidate_build.tcl`

本次归档文本报告位于 `reports/ad9528_gt_rate_planner/artifact_build/`。Vivado `.xpr`、BD、XCI 自动刷新漂移未提交。

## 14. 风险与后续建议

1. Project 1-840 未达到数量0；必须保留逐项 freshness 证据，不能把警告描述为已消失。
2. WNS 工程余量很小；任何重新实现都必须重新经过相同 timing gate。
3. PDCN-1569/RTSTAT-10 尚需用匹配 bit/LTX 在 Hardware Manager 验证 ILA枚举与采集。
4. 下一步使用同源 XSA 创建全新 Vitis platform/BSP，正式确认 mailbox `0x40040000` 与 descriptor BRAM `0x42000000`。
5. 本阶段未上板、未做 BER/眼图/光口/长期稳定性验证，`board_verified=0`。

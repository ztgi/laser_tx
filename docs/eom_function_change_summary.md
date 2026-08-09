# EOM 功能变化总结

> TX Sequence V2 production baseline update: `soa_gate_out`不再来自
> `phase_active`。`tx_eom_window_generator`现在用同一条经过安全门控的
> EOM window net同时驱动`eom_out`和`soa_gate_out`。两者逻辑窗口起止、
> reset和clock-unsafe行为完全一致；只有独立封装/PCB输出延迟可能不同。

## 1. 文档范围与证据边界

本文基于分支 `fix/tx-sequence-v2-user-cdc-methodology` 当前工作树，对 EOM 从
TX Sequence V2 引入到本轮用户 RTL CDC 收口后的结构和行为进行总结。主要证据为：

- 当前 RTL 与 testbench；
- TX Sequence V2 引入提交 `39925dc`；
- 当前工作树相对 `39925dc` 的 CDC 修改；
- 已存在的 RTL 回归结果和 routed implementation 报告。

本次任务只新增本文档，没有修改 RTL、BD、XDC、Vitis 软件或构建脚本，也没有
重新运行仿真、综合、实现或硬件测试。本文提到的验证结果均明确标注为“既有证据”，
不是本次文档任务新执行的结果。

## 2. EOM 功能演进概览

### 2.1 TX Sequence V2 以前

旧结构中的 `eom_out` 由 `sync_signal_gen` 根据 `valid_mask` 生成，本质上等价于
当前 TX word 是否包含有效 bit 的 word-level activity 指示。它不能表达“整项任务中
选定某个 pattern instance，只产生一次带 lead/trail 的全局 EOM 窗口”。

### 2.2 TX Sequence V2 引入的目标

提交 `39925dc` 将 EOM 重新定义为任务级、全局选点、单次输出功能：

1. PS 在 16-word 配置 record 中指定 EOM 参数；
2. PL 按 phase-major、repeat-minor 顺序定位一个 selected pattern instance；
3. 根据 HEAD、各段 pattern、独立 gap 和 phase 扫描结构计算该 instance 的 bit geometry；
4. 将 bit geometry 换算为当前 profile 的 EOM tick；
5. 在被选 pattern 周围应用 lead/trail；
6. 每个被接受的任务最多产生一次 EOM；
7. 即使 `loop_en=1` 重复发送 sequence，也不重复 arm EOM；只有新任务才能产生下一次 EOM；
8. TX 第一笔 word 与 EOM task tick 0 使用确定性的共同边界。

与此同时，`eom_out` 从 `sync_signal_gen` 中移出，改由
`tx_eom_window_generator` 独立生成。`sync_signal_gen` 继续负责 SOA/ACQ 信号，
不再以 `valid_mask` 生成 EOM。

### 2.3 外部接口

功能外部端口仍为：

```text
laser_tx_core.eom_out
→ BD laser_tx_core_0_eom_out
→ system_wrapper.eom_out_0
→ laser_tx_board_top.eom_out_0
```

当前工程实际使用的手写约束文件为 `constraints/laser_tx_board_io.xdc`，其中
`eom_out_0` 约束到 J9 GPIO1 / FPGA `AG17`，IOSTANDARD 为 `LVCMOS33`。
EOM 引入和本轮 CDC 收口均未改变端口名称、方向、位宽、AXI 地址或 GPIO 映射。

## 3. EOM 配置参数与 record 位置

EOM 使用 TX Sequence V2 的固定 16-word record。相关字段为：

| 字段 | record位置 | 含义 |
|---|---|---|
| `eom_enable` | word2 bit17 | 是否为本任务生成 EOM |
| `eom_global_pattern_index` | word2 bits28:18 | 全局 selected pattern instance |
| `eom_lead_ticks` | word8 bits15:0 | 相对 selected pattern 起点向前扩展的 tick 数 |
| `eom_trail_ticks` | word8 bits31:16 | 相对 selected pattern 终点向后扩展的 tick 数 |
| `repeat_cycles` | word2 bits4:0 | 每个 phase 中的 pattern instance 数 |
| `phase_shift_en` | word2 bit13 | 是否扫描全部 phase |
| `head_delay_bits` | word3 bits7:0 | 每个 phase 开始前的 HEAD bit 数 |
| `gap_len_bits[0..14]` | word4..word7 | 相邻 repeat pattern 之间的独立 gap |
| `pattern_len` | word2 bit16编码 | configured pattern 长度，63或127 bit |

完整 record 继续使用 word15 CRC32，覆盖 word1..word14；PS 先写 payload/CRC，
最后提交 word0 header。EOM 没有新增独立 AXI 地址或旁路配置接口。

## 4. selected pattern 与 geometry 计算

### 4.1 全局索引

全局 pattern instance 按 phase-major、repeat-minor 编号：

```text
phase_count  = phase_shift_en ? pattern_len : 1
instance_cnt = phase_count * repeat_cycles

selected_phase  = floor(global_pattern_index / repeat_cycles)
selected_repeat = global_pattern_index % repeat_cycles
```

若 `eom_enable=0`，或 `global_pattern_index >= instance_cnt`，TX任务仍可执行，
但 EOM geometry 被标记为不可请求，不产生 EOM 脉冲。

### 4.2 phase frame

每个 phase 的完整长度为：

```text
frame_bits = head_delay_bits
           + repeat_cycles * pattern_len
           + sum(gap[0 .. repeat_cycles-2])
```

selected pattern 的绝对起止 bit 位置为：

```text
selected_start_bits = selected_phase * frame_bits
                    + head_delay_bits
                    + selected_repeat * pattern_len
                    + sum(gap[0 .. selected_repeat-1])

selected_end_bits   = selected_start_bits + pattern_len
```

geometry 由 `tx_eom_geometry_precompute` 在 EOM clock 域内以多状态顺序运算完成，
包含 global index 分解、gap 累加、phase/repeat offset、bit-to-tick 换算和
lead/trail 应用。它不位于 64-bit TX word 的实时输出组合路径中。

### 4.3 bit 到 tick

当前结构满足：

```text
K = 2 ^ eom_subdiv_log2
EOM clock = K * TXUSRCLK2
serial_bits_per_eom_tick = 64 / K
```

geometry 换算规则为：

```text
start_tick_floor = floor(selected_start_bits / serial_bits_per_eom_tick)
end_tick_ceil    = ceil(selected_end_bits / serial_bits_per_eom_tick)

start_tick = max(start_tick_floor - lead_ticks, 0)
end_tick   = end_tick_ceil + trail_ticks
```

500M/1000M/2000M 固定档的 EOM clock 均为125 MHz，对应 K=16/8/4，
EOM tick 约为8 ns。lead/trail 的单位是 EOM tick，而 HEAD/gap 的单位仍是
serial bit；CDC 收口没有改变这两个单位或其换算方法。

## 5. AXI/control → TX → EOM snapshot 与 CDC

### 5.1 AXI/control 域到 TX 域

1. `config_loader` 在 AXI clock 域读取16-word record，检查 header、metadata、
   reserved bits、sequence mirror 和 CRC；
2. 校验成功后更新稳定 active config，并翻转 `cfg_update_toggle_axi`；
3. `cdc_toggle_sync` 将该 toggle 同步到 `txusrclk2`，生成单周期
   `cfg_update_pulse_tx`；
4. TX域只在该 pulse 到来时一次性捕获 repeat、HEAD、gap、EOM、phase、loop、
   pattern length 和 configured pattern；
5. active TX snapshot 在任务执行期间保持稳定，AXI/BRAM shadow 后续变化不会
   污染当前任务。

本轮 CDC 收口额外将 `cfg_valid_axi`、`eom_subdiv_log2`、软件 enable、soft reset、
`rate_apply_enable_blocked` 和 `eom_clock_safe` 分别同步到 TX 域，再组合成
TX域本地控制条件，避免把跨域组合逻辑直接放在同步器输入前。

### 5.2 TX 域到 EOM 域

当 pattern engine 接受任务时，`engine_start_accept_pulse_tx` 作为 EOM
`task_request_pulse_tx`：

1. TX域 `tx_eom_window_generator` 捕获完整 EOM task bundle；
2. 捕获后翻转 `request_toggle_tx`，并保持 snapshot 不变；
3. EOM域用两级同步器接收 request toggle；
4. EOM域一次性复制稳定 bundle 到 `*_local` 寄存器；
5. `tx_eom_geometry_precompute` 在 EOM域计算 geometry；
6. geometry 完成后 EOM域翻转 `ack_toggle_eom`；
7. ack同步回TX域后，`geometry_armed_tx=1`，TX侧确认 geometry 有效；
8. TX域再翻转 `armed_seen_toggle_tx`，闭合第二个确认环；
9. EOM状态机随后等待共同TX/EOM边界，而不是让多位 geometry 直接跨域进入
   实时比较器。

### 5.3 完成返回

EOM窗口结束时，EOM域翻转 `done_toggle`。该 toggle 经 `cdc_toggle_sync`
回到TX域成为 `eom_done_pulse_tx`，供 pattern engine 完成一次性EOM事务。

## 6. TX第一笔word与EOM tick 0共同边界

TXUSRCLK2和EOM clock来自同一个MMCM的零相位 sibling outputs。当前逻辑不再
把TXUSRCLK2作为普通数据在EOM域采样，而是在EOM域使用 modulo-K 计数器标识
共同边界。

共同启动流程为：

```text
B0：EOM域在共同边界后置位 tx_start_level 请求
 ↓
B1：TX域在下一个共同边界采样该level并进入armed/running准备状态
 ↓
B2：TX第一笔word注册到txdata/valid_mask
    同一边界生成task_zero_pulse_eom，task_tick_counter_eom=0
```

因此 EOM geometry 的 tick 0 与实际任务第一笔 TX word 使用同一个边界。该机制
与软件 start、配置提交或 geometry 开始时刻不同，避免EOM相对真实TX输出提前。

## 7. 本轮CDC修改前后的区别

### 7.1 修改前

修改前，raw `gt_ready`、`eom_clock_safe`、GPIO enable、soft reset 和
`rate_apply_enable_blocked` 先组合成安全条件。该 raw 条件同时参与：

- 物理 `eom_out` 门控；
- TX侧 `tx_abort` / reset pipe 的异步断言；
- EOM侧 `clock_safe_pipe` 的异步清零；
- geometry/state reset条件的形成。

这种结构虽然可以快速关闭输出，但把跨域组合安全条件送入异步 reset/synchronizer
控制树，容易形成 recovery/removal、LUT驱动reset、组合逻辑位于同步器之前及高扇出
reset路径。高层行为可概括为：raw安全条件既负责关输出，也参与内部状态清理。

### 7.2 修改后

修改后将“物理立即安全关闭”和“内部状态恢复”明确分开：

```text
raw safety condition
├─→ async_output_safe
│   → 组合门立即强制 eom_out = 0
│
└─→ 各控制信号先同步到TX域
    → 形成TX域 eom_operating_safe_tx / eom_task_abort_tx
    → clock_safe经两级同步进入EOM域
    → 在EOM clock边沿复位geometry、snapshot handshake和window state
```

对应的“修改前/修改后”流程图为：

```text
修改前：

raw gt_ready / eom_clock_safe / enable / soft-reset / apply_blocked
                         │
                         ├────────────→ 物理 eom_out 门控
                         │
                         └→ 异步reset/clock-safe pipe
                            → 内部geometry/state reset条件
                            → recovery/removal与组合reset风险


修改后：

raw safety condition
      ├──────────────────────────────→ 立即强制 eom_out=0
      │                                  （时钟停止也能关闭）
      │
      └→ enable/soft-reset/apply/clock-safe分别同步到TX域
         → TX域本地安全状态与abort
         → 两级同步进入EOM域
         → EOM域时钟边沿清理geometry/state/handshake
```

严格按当前RTL实现，内部EOM状态寄存器没有由raw安全组合直接驱动异步CLR/R/S；
它们在 `eom_clk` 域内根据同步后的 `eom_reset_sync` 清零。因此“异步断言、同步释放”
更准确地体现为：外部物理输出可异步立即关闭，内部状态按目标时钟域同步恢复；
而GT派生时钟域的本地reset pipe仍采用异步断言、同步释放结构。

## 8. apply_blocked、clock_safe、GT ready和MMCM reset变化

### 8.1 `apply_blocked`

修改前，`rate_apply_enable_blocked` 可作为raw组合条件进入TX enable/reset路径。

修改后：

- GT control域先生成寄存的 `apply_enable_blocked_ctrl_reg`；
- `laser_tx_core` 再通过 `rate_block_meta/rate_block_tx` 同步到TX域；
- TX域使用 `rate_block_tx` 阻止新任务、abort当前EOM事务并清除运行状态；
- raw `rate_apply_enable_blocked` 只保留在 `async_output_safe` 中，用于时钟可能停止时
  立即关闭物理EOM输出。

### 8.2 `clock_safe_pipe`

修改前，EOM域 `clock_safe_pipe` 带 `negedge clock_safe` 异步清零。

修改后，结构为：

```text
eom_operating_safe_tx
→ clock_safe_meta
→ clock_safe_sync
→ eom_reset_sync = !clock_safe_sync
```

`ASYNC_REG`和`SHREG_EXTRACT=NO`用于固定两级同步器语义。raw安全组合不再作为
该同步器的D输入或内部状态异步reset，只作为 `eom_out` 最末级安全门。

### 8.3 GT ready / TXRESETDONE

GT wrapper中：

- `txresetdone_native` 和 GT Wizard `tx_fsm_reset_done` 分别经过TX域两级同步；
- 两者在TX域寄存后形成 `txresetdone_tx`；
- control域再同步该结果形成 `txresetdone_sync`；
- `gt_ready_effective_ctrl` 先寄存为 `gt_ready_effective_ctrl_reg`，再同步到TX域；
- EOM和TX engine使用TX域的ready条件，不再让control域组合结果直接驱动多处TX逻辑。

这会让ready生效或失效的内部确认增加少量目标域时钟周期，但不会改变ready的逻辑
含义。EOM物理输出关闭不依赖这些同步周期，因为raw gate仍保留。

### 8.4 MMCM reset

修改前：

```text
tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate
```

为组合OR。

修改后，control域寄存该OR结果到 `tx_mmcm_reset_ctrl`，再驱动MMCM reset。
这去掉了跨层组合reset控制，并让MMCM reset的改变发生在明确的control clock边沿。
代价是reset控制增加一个control clock周期；PLL/MMCM参数和DRP序列没有改变。

## 9. reset、abort和unsafe场景的当前响应

| 场景 | 物理 `eom_out` | TX/EOM内部状态 |
|---|---|---|
| `tx_rst=1` | raw gate立即拉低 | TX域清除snapshot/request；EOM域随后同步复位 |
| software soft reset | raw GPIO条件立即拉低 | soft reset同步到TX域后abort任务并复位TX sequence/EOM事务 |
| software enable=0 | raw gate立即拉低 | enable同步到TX域后阻止启动、abort未完成任务 |
| `rate_apply_enable_blocked=1` | raw gate立即拉低 | `rate_block_tx`生效后阻止启动并清除进行中的事务 |
| GT not-ready | raw gate立即拉低 | TX域ready失效后停止engine并abort EOM请求/窗口 |
| MMCM失锁/`eom_clock_safe=0` | raw gate立即拉低，即使EOM clock停止 | `clock_safe`恢复并同步后，EOM域清除旧geometry/state；不会重开旧窗口 |
| pattern engine abort | EOM输出保持/转为低 | TX握手状态清除；新任务需重新snapshot和arm |

关键安全保证是：物理输出关闭不等待EOM clock；内部状态清理则不再使用raw组合安全
条件直接扇出到状态寄存器，而在所属时钟域内完成。恢复后必须经过新的snapshot、
geometry计算、ack和共同边界流程，旧窗口不会自动重新打开。

## 10. 保持不变与有意变化

### 10.1 保持不变

- EOM geometry公式和selected pattern定位；
- `eom_enable`、global index、lead/trail配置语义；
- phase-major、repeat-minor编号；
- 每个任务最多一次EOM；
- loop不重复EOM；
- TX第一笔word与EOM tick 0共同边界；
- EOM tick与profile K关系；
- 16-word配置、CRC和原子提交协议；
- AXI地址和GPIO control bitfield；
- 外部 `eom_out` / `eom_out_0` 端口；
- TX `PIPELINE_LATENCY=0`；
- `txdata/valid_mask`对齐和pattern sequence语义。

### 10.2 有意变化

```text
Functional behavior changed intentionally
```

有意变化仅限控制和安全实现：

- 内部状态清零从raw组合/异步reset控制树迁移到目标时钟域同步处理；
- reset释放由目标域时钟确认；
- `apply_blocked`、clock-safe、ready等安全条件增加同步确认延迟；
- 物理输出立即关闭与内部状态复位解耦；
- MMCM reset组合OR改为control域寄存；
- GT ready/TXRESETDONE采用分级同步和域内寄存组合。

这些变化不会移动有效EOM窗口的geometry边界，也不会增加TX数据pipeline；但unsafe
发生后内部状态何时被观察到清零，改为取决于相应目标域时钟边沿。

## 11. 涉及文件

### 11.1 EOM功能引入与当前实现RTL

| 文件 | 作用 |
|---|---|
| `laser_tx_core/config_loader.v` | 解码16-word配置，发布稳定active config |
| `laser_tx_core/laser_tx_core.v` | AXI→TX配置快照、enable/safe同步、EOM与pattern engine集成 |
| `laser_tx_core/tx_eom_geometry_precompute.v` | 在EOM域顺序计算selected pattern geometry |
| `laser_tx_core/tx_eom_window_generator.v` | TX↔EOM握手、共同边界、window输出和done toggle |
| `laser_tx_core/pattern_tx_engine.v` | 任务接受、共同启动、第一笔TX word和一次性EOM配合 |
| `laser_tx_core/cdc_toggle_sync.v` | 配置、done等单bit toggle CDC |
| `laser_tx_core/sync_signal_gen.v` | 保留SOA/ACQ；EOM已从该模块移出 |
| `laser_gt_tx_profile0.v` | GT ready、TXRESETDONE、MMCM reset、EOM clock/safe来源 |
| `rtl/laser_gt_rate_control_mux.v` | profile相关EOM K/subdivision与apply block |
| `rtl/laser_tx_board_top.v` | EOM clock/safe/top-level端口连接 |

### 11.2 Testbench与回归脚本

| 文件 | 覆盖内容 |
|---|---|
| `tb_tx_eom_v2.sv` | K=16/8/4/1、geometry、snapshot稳定、共同tick-0、单次EOM、loop、abort、安全关闭和恢复 |
| `tb_pattern_tx_engine_timing.sv` | pattern engine启动、first word、phase/repeat/gap及EOM握手 |
| `tb_config_loader_v2.sv` | EOM字段、record/CRC及配置解码 |
| `scripts/run_tx_sequence_v2_regression.tcl` | 编译并运行EOM、engine、loader自检 |
| `scripts/test_tx_sequence_v2_protocol.py` | 软件协议字段范围、global EOM index及16-word布局 |
| `scripts/run_tx_sequence_v2_artifact_build.tcl` | OOC/top/route及EOM runtime clock/report检查 |
| `scripts/gt_profile0_impl_pre.tcl` | K=16/8/4/2/1的runtime TX/EOM时钟关系 |

### 11.3 规格和报告

- `docs/bram_config_map.md`
- `docs/tx_phase_repeat_gap_global_eom.md`
- `docs/udp_protocol.md`
- `docs/debug_reports/53_tx_sequence_v2_low_speed_validation_report.md`
- `reports/tx_sequence_v2_artifact_build/`

## 12. 仿真、实现证据与未验证边界

### 12.1 既有证据

现有回归记录包含：

```text
PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS
TX_EOM_V2_REGRESSION_PASS
CONFIG_LOADER_V2_REGRESSION_PASS
```

`tb_tx_eom_v2`覆盖：

- K=16/8/4/1；
- 63/127-bit pattern；
- mixed gap、repeat=1/2/5/16；
- phase enable/disable；
- global index首、中、末位置和越界抑制；
- lead clamp和trail；
- source bundle在request busy期间变化不污染snapshot；
- TX第一笔word与task tick 0同一时刻；
- 每任务恰好一次EOM；
- loop运行时EOM不重复；
- clock unsafe后物理输出立即为低；
- 恢复后旧EOM窗口不重新打开。

本轮CDC收口后的既有routed报告记录：

| 项目 | 结果 |
|---|---:|
| Setup WNS | +0.613 ns |
| Setup TNS | 0 |
| Hold WHS | +0.050 ns |
| Hold THS | 0 |
| Setup/Hold failing endpoints | 0 / 0 |
| DRC Error | 0 |
| Unrouted nets | 0 |
| `no_clock` | 0 |
| `unconstrained_internal_endpoints` | 0 |
| 用户RTL Critical CDC | 0 |

完整CDC报告仍包含vendor PS/AXI/ILA/debug内部结构的Critical项，不能据此宣称整个
器件的原始 `report_cdc` 为零。Methodology仍有vendor GT/debug告警和
`eom_out_0`缺少外部output delay；后者需要真实外部接收器时序规格，不能猜测。

### 12.2 本次文档任务

```text
Tests were not run.
Synthesis/implementation was not run.
Bit/LTX/XSA/ELF were not generated by this documentation task.
Hardware test was not run.
```

### 12.3 当前风险

1. 尚未使用新BIT/LTX/ELF完成EOM上板波形验证；
2. 尚未以外部仪器确认 `eom_out_0` 实际脉宽、lead/trail和GPIO延迟；
3. `eom_out_0`外部output delay仍未定义；
4. 必须上板覆盖reset、abort、GT not-ready、MMCM失锁和动态rate apply期间的立即拉低；
5. 必须确认恢复后的第一项新任务能重新snapshot/arm，且旧任务不会产生stale EOM；
6. ILA只能证明内部数字事件，不能替代外部GPIO电气和时序测量。

## 13. 结论

```text
EOM外部功能语义未改变；
本轮主要改变的是EOM内部CDC、复位和安全关闭实现；
物理输出仍可立即安全拉低；
内部状态恢复改为目标时钟域内同步处理；
Hardware test was not run.
```

更具体地说，TX Sequence V2建立的任务级selected-pattern EOM、lead/trail、
单次触发和共同tick-0机制保持不变。本轮把raw安全条件的职责收敛为物理输出最后一级
立即门控，并把geometry、snapshot handshake、window state以及相关ready/reset控制
迁移到明确的目标时钟域同步路径。由此消除了用户RTL关键CDC告警，同时避免unsafe
期间EOM卡高；但最终板级结论仍需真实硬件波形验证。

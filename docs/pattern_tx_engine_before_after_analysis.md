# `pattern_tx_engine` 修改前后差异与原因分析

## 文档范围与证据边界

本文只分析 `pattern_tx_engine.v` 的结构变化、时序改善原因和功能一致性，不提出新的 RTL 改写，也未修改任何 RTL 或 testbench。

分析依据如下：

- 修改前 RTL 的诊断留档及关键组合循环片段；
- 当前 `pattern_tx_engine.v`；
- `tb_laser_tx_core.sv` 的自检参考模型；
- 修改前诊断数据和当前综合、布局布线报告；
- 当前 `sync_signal_gen.v` 的同步输出派生关系。

工程中没有保存一份可独立编译的修改前 RTL 副本，也没有可用于逐行 diff 的版本历史。因此，本文能够严格确认结构和 QoR 差异，但不能给出修改前文件的稳定行号。修改前代码位置以信号名和逻辑片段定位；修改后位置以当前文件行号定位。涉及未被现有 testbench 覆盖的行为，均明确标为“需要进一步确认”，不把回归通过等同于形式等价证明。

---

## 1. 总体结论

修改前的根本问题不是某个孤立比较器或 Vivado 的 phys-opt 策略，而是一个组合 `for` 循环在 64 个 lane 内用 blocking assignment 逐 bit 推进发送状态。`running`、`patterns_done`、pattern rollover、gap 进入/退出和 phase 结束判断都会由 lane `n` 传播到 lane `n+1`。综合展开后得到的是 **64-lane 串行 next-state 依赖链**，而不是 64 个相互独立的并行 lane。

修改后采用 **word-level phase position + parallel lane generation + pattern cursor**：每拍先在 word 级计算 phase 剩余长度和 gap 相对边界，再让 64 个 lane 只做并行区间选择；最后以 word 为单位一次更新 `phase_pos` 和 `pattern_cursor`。被消除的不是“几行代码”，而是跨越 64 lane 的串行依赖深度。

这解释了前后 QoR 的数量级变化：综合 WNS 从 `-176.773 ns` 变为 `+11.046 ns`，TNS 从 `-35096.727 ns` 归零，engine LUT 从 `25,701` 降到 `7,170`。当前 routed implementation 在 20 ns 周期下 setup WNS 为 `+5.594 ns`，hold WHS 为 `+0.040 ns`，没有 failed/unrouted net。

本次结构调整没有增加 pipeline 级。`txdata`、`valid_mask`、phase 状态和 phase-start pulse 仍在同一个 `txusrclk2` 上升沿提交，因此 start-to-first-word 延迟及各输出之间的寄存边界没有改变。

功能一致性结论分两层：

- 对现有 PRBS6、direct 127-bit、非法配置三个自检场景，逐 lane 数据、逐 lane mask、EOM、gate、trigger、phase 范围和完成行为均已通过，未发现功能差异；
- 对 loop、多组最小/边界配置和专门的边界对齐场景，当前 testbench 没有完整的定向覆盖，故只能认为 RTL 设计意图一致，尚不能宣称已经穷尽证明。

---

## 2. 修改前 RTL 结构分析

### 2.1 64 次循环内推进全部状态

修改前组合逻辑先把寄存状态复制到临时变量，然后在一个 64 次循环中逐 lane 更新这些临时变量。其结构可概括为：

```verilog
t_running             = running;
t_patterns_done       = patterns_done;
t_pattern_bit_idx     = pattern_bit_idx;
t_gap_remaining       = gap_remaining;
t_phase_start_pending = phase_start_pending;
t_phase_offset        = phase_offset;

for (lane = 0; lane < 64; lane = lane + 1) begin
    if (t_running && enable) begin
        // phase start、gap、pattern bit、rollover、phase end
        // 均在此处更新上述 t_* 临时状态
    end
end
```

因此，一个时钟周期内不只是生成 64 个数据 bit，还模拟了最多 64 次串行状态转移。

### 2.2 blocking assignment 建立 lane 间真实依赖

循环中的 `t_* = ...` 是 blocking assignment。Verilog 语义要求 lane `n+1` 看到 lane `n` 刚刚写入的新值。例如，当某 lane 完成一个 pattern 时，它会更新 `t_pattern_bit_idx` 和 `t_patterns_done`；下一 lane 必须根据更新后的值决定是继续 pattern、进入 gap、结束 phase，还是从下一 phase 取数。

这不是综合器可以任意并行化的代码风格问题，而是 RTL 明确表达的数据依赖：

```text
lane 0 next-state
  -> lane 1 next-state
  -> ...
  -> lane 63 next-state
```

### 2.3 串行传播的控制量

修改前以下决策都处于该依赖链内：

- `t_running`：序列是否还在运行；
- `t_patterns_done`：当前 phase 已完成多少个 pattern；
- `t_pattern_bit_idx`：当前 pattern 内 bit 位置及 rollover；
- `t_gap_remaining` / gap inserted：是否进入、停留或退出 gap；
- phase-end：是否完成当前 phase；
- `t_phase_offset`：是否切到下一相位或回卷；
- loop/non-loop：是否重新开始或结束序列。

任一低位 lane 触发 pattern rollover、gap 或 phase boundary，都可能改变其后所有 lane 的选择路径。

### 2.4 `txdata[n]` / `valid_mask[n]` 不是独立 lane

表面上循环每次只写 `txdata_next[lane]` 和 `mask_next[lane]`，但写入内容由当时的 `t_running`、gap 状态、pattern index 和 phase 状态决定，而这些临时状态已经包含前面所有 lane 的计算结果。因此：

```text
txdata[63]、valid_mask[63]
  <- lane 63 入口状态
  <- lane 62 计算结果
  <- ...
  <- lane 0 计算结果
  <- 当前拍状态寄存器
```

综合器不能将其实现成 64 份等深度并行逻辑，只能展开为大量级联 mux、比较、加减和 carry 节点。

### 2.5 最差路径为何是 `patterns_done_reg[4] -> txdata_reg[63]`

修改前综合检查点给出的最差路径为：

```text
Source      : u_pattern_tx_engine/patterns_done_reg[4]
Destination : u_pattern_tx_engine/txdata_reg[63]
Data delay  : 196.362 ns
WNS         : -176.773 ns
```

`patterns_done_reg[4]` 会影响当前 pattern 是否为最后一次 repeat；该判断又影响是否开始 gap、是否结束 phase、是否更新 phase offset，以及后续 lane 从哪个 pattern bit 取数。到达高位 `txdata[63]` 前，这个影响要穿过大量展开后的 lane 状态选择，所以该路径正是 TX word generation 串行依赖的直接证据，而不是偶然落在 engine 内部的一条无关路径。

---

## 3. 修改后 RTL 结构分析

### 3.1 用 word 级 `phase_pos` 替代 per-lane 状态推进

当前实现以 `phase_pos` 表示下一 word 起点在当前 phase 中的绝对位置，并计算：

```verilog
phase_remaining = phase_total_active - phase_pos;
remaining_rel = (phase_remaining >= 40'd64) ?
                7'd64 : phase_remaining[6:0];
```

位置：`pattern_tx_engine.v:50-51,151-153`。

一拍内只需要对 `phase_remaining > 64`、`== 64`、`< 64` 三种 word 级情况做一次状态更新，不再为每个 lane 重复推进完整 FSM。这直接消除了原来的 64 级 next-state 链。

### 3.2 active 配置只在 start 接受时锁存

`len_active`、`phase_shift_active`、`loop_active`、`phase_total_active`、`gap_start_active`、`gap_end_active` 和 `gap_present_active` 在 `start && enable && pattern_valid` 分支锁存，位置为 `pattern_tx_engine.v:326-348`。

准确地说，这是在**序列开始**时锁存，而不是每个 phase 都重新采样一次；其后所有 phase 共享这组 active 配置。每个 phase 切换时只更新 phase offset、`phase_pattern`、`pattern_cursor` 和 `phase_pos`。这样既防止发送期间外部配置变化进入大组合锥，也避免配置控制量反复参与每 lane 选择。

### 3.3 以 shift/subtract 计算 `x*63`、`x*127`

当前实现：

```verilog
(pattern_len == 8'd63) ? ((repeat_wide << 6) - repeat_wide) :
                         ((repeat_wide << 7) - repeat_wide);
```

gap 起点也采用相同形式，位置为 `pattern_tx_engine.v:55-65`。由于 `63=64-1`、`127=128-1`，该写法只需移位和减法，不需要通用乘法器、divider 或 modulo 网络。

### 3.4 利用“phase 至少 63 bit”限制跨界数量

合法 pattern 长度为 63 或 127，且 `repeat_cycles >= 1`，所以 phase 总长度至少为 63 bit。一个 64-bit word 最多跨越一个 phase boundary，不可能在同一 word 内完整越过两个 phase。

当前 lane 逻辑因此只需在“当前 phase”和“可能的下一 phase”两组数据之间选择，位置为 `pattern_tx_engine.v:206-234`。这把任意长度串行步进问题约束为固定的两段式 word 拼接问题。

### 3.5 将绝对 gap 区间压缩为 7-bit 相对边界

当前实现每拍只计算一次当前 phase gap 与 word 窗口的交集：

```text
current_gap_start_rel, current_gap_end_rel in 0..64
next_gap_start_rel,    next_gap_end_rel    in 0..64
```

位置为 `pattern_tx_engine.v:167-194`。lane 内不再比较 40-bit 绝对 phase 位置，也不再递减 gap 状态，只比较 7-bit lane index 是否落在 `[gap_start_rel, gap_end_rel)`。

### 3.6 64 个 `txdata` / `valid_mask` lane 并行生成

当前 `for` 循环位于 `pattern_tx_engine.v:206-234`。循环内没有修改 `phase_pos`、cursor、running、done、phase offset 等跨 lane 状态；每个 lane 只读取同一组已算好的边界和 pattern window，完成：

- 当前 phase、下一 phase或无效尾部选择；
- gap 区间选择；
- 对应数据 bit 选择。

lane `n+1` 不再依赖 lane `n` 的计算结果，因此综合器可以生成 64 份并行选择逻辑。

### 3.7 用 127-bit periodic pattern cursor 代替动态地址计算

`pattern_cursor[0]` 始终表示下一个有效 pattern bit。127-bit 模式直接保存一个完整周期；63-bit 模式把周期扩展到 127 bit：

```verilog
{base_pattern[0], base_pattern[62:0], base_pattern[62:0]}
```

位置为 `pattern_tx_engine.v:46-50,66-70`。`rotate_sequence` 通过拼接、移位和固定窗口取得推进后的 cursor，位置为 `pattern_tx_engine.v:72-94`。lane 内不再计算 `(phase_offset + bit_idx) % pattern_len`，也不再为每个 lane 做动态 pattern address rollover。

### 3.8 cursor 只按 valid bit 数推进

当前 word 的推进量为 `64-current_gap_width`；跨入下一 phase 时使用 `gap_bits_before()` 从已消费 bit 数中扣除 gap bit，位置为 `pattern_tx_engine.v:97-110,256-289`。

因此 gap lane 输出零且不消费 pattern 数据。gap 后第一个 valid lane 从 gap 前游标的连续下一 bit 开始，与原来的 pattern bit index 暂停语义一致。

### 3.9 输出与状态仍在同一个时钟边界提交

唯一的输出/状态提交块位于 `pattern_tx_engine.v:303-381`。运行分支中：

```verilog
txdata           <= txdata_calc;
valid_mask       <= valid_mask_calc;
phase_active     <= word_active_calc;
phase_start_pulse<= phase_start_calc;
phase_pos        <= phase_pos_next;
pattern_cursor   <= pattern_cursor_next;
```

这些信号在同一个 `posedge clk` 注册，没有插入额外 pipeline。`sync_signal_gen.v` 又以组合方式从已注册的 `valid_mask`、`phase_active` 和 `phase_start_pulse` 生成 EOM/SOA/ACQ，因此同步输出仍与当前 TX word 对齐。

---

## 4. 修改前后关键差异表

| 项目 | 修改前 | 修改后 | 对时序的影响 |
|---|---|---|---|
| 状态推进方式 | 64-lane 循环内逐 bit 更新 `t_*` 状态 | 每拍一次更新 `phase_pos`、phase 和 cursor | 消除跨 64 lane 的串行状态深度 |
| 64-bit word 生成方式 | 边生成 lane 边改变后续 lane 的入口状态 | 先做 word 级边界判断，再并行生成 lane | lane 逻辑可并行综合 |
| pattern address 计算 | 每 lane 根据 bit index/phase offset 动态选择和 rollover | 127-bit periodic cursor，bit 0 为下一有效 bit | 去除重复动态地址与 rollover 网络 |
| gap 处理方式 | 循环内进入、递减和退出 gap 状态 | 每 word 把绝对 gap 压缩为 0..64 相对区间 | 宽比较只做一次，lane 内仅为 7-bit 区间选择 |
| phase boundary 处理 | 任意 lane 内可触发并继续串行传播 | word 级判断 `remaining > / == / < 64`，最多拼接下一 phase | 将边界控制从 64 次降为一次 |
| `txdata` 生成 | 依赖此前所有 lane 的临时状态 | 每 lane 从预对齐 pattern window 并行选 bit | 高位 lane 不再承受低位 lane 的逻辑深度 |
| `valid_mask` 生成 | 依赖串行 gap/phase/running 状态 | 由相对 gap 和 phase 边界并行生成 | 去除 mask 的串行传播链 |
| pattern rollover | 循环中逐 bit 判断 pattern 末尾 | cursor 按本 word valid bit 数统一旋转 | rollover 次数和 mux 复制显著减少 |
| modulo/divider | 动态索引/回卷语义分散于 lane | 无 `%` 和除法；长度乘法用 shift/subtract | 避免昂贵通用算术网络 |
| per-lane dependency | 存在，lane `n+1` 依赖 lane `n` | 不存在跨 lane 状态写后读依赖 | 关键组合深度由 O(64) 变为固定 word 级路径 |
| 新增 pipeline | 无 | 无 | start-to-first-word 和输出对齐不因流水级改变 |
| 资源使用 | engine 25,701 LUT | 综合 7,170 LUT；route 后 7,017 LUT | 大量重复 mux/比较/carry 被消除 |

核心变化不是简单减少代码，而是把“每个 bit 串行推进状态”的模型改成“先在 word 级判断边界，再并行生成 lane”的模型。

---

## 5. 时序改善原因分析

### 5.1 修改前：为何出现约 -176 ns WNS

`patterns_done` 决定当前 repeat 是否结束，进而决定 gap、phase end、phase offset、running 和下一 pattern 数据源。由于这些决策在 blocking-assignment lane 循环中反复发生，`patterns_done_reg[4]` 对 `txdata[63]` 的影响必须穿过多级 `t_running`、data/mask mux、比较器和 carry chain。

修改前数据路径延迟为 `196.362 ns`，而时钟要求仅 `20.000 ns`，路径接近十个时钟周期。这不是普通布线拥塞造成的几纳秒超限，而是 RTL 所要求的组合依赖本身过深。256 个 failing endpoints 和 `-35096.727 ns` TNS 也说明问题覆盖整个 word generation 锥，而非单个局部端点。

phys_opt 的 replication、re-place、pin swap 可以降低扇出和路由延迟，却不能改变 lane `n+1` 必须等待 lane `n` 的逻辑语义。它只能反复优化依赖链的局部实现，不能把串行链变成并行结构，所以无法根治该问题。

### 5.2 修改后：为何路径和资源同时下降

修改后，lane 只读取预先计算的相对边界、`remaining_rel` 和已经对齐的 pattern vector。64 个 lane 的逻辑深度相近，不再从 lane 0 累积到 lane 63。状态更新则集中为一次 40-bit phase 位置运算和一次 cursor rotation。

因此最终最差路径已转移为：

```text
phase_pos_reg[17] -> pattern_cursor_reg[76]
Data path delay: 13.847 ns
Logic: 2.681 ns
Route: 11.166 ns
```

这条路径仍位于 engine 内，但它是固定深度的 word-control/cursor-update 路径，不再是跨 64 lane 的串行链。13.847 ns 数据延迟可在 20 ns 时钟要求内完成，最终 setup WNS 为 `+5.594 ns`。

LUT 从约 25k 降至约 7k 的原因也相同：原实现为每一个 lane 复制了运行判断、repeat/rollover、gap、phase-end 和多路选择逻辑，并将其级联；当前实现把宽控制计算提升到 word 级共享，lane 内只保留并行选择，重复逻辑和级联 mux 同时减少。

ILA 仍带来约 3.3k LUT 及布线压力，但修改后最差路径的起终点都在 engine 的 `phase_pos`/cursor 更新中，ILA 不是本次原始 -176 ns 违例的根因。

---

## 6. 功能等价性检查

| 行为 | 一致性判断 | 依据与边界 |
|---|---|---|
| 63/127-bit pattern period | 已保持 | `len_active` 仍为 63/127；63-bit cursor 周期扩展，127-bit cursor 保存完整周期；PRBS6 和 direct127 逐 lane 自检通过 |
| phase range | 已保持 | phase offset 最后值分别检查到 62、126，且 direct127 每 word 检查不超过 126 |
| repeat 行为 | 已保持于已测配置 | phase 总 pattern bit 数仍为 `repeat*len`；repeat=4、repeat=2 的 word 数和全流数据通过 |
| gap insertion | 已保持于已测配置 | gap 起点为 `insert_after*len`，总长加 `gap_len_bits`；5-bit、8-bit gap 的参考模型通过 |
| gap lane `txdata=0, valid_mask=0` | 已保持 | lane 循环显式赋零；两个场景逐 lane 对数据和 mask 做参考比较 |
| `eom_out = |valid_mask` | 已保持 | `sync_signal_gen.v` 直接归约；两个有效配置场景逐 word 检查 |
| SOA/ACQ gate 覆盖 phase 和 gap | 已保持于 PRBS6 场景 | gate 由 `phase_active` 派生，PRBS6 场景每个 active word 检查两者为高；没有单独的全-gap word 用例 |
| 每 phase start 一个 word-clock trigger pulse | 已保持于 PRBS6 场景 | `phase_start_calc` 与 word 同边沿注册；PRBS6 参考模型按 phase 起点检查 trigger |
| loop/non-loop completion | non-loop 已验证；loop 需进一步确认 | 两个发送场景均为 non-loop 并检查 done/word count；没有 loop testcase |
| start-to-first-word latency | 结构上未改变 | start 边沿清零输出并置 `running`，下一运行边沿提交首 word；无新增寄存级。若需周期级证据，应增加显式 latency assertion |
| TXDATA/mask/EOM/SOA/ACQ 对齐 | 已保持于现有场景 | data/mask/status 同边沿注册，同步输出组合派生；testbench 检查 EOM、gate、trigger 与当前 word |

未发现明确的功能 bug 或已证实的行为差异，因此不应再修改 RTL。但“现有回归通过”不等于全配置空间的形式等价；尤其 loop 和若干边界配置仍需补充验证。

---

## 7. Testbench 覆盖性评价

### 7.1 已覆盖内容

`tb_laser_tx_core.sv` 当前包含：

1. **PRBS6 场景**：63-bit pattern、63 个 phase、repeat=4、insert_after=2、gap=5；
2. **direct 127-bit 场景**：127-bit 直接 pattern、127 个 phase、repeat=2、insert_after=1、gap=8；
3. **invalid configuration**：`repeat_cycles=0`，检查 cfg error、error code 且 engine 不启动；
4. 两个有效场景均在每个 active word 内遍历 lane 0..63，逐 lane 检查 `txdata`；
5. 同样逐 lane 检查 `valid_mask`，因此 gap lane 和最终 partial word 也在参考模型内；
6. 两个有效场景逐 word 检查 `eom_out == |valid_mask`；
7. PRBS6 场景检查 SOA/ACQ gate；
8. PRBS6 场景按 phase 起点检查 ACQ trigger；
9. 检查最终 word count、done timeout 和 phase offset；direct127 还在运行中检查 phase 不超过 126；
10. direct127 长流会多次跨越 127-bit cursor 边界，因此 cursor rollover 已被数据参考模型实际覆盖；
11. non-loop 最后 partial word 已覆盖：PRBS6 总长度余 63 bit，direct127 总长度余 58 bit，尾部无效 lane 由逐 lane 模型检查。

### 7.2 覆盖不足及建议 testcase

建议增加以下定向用例或 coverage counter：

- **phase boundary 恰好落在 word 末尾**：现有长流可能经过该对齐关系，但 testbench 未设置独立断言证明 `phase_remaining == 64` 分支；建议用 phase 总长 64 的配置直接命中；
- **gap start / end 恰好位于 lane 0 或 lane 63**：现有 phase shift 会产生多种对齐，但没有明确覆盖点；应分别命中四个边界；
- **最短 63-bit phase**：`pattern_len=63, repeat=1, gap=0`，验证一个 word 同时含当前 phase 63 bit 和下一 phase 第 1 bit；
- **loop 模式**：跨越最后 phase 后回到 phase 0，检查数据、phase offset、trigger 以及 done 的定义；
- **direct 63-bit 和 PRBS7**：当前 RTL TB 没有覆盖这两个第一阶段板上配置；
- **无 gap、gap 在 pattern 尾部、较长 gap/全 gap word**：验证 gate 在 `valid_mask==0` 的整 word 上仍保持 high；
- **显式 start latency assertion**：从 engine start 到第一拍有效 word 的准确周期数；
- **enable 中途撤销**：检查输出清零、busy/running 退出及重新启动语义；
- **最大 `repeat_cycles`/`insert_after` 合法边界**：验证 40-bit 长度运算无溢出并符合配置约束。

若项目要求“修改前后严格等价”达到签核等级，建议保存修改前 RTL 快照并对有限状态空间做形式等价/属性验证；当前自检 testbench 能证明已覆盖场景一致，但不能替代全空间证明。

---

## 8. QoR 对比总结

### 8.1 Synthesis

| Metric | Before | After | Interpretation |
|---|---:|---:|---|
| Setup WNS | -176.773 ns | +11.046 ns | 从严重失败变为满足 20 ns setup |
| Setup TNS | -35096.727 ns | 0 ns | 所有 setup 负裕量清零 |
| Failing endpoints | 256 | 0 | 串行 word-generation 端点违例消失 |
| Engine LUT | 25,701 | 7,170 | 减少 18,531，约 72.1% |
| Core LUT | 26,081 | 7,236 | 减少 18,845，约 72.3% |

注：综合报告中的 hold 估计不是最终签核依据；最终 routed hold 已满足。

### 8.2 Routed implementation

| Metric | After route | 结论 |
|---|---:|---|
| Setup WNS / TNS | +5.594 ns / 0 ns | setup 满足 |
| Hold WHS / THS | +0.040 ns / 0 ns | 全设计最差 hold 满足；`clk_fpga_0` 组为 +0.051 ns |
| Failed/unrouted nets | 0 | 布线完成，无失败网络 |
| Worst data path | 13.847 ns | `phase_pos_reg[17] -> pattern_cursor_reg[76]`，满足 20 ns |
| Engine LUT | 7,017 | route 后进一步略有优化 |
| Core LUT | 7,078 | 与综合结果一致量级 |

当前 run 日志显示：

```text
phys_opt_design elapsed : 6 s
post-phys-opt estimate  : WNS +5.307 ns, TNS 0
route_design elapsed    : 3 min 15 s
route estimate          : WNS +5.587 ns, WHS +0.041 ns
```

这说明实现工具面对的是一个已具备正裕量、可正常布局布线的网表，而不是在超长结构性关键路径上反复尝试局部修补。`report_qor_suggestions` 只生成 retiming 建议，且明确因设计已满足 setup 而不生成 ML strategy；当前 50 MHz 条件下没有继续为时序改写 RTL 的必要。

---

## 9. 风险与后续建议

1. 当前结论基于 20.000 ns 周期，即 50 MHz temporary FCLK-based `txusrclk2`。这证明当前临时时钟下实现收敛，不代表最终 GT 用户时钟下自动满足。
2. 接入真实 GT Wizard 的 `txusrclk2` 并建立最终时钟约束后，必须重新运行 synthesis、implementation、timing summary、clock interaction 和 CDC 检查。
3. 如果最终频率提高后失败，优先顺序建议为：
   - 在 cursor rotation / word output 附近增加一层统一对齐 pipeline，并同步延迟 `valid_mask`、phase status、EOM、SOA、ACQ；
   - 减少 TX ILA probe 数和采样 depth，生产 bitstream 可移除非必要 ILA；
   - 对高扇出 word-control 条件做寄存器复制或在明确边界处寄存；
   - 根据最终 GT data width 和 user-clock 关系固定 pattern window，减少不必要的通用性。
4. 不应回退到 per-lane serial next-state propagation。那会重新建立 lane 0 到 lane 63 的组合依赖链。
5. 不应试图只靠更强的 `phys_opt_design` directive 解决结构性问题。物理优化可以改善实现，不能删除 RTL 明确要求的串行依赖。
6. 在继续优化前，应先补足第 7.2 节的定向用例。若未来加入 pipeline，testbench 必须同时验证所有同步输出的统一延迟和对齐。

综上，当前修改是一次计算模型重构：把 bit-serial next-state 展开改为 word-level boundary scheduling。它在不新增 pipeline 的前提下显著降低组合依赖深度和资源复制；现有回归与 QoR 报告均支持该方案。剩余工作重点应是边界覆盖和最终 GT 时钟下复签，而不是再次改写核心数据流。

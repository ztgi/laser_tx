# TX Sequence V2 production baseline 收口报告

## 1. 修改摘要

本轮在 `fix/gpio9-txusrclk2-monitor-ila` 的既有 dirty 工作区上完成三项收口：

1. 简化 Vitis/lwIP `WRITE_CONFIG` 对外参数，只移除已经 reserved/ignored 的
   `seed`、`prbs_order` 和 source-select；
2. 将 `soa_gate_out` 改为与 `eom_out` 共用同一个、已经安全门控的 EOM window；
3. 审计 GT adapter/XCI source management；由于 Vivado 2022.2 的标准 Wizard top
   不暴露运行时 `CPLLREFCLKSEL`，按 fail-closed 原则保留经过验证的 synth pre-hook。

同时保留并验证此前工作区中的 GPIO9/TXUSRCLK2 monitor ILA `probe15[9:0]`。
TX descriptor 地址、16-word布局、CRC、atomic commit、mailbox ABI和GT动态速率功能均未改变。

## 2. UDP/descriptor 修改前问题

PL内部PRBS/LFSR已被删除，但UDP仍要求用户提供 `seed`、`prbs_order` 和
PRBS/direct source-select。这三个值不会再决定生产数据，因此继续暴露会让用户误以为
PL仍能实时生成PRBS，也会增加参数数量错误的概率。

字段审计结果如下：

| 字段 | 当前生产用途 | 处理 |
|---|---|---|
| word1 legacy seed | reserved/ignored | 软件固定写0，不再作为UDP参数 |
| word2[12:5] legacy prbs_order | reserved/ignored | 软件固定写0，不再作为UDP参数 |
| word2[15] legacy source-select | reserved/ignored | 软件固定写0，不再作为UDP参数 |
| repeat_cycles | phase内重复调度 | 保留 |
| gap_len_bits[] | 各repeat之间独立gap | 保留 |
| pattern_len_127 | 63/127-bit周期长度 | 保留，UDP名称为`pattern127` |
| phase_shift_en/loop_en | phase扫描和loop语义 | 保留 |
| head_delay_bits | phase HEAD | 保留 |
| EOM enable/index/lead/trail | 全局EOM窗口 | 保留 |
| pattern words 9..12 | 唯一configured pattern数据源 | 保留 |

新语法为：

```text
WRITE_CONFIG index repeat pattern127 phase loop head \
  gap0 ... gap(repeat-2) \
  eom_enable eom_global_index eom_lead_ticks eom_trail_ticks \
  pattern_low pattern_mid pattern_high pattern_top
```

`repeat=1`时不带gap参数。旧命令形状明确返回`ERR WRITE_CONFIG_ARGS`；这是有意的
CLI不兼容升级，但PL 16-word descriptor ABI没有变化。

## 3. UDP/descriptor 修改后结构

```text
UDP production parameters
  -> LaserConfig（只保留真实生产字段）
  -> laser_config_to_words()
       word1                 = 0
       word2[12:5], bit15    = 0
       其余生产字段           = 原bit位置
  -> words1..14 CRC32
  -> payload/CRC先写
  -> header/sequence最后atomic commit
  -> PL完整snapshot和CRC校验
```

动态rate descriptor的64-word CRC golden常量同步修正为`0xDCF3D1B2`。算法、覆盖范围
和硬件实现未改变；旧测试常量没有包含64-word descriptor的完整零填充尾部。

## 4. EOM/SOA 修改前问题

修改前 `soa_gate_out` 由 `sync_signal_gen` 中的 `phase_active` 驱动，而`eom_out`
由EOM geometry、selected global pattern和lead/trail得到。两个输出的窗口定义不同，
不满足“SOA使用当前EOM窗口”的板级需求。

## 5. EOM/SOA 修改后结构

`tx_eom_window_generator` 现在形成：

```verilog
eom_out      = eom_window & async_output_safe & clock_safe_sync;
soa_gate_out = eom_out;
```

因此二者完全同周期、同开始边界、同结束边界、同异步安全关闭行为。SOA不增加状态机、
pipeline或CDC，仅给已经形成的安全EOM输出增加一个负载。`sync_signal_gen`仍只生成：

```text
acq_trig_out = phase_start_pulse
acq_gate_out = phase_active
```

Functional behavior changed intentionally：SOA来源由phase gate改为EOM window。EOM
geometry、每任务最多一次EOM、selected pattern、lead/trail、共同tick-0、TX Sequence V2、
ACQ输出、外部端口名和XDC引脚均保持不变。

## 6. GT adapter/source-management 审计

当前生产结构保持：

```text
laser_gt_tx_profile0
  -> repository-owned gtwizard_0_adapter
  -> local-XCI-generated gtwizard_0_gt
  -> GTXE2_CHANNEL
```

检查结果：

| 项目 | 结果 |
|---|---|
| adapter/golden顶层端口 | 61个，名称、方向、宽度一致 |
| runtime CPLLREFCLKSEL | 透传到primitive；001=GTREFCLK0，011=GTNORTHREFCLK0 |
| GTNORTHREFCLK0 | routed net为`ad9528_out0_gt_refclk`，未接地 |
| QPLL shared clocks | 保留透传 |
| GTXE2_CHANNEL / COMMON | 1 / 1 |
| routed black boxes | 0 |
| imported/reference GT active source | 0 |
| native synthesis compile order | 仅`gtwizard_0_adapter.v` |
| runtime overlay clocks | 15 |

Vivado 2022.2由XCI生成的标准`gtwizard_0.v`虽有`gt0_gtnorthrefclk0_in`，但不暴露
当前生产所需的运行时`gt0_cpllrefclksel_in`。IP Packager的generic subcore引用不能在
不重新参数化/复制本地定制XCI的前提下，把该XCI实例直接变成adapter的managed child。
直接换成标准top会丢失001/011运行时选择，复制或手改generated HDL又违反XCI单一来源。

因此本轮没有为消除Sources GUI问号而牺牲功能，继续使用：

```text
STEPS.SYNTH_DESIGN.TCL.PRE = scripts/gtwizard_0_synth_pre.tcl
```

该hook只从当前仓库`laser_tx.gen`读取本地XCI output products；无`project_gtx`、外部
generated HDL或imported GT依赖。Sources GUI在普通source解析阶段仍可能显示GT child
未解析；综合/实现的实际层次、primitive和连接由新鲜routed DCP证明正确。

## 7. BD、外部接口、时钟复位和软件影响

GPIO9 ILA已有变更被纳入基线：`ila_laser_tx`从15个probe增至16个，新增
`probe15[9:0]=dbg_gpio9_tx_bus`，ILA clock仍为TXUSRCLK2，probe0..14保持不变。

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| BD module-reference端口 | 无GPIO9诊断bus | 新增10-bit debug-only输出 | 只增加ILA观察 |
| 外部板级端口 | EOM/SOA/GPIO6/GPIO9既有端口 | 名称、方向、宽度不变 | 无引脚变化 |
| AXI地址 | 既有地址 | 不变 | 软件地址不变 |
| descriptor BRAM | 4 KiB共享双口RAM | 不变 | PS/PL拓扑不变 |
| TX/EOM时钟 | 15个runtime overlay | 不变 | 无时钟周期修改 |
| reset | 既有本地域reset与安全门控 | 不变 | SOA复用EOM关闭条件 |
| HDL wrapper | 已由新鲜BD output products验证 | 文本接口匹配 | 无额外手工修改 |
| XSA/Platform/BSP | 本轮新XSA更新原platform | BSP重新生成 | ELF绑定本轮硬件 |

Clock/reset behavior unchanged，除SOA有意改用EOM现有安全输出语义。AXI address map
unchanged。SPI、GPIO控制bitfield、planner、mailbox和rate executor行为不变。

## 8. 回归与构建验证

执行结果：

| 验证 | 结果 |
|---|---|
| `python scripts/test_tx_sequence_v2_protocol.py` | 14项PASS |
| dynamic descriptor spec/golden CRC unittest | PASS |
| dynamic mailbox RTL simulation | `PASS: dynamic mailbox descriptor validation and locking` |
| TX Sequence V2 Vivado regression | PASS |
| pattern engine regression | `PATTERN_TX_ENGINE_TIMING_REGRESSION_PASS` |
| scope debug regression | `TX_SCOPE_DEBUG_OUTPUTS_REGRESSION_PASS` |
| EOM/SOA regression | `TX_EOM_V2_REGRESSION_PASS`，逐事件检查SOA==EOM |
| config loader regression | `CONFIG_LOADER_V2_REGRESSION_PASS` |
| GT adapter equivalence | PASS，61 ports |
| Refresh/BD validate/output products/OOC | PASS |
| top synthesis/implementation/post-route phys-opt | PASS |
| bitstream/LTX/XSA | PASS |
| Vitis platform update/managed clean build | PASS，16个production C source，`USER_OBJS`为空 |

Vitis应用compiler/link通过。platform/BSP构建仍打印Xilinx/legacy lwIP vendor source的
fallthrough/pragma提示；没有通过修改production代码隐藏这些提示。

## 9. QoR、CDC、Methodology和DRC

| Metric | 先前fresh结果（2026-08-05） | 本轮fresh结果（2026-08-09） | 解释 |
|---|---:|---:|---|
| Setup WNS | +0.782 ns | +0.238 ns | 均通过；变化包含ILA负载与实现非确定性，不单独归因于EOM/SOA |
| Setup TNS | 0 ns | 0 ns | PASS |
| Setup failing endpoints | 0 | 0 | PASS |
| Hold WHS | +0.054 ns | +0.054 ns | PASS |
| Hold THS | 0 ns | 0 ns | PASS |
| LUT | 未形成同配置可比快照 | 25,351 | 不宣称资源改善 |
| FF | 未形成同配置可比快照 | 30,718 | 不宣称资源改善 |
| RAMB36 / RAMB18 | 未形成同配置可比快照 | 68 / 2 | 当前实现值 |
| DSP | 未形成同配置可比快照 | 0 | 当前实现值 |

当前runtime约束为正式目标：TXUSRCLK 3.103 ns、TXUSRCLK2 6.206 ns、EOM 6.206 ns。
`no_clock=0`、`unconstrained_internal_endpoints=0`、unrouted nets=0、DRC Error=0。

Methodology仍保留真实warning：LUTAR-1 1项位于GT Wizard TX startup FSM；PDRC-190
12项位于dbg_hub；TIMING-9 1项；TIMING-18 2项对应未建模板外负载的EOM/SOA输出。
`check_timing`共记录6个低速控制/debug输出无output delay，没有用0 ns假约束掩盖。

CDC详细报告含910条Critical detail row；按层次过滤后全部位于ILA/debug/vendor/GT层次，
候选用户RTL Critical row为0。该分类不等于vendor CDC被waive，warning仍保留在原报告。
DRC另有3项dbg_hub PDCN-1569和1组RTSTAT-10 warning；无DRC Error。

本轮implementation仍出现13项`Project 1-840`，对象是BD生成的PS7、AXI、ILA、BRAM
等本地OOC DCP，而非外部/手工GT DCP。它们没有造成black box、缺约束或构建失败，
但仍是后续构建流可继续收口的非阻塞风险。

## 10. 产物与SHA-256

| 产物 | 路径 | SHA-256 |
|---|---|---|
| BIT | `reports/tx_sequence_v2_artifact_build/artifacts/laser_tx_board_top.bit` | `B349AF474FB9C6FA7674F600E45F009EDC6BBC23021F14AB2A583C0F66666D97` |
| LTX | `reports/tx_sequence_v2_artifact_build/artifacts/laser_tx_board_top.ltx` | `F6FBBA7B538A51009C8EAE2E0945160CD0AB7544C47243F906270AF7BBD221AC` |
| XSA | `reports/tx_sequence_v2_artifact_build/artifacts/laser_tx_board_top_tx_sequence_v2.xsa` | `937BE30912A982DCE298E657535DADF22A4EB65B79E077CBE0E5B22DFA8D9740` |
| ELF | `vitis_bringup/bringup/Debug/bringup.elf` | `8C6A4D8423B39900A0E4D8BB93A2268DE18D70C987F61D6354DC78525CD9A52B` |
| laser_tx_core OOC DCP | `laser_tx.runs/system_laser_tx_core_0_0_synth_1/system_laser_tx_core_0_0.dcp` | `38A664D8CA91927F5441E70F5BEB090143BA519736D758A2E8B87AB4D6149707` |

ELF size为text 264,815 bytes、data 3,536 bytes、bss 3,201,088 bytes。linker script
未修改；大BSS为既有应用结构，本轮没有新增大型buffer。

## 11. 功能等价性与有意变化

Expected system behavior unchanged：TX pattern、HEAD/gap/repeat/phase/wrap/loop、
data/valid对齐、EOM geometry、ACQ输出、动态rate、GT选择、descriptor ABI和AXI地址不变。

Functional behavior changed intentionally：

1. 旧UDP `WRITE_CONFIG`参数形状不再接受三个无效PRBS字段；
2. SOA由`phase_active`改为和EOM完全同周期；
3. 软件生成descriptor时reserved PRBS字段固定写0。

结论基于自检仿真、源码结构检查和新鲜综合实现；尚未进行本轮硬件下载或UDP上板回归。

## 12. Git基线与剩余风险

```text
OLD_MAIN=c71843add9ebba57089e9eb4edd3c006e39bbf39
OLD_FEATURE_BASE=e38aee7840e80bda7bccbec10af136a639e46ba5
NEW_BASELINE=包含本报告的提交（精确hash见该提交的git log和任务最终输出）
NEW_MAINLINE=mainline/tx-sequence-v2
```

剩余风险：

1. Sources GUI普通解析阶段仍可能显示GT generated child问号；正式build依赖仓库内pre-hook；
2. `Project 1-840`仍存在于本地BD IP OOC DCP加载流程；
3. BIT/LTX/XSA/ELF虽由同轮构建生成，但未下载到硬件；
4. 新UDP命令和EOM/SOA同周期行为仍需UART/UDP/ILA/板级输出验证；
5. 外部EOM/SOA负载没有output-delay模型，不能据此声明板级时序质量；
6. GT高速眼图、BER、外部光链路和长期稳定性不在本轮验证范围。

Hardware test was not run.

# AD9528 运行时 GTX 速率规划、mailbox 与安全执行链路实施报告

## 1. 本阶段目标与边界

本阶段实现第一版“PS 运行时规划 + descriptor mailbox + PL 通用执行器”链路。PS 根据用户输入速率选择已枚举的 AD9528、GT 和 MMCM 合法组合；PL 只执行经过版本、长度和 CRC 校验的 descriptor，不接收软件直接散写 GT/MMCM DRP 地址和数据。

现有固定 profile executor、`rate_id=0..11`、GPIO rate bitfield 和正式 supported list均保留。运行时路径不占用剩余固定 `rate_id`，也不把运行时计划自动加入正式 fixed profile 表。`current_rate` 的 legacy 语义没有被运行时 descriptor 冒充或覆盖。

`dynamic_runtime_rate_switch_board_verified=0`

## 2. 实施提交基线

| 阶段 | 提交 | 内容 |
|---|---|---|
| Stage 1 | `09d74d5` | PS 运行时 GTX rate planner |
| Stage 2 | `52adc1b` | 64-word descriptor 与独立 mailbox |
| Stage 3 | `bd7b30a` | 动态 GT/MMCM executor、资源仲裁和 rollback |
| Stage 4 | `3f72a79` | PS AD9528 动态事务协调器 |
| Stage 5 | `1e2e00b` | UDP `rate plan/set/status/abort` 集成 |

## 3. PS 运行时规划器

离线生成器输出器件合法集合，不输出未经验证的固定速率 profile。当前表包含 AD9528 配置 1319 项、GT tuple 240 项（CPLL 80、QPLL 160）和 MMCM recipe 63 项。运行时规划器遍历有限 GT tuple，反推参考时钟要求，再在排序后的 AD9528 表内执行邻近搜索；速率、误差和合法性判断使用整数/有理数运算。

十进制解析支持整数或最多三位小数的 Mbps。`rate plan` 为只读操作。规划结果包含 PLL 类型、参考时钟、CPLL DRP field image、TXOUT_DIV、MMCM DRP sequence、TXUSRCLK2 expected/tolerance 和 AD9528 transaction plan。

## 4. Descriptor 与 mailbox

descriptor version 为 1，固定占用 64 个有效 word，最多携带 16 项 MMCM DRP 写操作；magic 为 `0x31505452`。CRC 使用 CRC-32/ISO-HDLC：反射多项式 `0xEDB88320`，初值和 final xor 均为 `0xFFFFFFFF`，覆盖 word 0..63 并排除 CRC word 3，每个 word 按 little-endian 字节顺序输入。C/Verilog 常量由同一 Python 生成脚本维护。

PL 在 PREPARE 时复制完整 shadow descriptor，然后检查 magic、version、word count、MMCM count 和 CRC。校验通过后形成 active 副本，后续 executor 不再读取 shadow 区。PREPARE、REFCLK_READY、ABORT 和 ROLLBACK_READY 均使用 toggle event；忙时 toggle 会被消费，不会在事务结束后重放。

## 5. BD 与软件可见地址

| 外设 | 地址 | 范围 |
|---|---:|---:|
| pattern/config BRAM | `0x40000000` | 8 KiB |
| 主控制/状态 AXI GPIO | `0x41200000` | 64 KiB |
| GT status AXI GPIO | `0x40020000` | 64 KiB |
| AD9528 measurement AXI GPIO | `0x40030000` | 64 KiB |
| dynamic mailbox AXI GPIO | `0x40040000` | 64 KiB |
| dynamic descriptor BRAM | `0x42000000` | 4 KiB |

新增 AXI GPIO channel 1 为 4-bit PS→PL toggle，channel 2 为 32-bit PL→PS status；新增 descriptor Block Memory Generator 为 true dual-port，Port A 由 PS/AXI BRAM Controller 访问，Port B 由 mailbox reader 使用。旧 AXI 地址、SPI chip-select、外部板级端口和 PS MIO/EMIO 未改变。

新增逻辑仍使用 50 MHz `gt_ctrl_clk` 和对应的 `peripheral_aresetn`。AXI 地址发生了有意扩展，但旧地址没有迁移。新 XSA 需要用于刷新 Vitis platform/BSP，使 `xparameters.h` 获得 dynamic mailbox/descriptor 的正式符号；Stage 4 软件在刷新前保留与已审查 BD 地址一致的 fallback。

## 6. PL 资源仲裁和动态执行器

legacy 与 dynamic executor 通过唯一资源仲裁器共享 GT reset、TXUSERRDY block、CPLL/QPLL source select、GT channel DRP 和 MMCM DRP。dynamic executor 只有在 GT reset 已断言、TXUSERRDY 已关闭且 MMCM reset 已断言的安全阶段才取得物理资源所有权；忙时 legacy request 不会覆盖动态事务，动态 request 也不会打断 legacy 事务。

动态执行流程为：descriptor validate → quiesce TX → assert reset → PREPARED → 等待 PS 完成 AD9528 → snapshot CPLL/TXOUT_DIV/MMCM → select refclk/PLL → GT DRP write/readback → MMCM DRP write/readback → lock/ready wait → TXUSRCLK2 frequency verify → DONE。所有 GT/MMCM 写入在推进前均执行 readback 检查。

失败路径保存 previous PLL/refclk source、CPLL DRP、TXOUT_DIV、MMCM image 和 last-good frequency window。PS 恢复 AD9528 后发送 ROLLBACK_READY，PL 才恢复 GT/MMCM；rollback readback 或 last-good frequency verify 失败时进入安全锁定状态，不伪造成功。

### 6.1 PREPARED 长等待修正

普通 GT/MMCM DRP、lock 和 ready timeout 保持 `5,000,000` 个 50 MHz 周期，即约 100 ms。AD9528 配置、PLL2 calibration 和多窗口测频可能明显超过 100 ms，因此 PREPARED 不能复用普通硬件 timeout。本阶段新增独立 `REFCLK_READY_TIMEOUT_CYCLES=250,000,000`，对应约 5 s；只改变等待 PS `REFCLK_READY` 的容限，不改变 DRP/reset/lock/ready 状态顺序。

## 7. PS AD9528 事务协调器

协调器按以下顺序执行：runtime plan → descriptor 写入 BRAM → PREPARE → 等待 PL PREPARED → snapshot/apply AD9528 → calibration/lock/readback → 三个有效测频窗口 → REFCLK_READY → 等待 PL DONE。任一步失败都会发 ABORT；若 AD9528 已改变，则先恢复 AD9528 snapshot，再发 ROLLBACK_READY 允许 PL 恢复 previous GT/MMCM image。

`active` 和 `programmed` 状态语义保持区分：规划值不表示硬件已编程；AD9528 readback/measurement 和 PL VERIFY 均通过后，事务才可返回成功。

## 8. UDP 行为

- `rate plan <Mbps> [tolerance_ppm=n]`：使用 runtime planner，只读，不写硬件。
- `rate set <Mbps>`：若命中无 tolerance 的 board-verified 整数固定 profile，继续使用原 legacy executor；非固定、带小数或显式 tolerance 的目标进入 runtime AD9528 path。
- `rate abort`：请求中止运行时事务。
- `rate status`：保留原状态字段，并追加 runtime state/error/sequence/plan/mailbox raw status。

普通 fixed profile 的 UDP 命令格式、GPIO bitfield 和 supported list没有改变。

## 9. ILA 观测

原 AXI/FCLK ILA 的 50 个 probe 均保留，GT/MMCM DRP、reset、lock、ready、TXUSRCLK2 alive/count 和 legacy PLL 状态仍使用原 probe。新增 `probe50[31:0]`，由稳定的 50 MHz `gt_ctrl_clk` 采样，且仅用于观测：

| 位 | 信号 |
|---|---|
| `[7:0]` | `dynamic_executor_state` |
| `[15:8]` | `dynamic_executor_failed_stage` |
| `[16]` | `dynamic_executor_prepared` |
| `[17]` | `dynamic_executor_done` |
| `[18]` | `dynamic_executor_error` |
| `[19]` | `dynamic_executor_rollback_done` |
| `[20]` | `dynamic_executor_verify_pass` |
| `[21]` | `dynamic_descriptor_valid` |
| `[22]` | descriptor commit event |
| `[23]` | REFCLK_READY event |
| `[24]` | ABORT event |
| `[25]` | ROLLBACK_READY event |
| `[28]` | final `gt_ready` |
| 其余 | reserved 0 |

该 debug bus 不反馈到 mailbox、executor 或 TX 数据路径。ILA/debug hub 时钟不依赖 AD9528 OUT0 或 TXUSRCLK2。

## 10. 仿真与软件构建

| 验证 | 结果 |
|---|---|
| descriptor/mailbox simulation | PASS |
| resource arbiter simulation | PASS |
| executor success/rollback simulation | PASS |
| executor injected-fault/rollback simulation | PASS |
| PREPARED 等待超过普通 timeout | PASS；测试等待 25 cycle，普通 timeout 为 20 cycle |
| Python descriptor/planner tests | PASS，4 tests + 3 tests |
| Vitis managed application build | PASS；Stage 5 ELF 已生成，无手工补 object |

fault test覆盖 QPLL/GTNORTH 成功、GT DRP timeout、PLL lock timeout、MMCM DRP timeout、MMCM lock timeout、ready timeout、ABORT rollback、sequence mutation 和 rollback verify failure safe lock。以上均为仿真证据，不等价于上板 fault injection。

## 11. Vivado build、timing 与产物

Stage 6 已完成 synthesis、implementation、route、DRC、CDC、clock、IO、debug core、bit/LTX 和 XSA 生成。生成物仅作为本次诊断构建结果，**不得作为可安全上板的 release artifact**，因为按照 runtime planner 最大线速率 10.3125 Gbps 对 TXUSRCLK2 施加 6.206 ns（161.134 MHz）约束后，setup timing 未通过。构建约束随后也补齐了对应 TXUSRCLK 3.103 ns（322.266 MHz）；由于现有 TXUSRCLK2 数据路径已经确定失败，本轮没有把补齐约束误写成新一轮 timing pass。

| 项目 | 结果 |
|---|---:|
| synthesis | 完成，0 error、0 critical warning |
| implementation / route | 完成，0 unrouted net |
| Setup WNS | `-3.176 ns` |
| Setup TNS | `-494.725 ns`，295 failing endpoints |
| Hold WHS / THS | `0.051 ns / 0.000 ns` |
| 最差 setup path | `pattern_tx_engine/phase_pos_reg[10]` → `pattern_cursor_reg[53]` |
| 最差路径结构 | 27 logic levels，data path 9.057 ns（logic 2.216 ns，route 6.841 ns） |
| DRC | 0 error；3 条 `PDCN-1569` 和 1 条 `RTSTAT-10` warning |
| debug core | `dbg_hub`、AXI/FCLK ILA、TX ILA、AD9528 measurement ILA 均 implemented；AXI/FCLK ILA `probe50[31:0]` 存在 |

资源结果为 LUT 28,503（10.28%）、FF 28,216（5.09%）、Block RAM tile 69（9.14%）、DSP 0、BUFG 7、MMCM 1、GTXE2_CHANNEL 1、GTXE2_COMMON 1。

实现过程中还出现 13 条 `Project 1-840` Critical Warning：当前 project flow 直接读取 BD IP 的 OOC DCP。它们没有阻止 link/place/route，但属于应在后续 build-flow 清理的工程风险，不能写成“无 Critical Warning”。

本次诊断生成路径如下：

- bit：`laser_tx.runs/impl_1/laser_tx_board_top.bit`
- LTX：`laser_tx.runs/impl_1/laser_tx_board_top.ltx`
- XSA：`reports/ad9528_gt_rate_planner/stage6_build/laser_tx_board_top_runtime_rate_switch.xsa`

构建脚本已改为先运行到 routed design、检查 setup/hold slack；只有 timing pass 才继续生成可推广的 bit/LTX/XSA。当前已生成文件来自发现该问题前的诊断运行，不提交 Git，也不建议上板。

Vitis application 已执行真实 managed `make clean && make all`，16 个应用源文件由 managed object list 编译，link 通过，ELF 为 `vitis_bringup/bringup/Debug/bringup.elf`；size 为 text 261,673、data 3,512、bss 3,201,088 bytes。自动以新 XSA 刷新现有 `laser_tx_system_top` platform 时，XSCT 工作区未稳定识别 platform，刷新未闭环；因此该 ELF 仍基于既有 BSP，并由 `laser_hw.h` 中与 BD 审核地址一致的 fallback 使用 `0x40040000` 和 `0x42000000`。上板前仍需成功刷新 platform/BSP、确认 `xparameters.h` 正式符号并重新 clean build。

## 12. 硬件验证状态

Hardware test was not run. 当前没有 UDP + ILA 上板证据证明任意一个 runtime-generated descriptor 已完成 AD9528→GTNORTHREFCLK→GT/MMCM→VERIFY 的完整切换和恢复。

`dynamic_runtime_rate_switch_board_verified=0`

## 13. 当前结论与边界

代码、仿真和软件构建支持“运行时规划、受校验 descriptor、事务协调、资源仲裁、安全执行和 rollback”的实现结论；在上板前不能声明运行时动态切换已通过。

本阶段不证明：

- 任意连续速率都存在合法解；
- runtime candidate 已成为正式 supported profile；
- 所有 AD9528/GT/MMCM 组合均可在板上锁定；
- rollback fault injection 已在硬件验证；
- 外部光口、眼图、BER、抖动/相噪或长期稳定性通过；
- 156.25 MHz 板载 MGTREFCLK 动态切换或 AD9528 直连 Bank111 已实现。

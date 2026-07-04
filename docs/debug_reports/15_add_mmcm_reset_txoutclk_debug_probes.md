# MMCM reset / TXOUTCLK debug-only probe 增强报告

## 1. 本轮任务范围

本轮只做 500M -> 1000M 动态切换失败后的 debug-only probe 增强，用于下一次上板定位 `MMCM_LOCK_TIMEOUT` 的真实原因。

本轮目标不是修复动态切换状态机，也不是修改 GTX/MMCM DRP 写序列，而是在 AXI/FCLK 域 ILA 中补充可观察信号，区分以下三类情况：

1. `tx_mmcm_reset` 仍然为 1，MMCM 没有真正释放；
2. `tx_mmcm_reset` 已释放，但 MMCM 输入 `TXOUTCLK` 不存在或不稳定；
3. MMCM/GT DRP 写值或 readback 不符合预期。

## 2. 修改摘要

本轮涉及 RTL debug 端口、BD/ILA probe、wrapper、Vivado 构建脚本和报告文件。

修改文件：

| 文件 | 修改内容 |
| --- | --- |
| `laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v` | 增加 debug-only `dbg_timeout_count[31:0]` 输出，用于观察 WAIT_LOCK / timeout 计数 |
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 增加 MMCM reset/lock、GT reset/user ready、GT/MMCM DRP、TXOUTCLK alive、timeout 等 debug-only 输出 |
| `rtl/laser_tx_board_top.v` | 增加顶层内部 debug wire，并转接到 `system_wrapper` |
| `laser_tx.srcs/sources_1/bd/system/system.bd` | 将 `ila_laser_axi_cfg` 扩展到 50 个 probe，并接入新增 AXI/FCLK 域 debug 信号 |
| `laser_tx.srcs/sources_1/imports/hdl/system_wrapper.v` | 重新生成/同步 wrapper，暴露新增 debug-only 端口 |
| `scripts/add_mmcm_reset_txoutclk_debug_probes.tcl` | 新增 BD/ILA probe 接入脚本 |
| `scripts/direct_build_mmcm_txoutclk_debug_probes.tcl` | 新增 direct build 检查脚本，用于 synthesis / implementation / timing |
| `scripts/post_write_mmcm_txoutclk_debug_artifacts.tcl` | 新增 bit/LTX/debug report 导出脚本 |
| `docs/debug_reports/15_add_mmcm_reset_txoutclk_debug_probes.md` | 本报告 |

本轮未修改 Vitis、UDP 协议、AD9528、速率集合，也未新增任何 500M/1000M 以外的速率。

## 3. 修改前问题

第一次 500M -> 1000M 真实动态切换上板失败时，UDP 返回：

```text
rate_state=RATE_ERROR
error_code=MMCM_LOCK_TIMEOUT
gt_drp_written=1
mmcm_drp_written=1
gt_drp_done=1
mmcm_drp_done=1
gt_ready=0
raw=0x0680f829
```

已有 AXI/FCLK ILA 能看到 rate controller 大方向已经进入切换流程，但不足以判断 `RATE_WAIT_LOCK` 阶段到底卡在：

- MMCM reset 没释放；
- GT TXOUTCLK 不存在或不稳定；
- MMCM DRP 写值/readback 有问题；
- locked 原始信号正常但同步状态异常。

因此不能继续盲改 DRP 参数或状态机，需要先补齐 debug-only 观测点。

## 3.1 为什么原有 ILA 不足以判断 RATE_WAIT_LOCK 根因

原有 AXI/FCLK ILA 主要能看到 `rate_state`、`rate_error_code`、GT/MMCM DRP `busy/done/error`、`txusrclk2_alive_axi`、`txusrclk2_freq_counter_axi`、`gt_ready` / `txresetdone` 的汇总状态。

这些信号已经足够证明 rate controller 确实进入了动态切换流程，也能证明 GT DRP 和 MMCM DRP 事务至少走到了 `done`。但它们还不足以证明 MMCM 在 `RATE_WAIT_LOCK` 阶段具备 lock 的必要条件。换句话说，原有 ILA 能看到“流程走到哪里”和“最后报了什么错”，但看不到 MMCM lock 失败之前几个关键前提是否成立。

### 1. 为什么无法判断 MMCM reset 是否真正释放

原有 ILA 只能看到最终 `error_code=MMCM_LOCK_TIMEOUT`，不能看到 `tx_mmcm_reset_wizard`、`tx_mmcm_reset_rate` 和最终 `tx_mmcm_reset`。

当前 RTL 中 MMCM reset 是多个来源的组合结果：

```text
tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate
```

这意味着，即使 rate controller 已经把 `rate_mmcm_reset` 释放为 0，只要 GT Wizard 侧的 `tx_mmcm_reset_wizard` 仍然为 1，最终送进 MMCM 的 reset 仍然是 1。MMCM 在 reset 被按住时不可能 lock。

因此，如果不同时观察这三个 reset 信号，只看 `locked=0` 或 timeout，无法判断当前问题是“MMCM 参数不对”，还是“MMCM 根本没有解除 reset”。这两类问题的修复方向完全不同：前者要查 DRP 参数，后者要查 reset 来源和释放顺序。

### 2. 为什么无法判断 TXOUTCLK 是否存在或稳定

原有 ILA 中有 `txusrclk2_alive_axi`，但 `txusrclk2` 是 MMCM 的输出侧时钟，不是 MMCM 的输入时钟。

当前时钟链路是：

```text
GT TXOUTCLK -> MMCM -> TXUSRCLK/TXUSRCLK2
```

因此，`txusrclk2` 停止只能说明 MMCM 输出没有正常工作，不能说明原因。它可能是因为：

- MMCM reset 没释放；
- MMCM 输入 `TXOUTCLK` 没有；
- MMCM 输入 `TXOUTCLK` 有，但 MMCM 没 lock；
- MMCM lock 过，但同步状态异常。

原有 ILA 没有 `txoutclk_alive_axi`，所以无法判断 MMCM 输入端是否还有时钟。没有这个信号时，`txusrclk2_alive_axi=0` 只能说明“结果坏了”，不能说明“输入时钟有没有来”。这会让 debug 停留在输出现象层面，而无法继续向上游定位到 GT TXOUTCLK / GT reset / TXOUT_DIV 切换顺序。

### 3. 为什么无法判断 MMCM DRP 写值/readback 是否正确

原有 ILA 只能看到 `mmcm_drp_done=1`。这个 done 只能说明 MMCM DRP 接口完成了事务、`DRDY` 返回了，不等于写入的地址和值一定符合预期，也不等于 readback 正确。

如果没有观察：

- `mmcm_drp_addr`
- `mmcm_drp_di`
- `mmcm_drp_do`
- `mmcm_drp_en`
- `mmcm_drp_we`
- `mmcm_drp_rdy`

就无法确认 1000M 目标参数是否按预期顺序写入，也无法判断 LOCK/FILTER、CLKFBOUT、CLKOUT、DIVCLK 等寄存器是否被正确配置。因此，原有 ILA 只能证明“写流程结束”，不能证明“写内容正确”。

这一区分很关键：如果 `done=1` 但地址或数据错误，状态机本身看起来可能没有失败，MMCM 却仍然无法 lock。此时继续调大 timeout 或修改 reset sequence 都可能掩盖真正问题。

### 4. 为什么无法判断 MMCM locked raw 正常但同步后异常

rate controller 等待的是同步到 `gt_ctrl_clk` 域后的 `tx_mmcm_locked_sync`，而 MMCM 自身输出的是原始 `tx_mmcm_locked_raw`。

如果原始 locked 已经拉高，但同步链路因为复位、CDC 或采样窗口问题没有正确反映到 `gt_ctrl_clk` 域，那么 rate controller 仍然会看到 `locked_sync=0`，并最终 timeout。

原有 ILA 没有同时观察 `locked_raw` 和 `locked_sync`，所以无法区分：

- MMCM 本身确实没有 lock；
- MMCM 已经 lock，但同步后的 `locked_sync` 没有正确拉高。

前者指向 MMCM 输入时钟、DRP 参数或 reset sequence；后者则指向 CDC、同步复位或采样窗口。只看最终 timeout 无法区分这两条排查路径。

### 小结

因此，原有 ILA 只能定位到“`RATE_WAIT_LOCK` 阶段没有等到 `locked_sync`，最终 `MMCM_LOCK_TIMEOUT`”，但不能进一步判断根因。新增 debug-only probes 的目的，就是把这一个模糊结果拆成几个可验证条件：

1. `tx_mmcm_reset` 是否释放；
2. `txoutclk_alive_axi` 是否存在；
3. `tx_mmcm_locked_raw` 是否曾经拉高；
4. `tx_mmcm_locked_sync` 是否正确同步；
5. MMCM/GT DRP addr/data/readback 是否符合预期；
6. `timeout_count` 是否在 `RATE_WAIT_LOCK` 阶段正常推进。

这样下一次上板时，就可以从 ILA 直接判断根因属于 reset 未释放、输入时钟不存在、DRP 配置问题，还是 locked CDC 问题，而不是继续只看到一个笼统的 `MMCM_LOCK_TIMEOUT`。

## 4. 修改后结构

### 4.1 AXI/FCLK ILA 新增 probe

新增 probe 均接入 `ila_laser_axi_cfg`，采样时钟为 `gt_ctrl_clk / clk_fpga_0`。

| Probe | 信号 | 位宽 | 用途 |
| --- | --- | ---: | --- |
| probe24 | `dbg_tx_mmcm_reset_wizard` | 1 | 观察 GT Wizard/user clocking 原始 MMCM reset 来源 |
| probe25 | `dbg_tx_mmcm_reset_rate` | 1 | 观察 rate controller 对 MMCM reset 的控制 |
| probe26 | `dbg_tx_mmcm_reset` | 1 | 观察最终送入 user clocking 的 MMCM reset |
| probe27 | `dbg_tx_mmcm_locked_raw` | 1 | 观察 MMCM locked 原始信号 |
| probe28 | `dbg_tx_mmcm_locked_sync` | 1 | 观察同步到 `gt_ctrl_clk` 后的 MMCM locked |
| probe29 | `dbg_rate_gt_tx_reset` | 1 | 观察 rate controller 对 GT TX reset 的控制 |
| probe30 | `dbg_gt0_gttxreset_effective` | 1 | 观察最终送入 GT Wizard 的 TX reset |
| probe31 | `dbg_rate_txuserrdy_block` | 1 | 观察 rate controller 是否阻塞 `txuserrdy` |
| probe32 | `dbg_gt0_txuserrdy_effective` | 1 | 观察最终送入 GT Wizard 的 `txuserrdy` |
| probe33 | `dbg_txresetdone_sync` | 1 | 观察 GT `txresetdone` 同步状态 |
| probe34 | `dbg_gt_ready` | 1 | 观察 AXI/FCLK 域综合 GT ready |
| probe35 | `dbg_mmcm_drp_addr[6:0]` | 7 | 观察 MMCM DRP address |
| probe36 | `dbg_mmcm_drp_di[15:0]` | 16 | 观察 MMCM DRP write data |
| probe37 | `dbg_mmcm_drp_do[15:0]` | 16 | 观察 MMCM DRP readback data |
| probe38 | `dbg_mmcm_drp_en` | 1 | 观察 MMCM DRP DEN |
| probe39 | `dbg_mmcm_drp_we` | 1 | 观察 MMCM DRP DWE |
| probe40 | `dbg_mmcm_drp_rdy` | 1 | 观察 MMCM DRP DRDY |
| probe41 | `dbg_gt_drp_addr[8:0]` | 9 | 观察 GT DRP address |
| probe42 | `dbg_gt_drp_di[15:0]` | 16 | 观察 GT DRP write data |
| probe43 | `dbg_gt_drp_do[15:0]` | 16 | 观察 GT DRP readback data |
| probe44 | `dbg_gt_drp_en` | 1 | 观察 GT DRP DEN |
| probe45 | `dbg_gt_drp_we` | 1 | 观察 GT DRP DWE |
| probe46 | `dbg_gt_drp_rdy` | 1 | 观察 GT DRP DRDY |
| probe47 | `dbg_gt_drp_readback_value[15:0]` | 16 | 观察 GT TXOUT_DIV readback 结果 |
| probe48 | `dbg_txoutclk_alive_axi` | 1 | 观察 TXOUTCLK 是否仍在跳变 |
| probe49 | `dbg_timeout_count[31:0]` | 32 | 观察 WAIT_LOCK / timeout 计数 |

原有 AXI/FCLK probe 仍保留，包括 `axi_gpio_0_gpio_io_o[31:0]`、`gpio_status[31:0]`、BRAM debug、rate_state、target/current rate、rate_error、GT/MMCM DRP busy/done/error、`txusrclk2_alive_axi` 和 `txusrclk2_freq_counter_axi`。

### 4.2 TXOUTCLK alive CDC 方法

`TXOUTCLK` 不能直接驱动普通 fabric FF。首次实现中曾直接用 `txoutclk` 驱动 toggle FF，Vivado DRC 报：

```text
[DRC REQP-1739] GTx R/TXOUTCLK drives inappropriate load
```

修正后增加 debug-only `BUFG u_txoutclk_debug_bufg`，形成：

```text
GT TXOUTCLK -> BUFG(debug only) -> txoutclk_toggle_txout
             -> 2FF synchronizer -> gt_ctrl_clk domain
             -> txoutclk_alive_axi
```

`txoutclk_alive_axi` 是 AXI/FCLK 域下的安全 CDC 后信号，没有把 `TXOUTCLK` 域多 bit counter 直接跨域接到 AXI ILA。

### 4.3 GT reset / user ready effective debug

为便于观察最终进入 GT Wizard 的控制信号，本轮显式命名并导出：

```text
gt0_gttxreset_effective
gt0_txuserrdy_effective
```

这两个信号用于 debug 观测最终送入 GT Wizard 的 reset/user-ready 组合结果。其目的是让 ILA 能直接判断切换期间 GT 是否仍被 reset 或 `txuserrdy` 是否被阻塞。

## 5. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| MMCM reset 观察 | 只能间接从状态推断 | 可观察 wizard/rate/final reset 三类信号 | 可判断 MMCM 是否真的释放 |
| MMCM lock 观察 | 仅有同步后的部分状态 | 增加 raw locked 与 sync locked | 可区分原始 lock 和 CDC 后状态 |
| TXOUTCLK 观察 | 无独立 alive 观测 | 增加 BUFG + toggle CDC + `txoutclk_alive_axi` | 可判断 MMCM 输入是否存在 |
| MMCM DRP 观察 | 只看 busy/done/error | 增加 addr/di/do/en/we/rdy | 可检查 DRP 写序列与 readback |
| GT DRP 观察 | 只看 busy/done/error/readback 部分状态 | 增加 addr/di/do/en/we/rdy/readback | 可检查 TXOUT_DIV DRP 时序和 readback |
| WAIT_LOCK timeout | 只能看到最终 error | 增加 `dbg_timeout_count[31:0]` | 可观察等待阶段计数是否推进 |
| ILA clock | AXI ILA 为 `gt_ctrl_clk`，TX ILA 为 `txusrclk2` | 保持不变 | debug hub 和主 bring-up ILA 不依赖 txusrclk2 |
| 功能行为 | 动态切换进入 `MMCM_LOCK_TIMEOUT` | 未改变状态机行为和 DRP 写序列 | 本轮不修复功能，只增强观测 |
| Pipeline latency | 无变化 | 无变化 | 不影响发送数据路径 |

## 6. 功能等价性说明

本轮设计意图是 debug-only 增强。

未修改：

- rate controller 状态机状态转移；
- GTX DRP 地址、写值、写序列；
- MMCM DRP 地址、写值、写序列；
- UDP/Vitis 命令协议；
- BRAM 配置格式；
- `laser_tx_core` 发送数据路径；
- 500M/1000M 以外的速率；
- AD9528。

`txoutclk_alive_axi` 只用于观察，不参与控制。`dbg_timeout_count` 只导出既有 `timeout_count`，不改变 timeout 判断。新增 ILA probe 不应改变软件可见寄存器、AXI 地址、外部端口或 Vitis BSP。

注意：本轮为了让 GT Wizard 入口 reset/user-ready 可观察，将最终表达式命名为 `gt0_gttxreset_effective` / `gt0_txuserrdy_effective` 后再接入 GT Wizard。该变更意图为结构显式化和 debug 暴露，等价于观察最终控制条件；未引入新的速率切换行为。

## 7. Vivado / BD / Debug 结构说明

### 7.1 Debug core 时钟

`report_debug_core -full_path` 结果显示：

```text
dbg_hub/clk          = gt_ctrl_clk
ila_laser_axi_cfg/clk = u_system_wrapper/system_i/gt_ctrl_clk
ila_laser_tx/clk      = u_system_wrapper/system_i/txusrclk2
```

因此主 debug hub 和 AXI/FCLK ILA 均不依赖 `txusrclk2`；`ila_laser_tx` 继续作为 TX 域二级观察窗口。

### 7.2 Debug core 数量

本轮 bit 中包含 3 个 debug core：

```text
dbg_hub
ila_laser_axi_cfg
ila_laser_tx
```

`ila_laser_axi_cfg` 已扩展到 50 个 probe，新 probe24~probe49 已进入 AXI/FCLK ILA。

### 7.3 BD / wrapper 影响

BD 中未新增外部板级端口，未改变 AXI 地址映射，未改变 PS MIO/EMIO，未改变中断，未改变软件可见外设。

本轮只在 BD/module wrapper 边界增加内部 debug-only 信号连接，并重新同步 `system_wrapper.v`。

## 8. 构建与验证记录

执行过的主要步骤：

```text
vivado.bat -mode batch -source scripts/add_mmcm_reset_txoutclk_debug_probes.tcl -notrace
vivado.bat -mode batch -source scripts/direct_build_mmcm_txoutclk_debug_probes.tcl -notrace
vivado.bat -mode batch -source scripts/post_write_mmcm_txoutclk_debug_artifacts.tcl -notrace
```

构建结果：

| 项目 | 结果 |
| --- | --- |
| synthesis | 通过 |
| implementation/place/route | 通过 |
| bitstream | 已生成 |
| write_debug_probes | 已生成 |
| report_debug_core -full_path | 已生成 |
| hardware test | Hardware test was not run |

Bit/LTX 产物：

| 文件 | 大小 | 修改时间 |
| --- | ---: | --- |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit` | 17,416,462 bytes | 2026-07-03 15:00:10 |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx` | 154,556 bytes | 2026-07-03 15:00:11 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 17,416,462 bytes | 2026-07-03 15:01:06 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 154,556 bytes | 2026-07-03 15:01:07 |

报告文件：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/mmcm_txoutclk_debug_timing_summary.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/mmcm_txoutclk_debug_core_full_path.rpt
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/mmcm_txoutclk_debug_core_full_path.rpt
```

## 9. QoR / timing 对比

本轮只确认修改后的 timing。未重新整理修改前 QoR 对比。

| Metric | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Setup WNS | 未复核 | 7.029 ns | timing met |
| Setup TNS | 未复核 | 0.000 ns | 无 setup violation |
| Failing endpoints | 未复核 | 0 | 无 failing endpoint |
| Hold WHS | 未复核 | 0.054 ns | hold met |
| Hold THS | 未复核 | 0.000 ns | 无 hold violation |
| Worst path | 未复核 | GT/CPLL 或 debug/clock interaction 相关路径，均 met | debug 增强后实现通过 |

当前 timing 约束沿用现有工程约束；本轮未修改 XDC。

## 10. 重要边界声明

本轮只是 debug-only probe 增强：

- 没有修复 `MMCM_LOCK_TIMEOUT`；
- 没有证明 500M -> 1000M 动态切换成功；
- 没有执行上板验证；
- 没有执行 `rate set 1000` / `rate set 500` 复测；
- 没有声明外部光口链路或示波器验证通过。

本轮完成的是：下一次上板时，AXI/FCLK ILA 已具备判断 `RATE_WAIT_LOCK` 阶段关键条件的观测能力。

## 11. 风险与后续建议

### 11.1 残留风险

1. 当前 build 使用 direct build / checkpoint 导出流程完成，建议后续继续清理 GUI/project run 与 direct flow 的边界，避免再次混入旧 bit/LTX。
2. `TXOUTCLK` debug-only BUFG 会占用额外全局时钟资源；它不参与功能控制，但属于新增 debug 资源。
3. 本轮新增大量 ILA probe，可能增加 debug routing 负载；当前 timing 已通过，但后续若再增加 probe 仍需重新实现。
4. 由于未上板，本轮不能判断 `MMCM_LOCK_TIMEOUT` 的根因。

### 11.2 下一次上板重点观察

下一次上板执行 500M -> 1000M 切换时，应优先在 `ila_laser_axi_cfg` 中观察：

1. `rate_state[7:0]` 是否进入 `RATE_WAIT_LOCK`；
2. `dbg_tx_mmcm_reset` / `dbg_tx_mmcm_reset_rate` / `dbg_tx_mmcm_reset_wizard` 在 WAIT_LOCK 是否已释放；
3. `dbg_txoutclk_alive_axi` 是否保持为 1；
4. `dbg_tx_mmcm_locked_raw` 是否曾经拉高；
5. `dbg_tx_mmcm_locked_sync` 是否正确同步；
6. `dbg_mmcm_drp_addr/di/do/en/we/rdy` 是否符合预期写序列；
7. `dbg_gt_drp_addr/di/do/en/we/rdy/readback` 是否确认 TXOUT_DIV 写入成功；
8. `dbg_timeout_count[31:0]` 是否持续计数到 timeout。

如果 `tx_mmcm_reset` 未释放，应优先查 reset release 条件；如果 `txoutclk_alive_axi=0`，应优先查 GT reset/TXOUTCLK 顺序；如果 `txoutclk_alive_axi=1` 但 `tx_mmcm_locked_raw=0`，再查 MMCM DRP 参数和 LOCK/FILTER 相关配置。

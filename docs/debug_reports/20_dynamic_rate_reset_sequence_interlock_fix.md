# 500M↔1000M 动态切换 reset sequence 互锁修复报告

## 1. 修改摘要

本轮只修改动态速率切换控制器：

```text
laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v
```

修改目的：打破 500M -> 1000M 动态切换进入 `RATE_WAIT_LOCK` 后的 reset sequence 互锁。

本轮未修改：

```text
laser_tx_core
pattern_tx_engine
GT/MMCM DRP 参数表
GT Wizard generated source
BD 功能连接
XDC
Vitis
UDP 协议
AD9528
500M/1000M 以外的速率支持
```

重新运行了 Vivado project flow：

```text
synth_1
impl_1
write_bitstream
write_debug_probes
report_timing_summary
report_debug_core -full_path
```

生成的主工程 bit/LTX：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

同步复制到 dynamic artifacts：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

## 2. 修改前问题

上板 ILA 与 UDP 状态显示，500M -> 1000M 第一次真实动态切换失败在 `MMCM_LOCK_TIMEOUT`：

```text
dbg_tx_mmcm_reset_rate   = 0
dbg_tx_mmcm_reset_wizard = 1
dbg_tx_mmcm_reset        = 1
dbg_txoutclk_alive_axi   = 1
dbg_gt0_gttxreset_effective = 1
dbg_gt0_txuserrdy_effective = 0
dbg_gt_ready             = 0
```

当前 wrapper 中 MMCM reset 是组合结果：

```verilog
tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate;
```

其中 `tx_mmcm_reset_wizard` 来自 GT Wizard TX startup FSM。此前 rate controller 在进入 `RATE_WAIT_LOCK` 后仍保持 `rate_gt_tx_reset=1`，而 `rate_gt_tx_reset` 同时参与驱动 GT Wizard 的 `soft_reset_tx_in` / `gttxreset` 路径。

因此形成互锁：

```text
状态机等待 tx_mmcm_locked_sync
-> rate_gt_tx_reset 仍为 1
-> GT Wizard 侧 soft_reset_tx_in 仍被按住
-> GT Wizard TX startup FSM 继续拉高 tx_mmcm_reset_wizard
-> 最终 tx_mmcm_reset = 1
-> MMCM 没有真正释放，无法稳定 lock
-> 状态机继续等待 locked
-> timeout
```

这个问题不是 MMCM DRP 参数表本身的直接证据，也不是 Vitis/UDP 命令解析问题；它首先是 reset release 顺序的问题。

## 3. 修改后结构

本轮采用最小 reset sequence 修复，不改 GT/MMCM DRP 写值，只改变 DRP 写完后的 reset/user-ready 释放顺序。

新增状态：

```verilog
localparam [7:0] RATE_WAIT_MMCM_RESET_RELEASE = 8'h0b;
```

### 3.1 RATE_RELEASE_RESET

修改前，`RATE_RELEASE_RESET` 会进入 `RATE_WAIT_LOCK`，但 `rate_gt_tx_reset` 没有在等待 MMCM lock 前释放，可能继续使 Wizard 侧 `tx_mmcm_reset_wizard` 保持为 1。

修改后：

```verilog
rate_gt_tx_reset      <= 1'b0;
rate_txuserrdy_block  <= 1'b1;
rate_mmcm_reset       <= 1'b0;
rate_state            <= RATE_WAIT_MMCM_RESET_RELEASE;
timeout_count         <= 32'd0;
```

含义：

```text
1. 先释放 rate_gt_tx_reset，使 GT Wizard soft_reset_tx_in 解除；
2. 同时保持 rate_txuserrdy_block=1，避免 MMCM lock 之前过早释放 TXUSERRDY；
3. 释放 rate_mmcm_reset，使用户侧 MMCM reset 不再由 rate controller 按住；
4. 进入短暂等待状态，让 Wizard 侧 TX startup FSM 有机会释放 tx_mmcm_reset_wizard。
```

### 3.2 RATE_WAIT_MMCM_RESET_RELEASE

新增中间状态保持：

```text
rate_gt_tx_reset     = 0
rate_txuserrdy_block = 1
rate_mmcm_reset      = 0
```

该状态等待 `RESET_HOLD_CYCLES` 后进入 `RATE_WAIT_LOCK`。由于本轮禁止修改 wrapper/BD/ILA 连接，`laser_gt_rate_switch_500m_1000m.v` 当前没有 `tx_mmcm_reset`、`tx_mmcm_reset_wizard`、`txoutclk_alive_axi` 输入，所以不能在状态机内部直接判断 `tx_mmcm_reset==0 && txoutclk_alive_axi==1`。这些条件仍由 AXI/FCLK ILA 在上板时观察确认。

### 3.3 RATE_WAIT_LOCK

修改前，在 `tx_mmcm_locked_sync=0` 时可能继续保持或重新拉高 `rate_gt_tx_reset`。

修改后，在等待 MMCM lock 时明确保持：

```verilog
rate_gt_tx_reset     <= 1'b0;
rate_txuserrdy_block <= 1'b1;
rate_mmcm_reset      <= 1'b0;
```

也就是说，`RATE_WAIT_LOCK` 不再因为 locked 尚未回来就重新按住 GT Wizard soft reset。MMCM lock 成功后，才释放 `rate_txuserrdy_block`，进入后续 `txresetdone_sync` / `gt_ready_ctrl` 等待流程。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| DRP 参数表 | 500M/1000M GT/MMCM 参数表保持原样 | 保持原样 | 不改变 TXOUT_DIV、MMCM 寄存器写值 |
| `RATE_RELEASE_RESET` | DRP done 后直接进入等待 lock，GT reset 释放边界不清 | 先释放 `rate_gt_tx_reset`，保持 `rate_txuserrdy_block=1`，进入中间等待 | 打破 Wizard soft reset 与 MMCM lock 的互锁 |
| 新增状态 | 无 | `RATE_WAIT_MMCM_RESET_RELEASE` | 给 Wizard TX startup FSM 释放 `tx_mmcm_reset_wizard` 的时间窗口 |
| `RATE_WAIT_LOCK` | locked 未回来时可能继续使 GT Wizard reset 路径被按住 | locked 未回来时不再重新拉高 `rate_gt_tx_reset` | 允许 MMCM 在 TXOUTCLK 存在时尝试重新 lock |
| TXUSERRDY | 可能与 reset/lock 等待耦合不清 | MMCM lock 前保持 block，lock 后再释放 | 避免用户时钟未稳定时过早释放 GT TX user ready |
| 支持速率 | 仅 500M/1000M | 不变 | 未新增任意速率 |
| 软件接口 | `rate set 500/1000` | 不变 | 未修改 Vitis/UDP 协议 |
| 功能行为 | 500M->1000M 可能进入 MMCM_LOCK_TIMEOUT 互锁 | 改变 reset release 顺序以避免互锁 | reset sequence 行为有意修改 |
| 上板验证状态 | 已观察到失败互锁证据 | 已生成新 bit/LTX，尚未上板验证 | 不能声明动态切换成功 |

## 5. 功能等价性说明

本轮不是对 `laser_tx_core` 或发送数据路径的功能重构。

保持不变的行为：

```text
1. 只支持 500M 和 1000M 两档；
2. GT/MMCM DRP address/data 参数表不变；
3. `rate set 500` / `rate set 1000` 软件命令语义不变；
4. 非法速率处理不变；
5. APPLY/ENABLE/BRAM/GPIO/UDP 控制协议不变；
6. txdata/valid_mask 发送语义不变；
7. GT Wizard generated HDL 未修改；
8. BD/XDC/Vitis 未修改。
```

有意改变的行为：

```text
Functional behavior changed intentionally
```

改变点仅限动态 rate switch reset sequence：

```text
GT/MMCM DRP 写完后，先释放 rate_gt_tx_reset，使 GT Wizard soft_reset_tx_in 解除；
MMCM lock 前继续保持 txuserrdy blocked；
等待 MMCM lock 时不再重新按住 GT reset；
MMCM locked 后再释放 TXUSERRDY，随后等待 txresetdone/gt_ready。
```

功能等价性结论基于 RTL 结构检查和 Vivado build 结果；动态切换是否真正修复仍需要上板 ILA/UDP 验证。

## 6. 测试与验证

### 6.1 执行命令

使用 Vivado 2022.2 project flow 临时 Tcl 执行：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source %TEMP%\laser_tx_reset_sequence_fix_build.tcl"
```

由于 build 主流程已经完成，但后处理阶段第一次遇到 Vivado 2022.2 `report_debug_core -return_string` 不支持、第二次遇到单 core `report_debug_core` 参数形式不兼容，随后只补跑后处理：

```text
cmd /c "call D:\Vitis\2022.2\settings64.bat && vivado -mode batch -source %TEMP%\laser_tx_reset_sequence_fix_post2.tcl"
```

这些 Tcl 文件位于用户临时目录，仅作为本轮命令驱动使用；没有修改工程 build 脚本。

### 6.2 Vivado build 结果

```text
synth_1_STATUS=synth_design Complete!
synth_1_PROGRESS=100%
synth_1_first_ERROR=

impl_1_STATUS=write_bitstream Complete!
impl_1_PROGRESS=100%
impl_1_first_ERROR=
```

主工程产物：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx
```

dynamic artifacts：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

文件大小：

```text
laser_tx_board_top.bit = 17,416,462 bytes
laser_tx_board_top.ltx =    154,556 bytes
```

### 6.3 Debug core 检查

`report_debug_core -full_path` 已生成：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/reset_sequence_fix/impl1_debug_core_full_path.rpt
```

debug core 列表：

```text
dbg_hub
u_system_wrapper/system_i/ila_laser_axi_cfg
u_system_wrapper/system_i/ila_laser_tx
```

dbg_hub clock：

```text
dbg_hub/clk net=gt_ctrl_clk clocks=clk_fpga_0
```

报告中确认：

```text
ila_laser_axi_cfg/clk = u_system_wrapper/system_i/gt_ctrl_clk
```

AXI/FCLK ILA 中仍可看到动态切换与 MMCM reset/TXOUTCLK debug probe，例如：

```text
dbg_rate_state
dbg_tx_mmcm_reset_wizard
dbg_tx_mmcm_reset_rate
dbg_tx_mmcm_reset
dbg_mmcm_drp_addr
dbg_gt_drp_addr
dbg_txoutclk_alive_axi
```

### 6.4 上板验证

```text
Hardware test was not run
```

本轮没有执行 `rate set 1000` / `rate set 500` 上板测试，因此不能声明 500M->1000M 或 1000M->500M 动态切换已经通过。

## 7. QoR / timing 对比

当前实现后 timing summary：

| Metric | After | Interpretation |
|---|---:|---|
| Setup WNS | 7.029 ns | 通过 |
| Setup TNS | 0.000 ns | 无 setup violation |
| Setup failing endpoints | 0 | 无 setup 失败端点 |
| Hold WHS | 0.042 ns | 通过 |
| Hold THS | 0.000 ns | 无 hold violation |
| Hold failing endpoints | 0 | 无 hold 失败端点 |
| Pulse width WPWS | 3.358 ns | 通过 |
| Timing summary | All user specified timing constraints are met | timing met |

报告路径：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/reset_sequence_fix/impl1_timing_summary.rpt
```

本轮没有可靠 before/after QoR 资源表对照，因此只报告修改后实现结果。若需要正式 QoR 对比，应基于修改前同一工程状态的 utilization/timing 报告再做对照。

## 8. 风险与后续建议

### 8.1 残留风险

1. 本轮只打破 reset sequence 互锁，不修改 MMCM DRP 参数表；如果 MMCM DRP 写值本身仍有问题，仍可能 timeout。
2. `laser_gt_rate_switch_500m_1000m.v` 当前没有 `tx_mmcm_reset`、`tx_mmcm_reset_wizard`、`txoutclk_alive_axi` 输入，因此状态机内部不能直接等待 `tx_mmcm_reset==0 && txoutclk_alive_axi==1`；这些条件需要通过 AXI/FCLK ILA 上板观察。
3. 新 bit/LTX 尚未上板验证，不能确认 `tx_mmcm_reset_wizard` 是否会按预期变为 0。
4. 仍未验证 1000M->500M 反向切换。
5. 本轮 Vivado 后处理中发现 `report_debug_core` 不同参数形式在 Vivado 2022.2 下兼容性有限；正式脚本中应继续使用已验证可行的 `report_debug_core -full_path -file ...`。

### 8.2 下一步上板观察重点

使用本轮生成的同源 bit/LTX：

```text
Bitstream:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit

Debug probes:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

上板执行 `rate set 1000` 后，AXI/FCLK ILA 重点观察：

```text
RATE_WAIT_MMCM_RESET_RELEASE 是否出现；
RATE_WAIT_LOCK 阶段 dbg_tx_mmcm_reset_wizard 是否变为 0；
dbg_tx_mmcm_reset 是否保持 0；
dbg_txoutclk_alive_axi 是否为 1；
dbg_tx_mmcm_locked_raw 是否稳定为 1；
dbg_tx_mmcm_locked_sync 是否稳定为 1；
dbg_gt0_txuserrdy_effective 是否在 locked 后释放；
txresetdone_sync / gt_ready 是否恢复；
rate_error_code 是否保持 0；
current_rate_mbps 是否在成功后更新到 1000。
```

若 500M->1000M 成功，再测试 1000M->500M。若仍失败，应根据 ILA 将根因分到：

```text
1. Wizard reset 仍未释放；
2. TXOUTCLK 存在但 MMCM raw lock 不稳定；
3. raw lock 正常但 sync 不正常；
4. MMCM/GT DRP readback 与预期不一致；
5. GT TX resetdone/ready 恢复序列仍有问题。
```

## 9. 当前结论

本轮已完成最小 reset sequence RTL 修复，并重新生成通过 timing 的 bit/LTX。修改后的状态机在 GT/MMCM DRP 写完后先释放 `rate_gt_tx_reset`，保持 `rate_txuserrdy_block`，再进入 MMCM lock 等待，从结构上打破了“等待 MMCM lock 时 Wizard 仍按住 MMCM reset”的互锁。

但是，本轮尚未执行上板 `rate set 1000` / `rate set 500` 验证，因此当前只能结论为：

```text
reset sequence 互锁修复已完成 RTL 实现并通过 Vivado synthesis/implementation/timing/bitstream；
动态速率切换尚未上板验证通过；
不能声明 500M↔1000M 动态切换成功。
```

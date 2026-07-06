# QPLL wrapper 架构升级报告

## 1. 本阶段目标

本阶段目标是为后续 10G QPLL profile 做硬件架构准备，而不是实现 `rate set 10000`。本轮只在现有 GT TX wrapper 中补齐真实的 QPLL 基础结构，使工程中不再只有 CPLL-only channel wrapper 和常量 QPLL 输入。

本阶段明确不改变现有 CPLL dynamic profile 的功能行为。当前 supported rate list 仍保持 500M / 1000M / 1250M / 2000M / 2500M / 3125M / 5000M / 6250M，不加入 10000M。

## 2. 为什么不能直接加入 10G

31 号能力确认阶段已经指出，原 active wrapper 不具备安全加入 10G QPLL profile 的条件：

- 未实例化可用的 `GTXE2_COMMON`；
- `gt0_qplloutclk_in` / `gt0_qplloutrefclk_in` 被常量占位，QPLLCLK / QPLLREFCLK 不是真实时钟；
- QPLLLOCK 不是真实可观测 lock；
- QPLLRESET 未接入 wrapper 或 rate controller；
- `TXSYSCLKSEL` 固定为 CPLL 选择；
- 当前 reset / lock / ready sequence 仍围绕 CPLL profile。

因此，如果直接把 10000M 加入 profile table，会把 QPLL clock source、QPLL reset/lock、GT channel PLL 选择、MMCM DRP、TX reset sequence 和 VERIFY_RATE 混在一起，失败时无法定位。当前阶段先补 wrapper 架构，是比较稳的拆解方式。

## 3. 修改摘要

| 文件 | 修改内容 |
|---|---|
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 新增 `GTXE2_COMMON` QPLL 实例；将 QPLLCLK/QPLLREFCLK 接入 GT Wizard channel；新增 `gt0_txsysclksel_effective` CPLL/QPLL 选择 mux；新增 QPLL lock/refclk-lost 同步寄存器与 debug 标记。 |
| `constraints/laser_tx_gt_profile0.xdc` | 在原 GTX channel LOC 基础上新增 `GTXE2_COMMON_X0Y2` LOC 约束，并更新注释说明当前 QPLL 是架构准备，active profile 仍选 CPLL。 |
| `scripts/run_qpll_wrapper_architecture_project_flow.tcl` | 新增可重复 project-flow build/report 脚本，输出到 `reports/qpll_wrapper_architecture/`。 |

未修改：

- 未修改 BD 功能连接；
- 未修改 Vitis / UDP 协议；
- 未修改 `laser_tx_core` 数据路径；
- 未修改 `pattern_tx_engine`；
- 未修改现有 GT/MMCM DRP 参数表；
- 未新增 10000M supported profile；
- 未重新导出 XSA。

## 4. 修改前问题

原 wrapper 的 GT Wizard channel 侧虽然有 QPLL 输入端口，但实际连接为常量：

```verilog
.gt0_txsysclksel_in   (2'b00),
.gt0_qplloutclk_in    (1'b0),
.gt0_qplloutrefclk_in (1'b0)
```

这表示 channel 永远选择 CPLL，且 QPLL clock/refclk path 并不存在。此时即使后续 rate controller 增加 QPLL profile，也没有真实 QPLL clock、QPLL lock、QPLL reset 和 channel PLL select 基础。

## 5. 修改后结构

### 5.1 GTXE2_COMMON / QPLL

在 `laser_gt_tx_profile0.v` 中新增 `GTXE2_COMMON` 实例 `u_gtxe2_common_qpll`，输入参考时钟使用现有 125 MHz MGT REFCLK：

```verilog
.GTREFCLK0      (gtrefclk125),
.QPLLREFCLKSEL  (3'b001),
.QPLLOUTCLK     (qplloutclk),
.QPLLOUTREFCLK  (qplloutrefclk),
.QPLLLOCK       (qplllock),
.QPLLRESET      (qpllreset_ctrl)
```

本轮 QPLL 参数来自当前工程已有 10G/QPLL 能力分析和同板参考工程的 `GTXE2_COMMON` 结构；其作用是让 QPLL primitive、clock、lock、reset path 真实进入 netlist。它不是 10G profile 的最终 DRP 参数确认，也不是 QPLL dynamic switching 验证。

### 5.2 QPLLCLK / QPLLREFCLK 接入 channel

GT Wizard channel 侧的 QPLL 输入由常量改为 COMMON 输出：

```verilog
.gt0_qplloutclk_in    (qplloutclk),
.gt0_qplloutrefclk_in (qplloutrefclk)
```

这解决了原 wrapper 中 QPLLCLK / QPLLREFCLK 不真实接入的问题。

### 5.3 CPLL/QPLL 选择结构

新增：

```verilog
assign qpll_selected = 1'b0;
assign gt0_txsysclksel_effective = qpll_selected ? 2'b11 : 2'b00;
```

当前 `qpll_selected` 故意保持为 0，因此现有 CPLL profiles 继续走 CPLL path。这里建立的是选择结构，不启用 QPLL profile。7-series GT Wizard 当前端口集中没有单独名为 `TXPLLCLKSEL` 的 wrapper 端口；本工程实际使用 `TXSYSCLKSEL` 选择 CPLL/QPLL source。

### 5.4 QPLL reset / lock debug

新增 QPLL debug-only 信号：

- `qpllreset_ctrl`
- `qpllpd_ctrl`
- `qplllock`
- `qplllock_sync`
- `qpllrefclklost`
- `qpllrefclklost_sync`
- `qplloutclk`
- `qplloutrefclk`
- `gt0_txsysclksel_effective`
- `qpll_selected`

其中 `qplllock` 与 `qpllrefclklost` 被同步到 `ctrl_clk` 域，避免后续直接跨域判断。当前这些信号已加 `keep/mark_debug`，用于保留和后续 debug 插入；本轮未修改 BD ILA probe，因此它们还不是现有 `ila_laser_axi_cfg` 的正式 probe。下一阶段若要做 QPLL 上板 bring-up，应把这些同步后的 QPLL 状态接入 AXI/FCLK ILA 或 status register。

## 6. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| `GTXE2_COMMON` | 不存在 | 新增 `u_gtxe2_common_qpll` | QPLL primitive 真实进入 design |
| QPLLCLK / QPLLREFCLK | channel 端常量 0 | 来自 `GTXE2_COMMON` 输出 | 后续 QPLL path 有真实 clock 输入 |
| QPLLLOCK | 不是真实 lock | 来自 `GTXE2_COMMON.QPLLLOCK`，并同步到 `ctrl_clk` | 后续可用于 QPLL lock wait |
| QPLLRESET | 未接入 | `qpllreset_ctrl = ctrl_rst` | wrapper 级可控；尚未接入 rate controller sequence |
| `TXSYSCLKSEL` | 固定 `2'b00` | 由 `gt0_txsysclksel_effective` mux 产生，当前仍选 CPLL | 具备后续 CPLL/QPLL 选择结构，当前 CPLL 行为不变 |
| supported rate list | 500/1000/1250/2000/2500/3125/5000/6250 | 不变 | 未开放 10G |
| rate controller | CPLL profile executor | 未改变执行行为 | 不影响现有速率功能 |
| ILA/status | 原 AXI/TX ILA | 原 ILA 保持；QPLL 内部信号 mark_debug/keep | 上板 QPLL ILA probe 仍需下一阶段补充 |
| pipeline / latency | 无关 | 无新增数据路径 pipeline | laser_tx_core 数据路径不变 |

## 7. 接口与板级一致性说明

- 顶层外部端口未新增、未删除、未改名。
- GT TX 差分输出引脚未变化：`gtx_txp_out` / `gtx_txn_out` 仍使用原约束。
- 125 MHz MGT REFCLK 引脚未变化：`gt_refclk125_p/n` 仍使用原约束。
- 新增 `GTXE2_COMMON_X0Y2` LOC，与现有 `GTXE2_CHANNEL_X0Y8` 属于同一 GTX quad 结构准备。
- 未修改 PS MIO/EMIO、AXI GPIO、BRAM、GT status AXI 地址或 Vitis 可见寄存器映射。
- 未引入 156.25 MHz REFCLK，未接 AD9528 动态输出。

## 8. 时钟与复位说明

- CPLL active profiles 的 TX user clocking 未改变，仍由 GT TXOUTCLK -> TX MMCM -> TXUSRCLK/TXUSRCLK2。
- `dbg_hub/clk` 根据 `report_debug_core` 仍为 `gt_ctrl_clk`。
- `ila_laser_axi_cfg/clk` 仍为 `u_system_wrapper/system_i/gt_ctrl_clk`。
- `ila_laser_tx/clk` 仍为 TX 域 ILA 时钟。
- 新增 QPLL COMMON 使用 `gtrefclk125` 作为 `GTREFCLK0`，`QPLLREFCLKSEL=3'b001`。
- 当前 `qpllreset_ctrl = ctrl_rst`，只是 wrapper 级 reset path；尚未实现 rate-controller-driven QPLL reset/lock sequence。

Clock/reset behavior changed intentionally：新增 QPLL COMMON reset/lock path，但现有 CPLL profile 的 clock/reset 行为预期不变。

## 9. AXI 地址与软件影响

AXI address map unchanged。

本轮没有修改 BD AXI 地址、AXI GPIO 宽度、BRAM 地址、GT status 地址或 Vitis `xparameters.h` 依赖。因此：

- 不需要重新导出 XSA；
- 不需要重建 Vitis platform/BSP；
- 不需要修改 UDP 命令格式；
- `rate list` 不应出现 10000M。

## 10. Validate / 综合实现 / 生成文件

执行脚本：

```text
scripts/run_qpll_wrapper_architecture_project_flow.tcl
```

执行结果：

```text
synth_1_STATUS = synth_design Complete!
impl_1_STATUS  = write_bitstream Complete!
impl_1_PROGRESS = 100%
```

生成文件：

```text
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit
D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx

D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/artifacts/laser_tx_board_top_qpll_wrapper_architecture.bit
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/artifacts/laser_tx_board_top_qpll_wrapper_architecture.ltx
```

报告文件：

```text
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/timing_summary_qpll_wrapper_architecture.rpt
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/utilization_qpll_wrapper_architecture.rpt
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/debug_cores_qpll_wrapper_architecture.rpt
D:/FPGA_Learn/laser_tx/reports/qpll_wrapper_architecture/clocks_qpll_wrapper_architecture.rpt
```

## 11. QoR / timing / utilization

| Metric | Result | Interpretation |
|---|---:|---|
| Setup WNS | 7.029 ns | Timing met |
| Setup TNS | 0.000 ns | 无 setup violation |
| Hold WHS | 0.045 ns | Hold met |
| Hold THS | 0.000 ns | 无 hold violation |
| LUT | 22693 | 当前实现结果 |
| FF | 21632 | 当前实现结果 |
| BRAM Tile | 61 | 当前实现结果 |
| DSP | 0 | 未使用 DSP |
| BUFGCTRL | 6 | 当前实现结果 |
| MMCME2_ADV | 1 | TX user clock MMCM |
| GTXE2_CHANNEL | 1 | 原 GT channel |
| GTXE2_COMMON | 1 | 本轮新增/启用 QPLL COMMON |

Timing 通过只说明当前实现满足已约束时序，不等价于 10G/QPLL dynamic switching 或长期硬件稳定性已经通过。

## 12. Debug core 结果

`report_debug_core -full_path` 显示：

- `dbg_hub`：implemented, inserted；
- `dbg_hub/clk = gt_ctrl_clk`；
- `ila_laser_axi_cfg`：implemented, instantiated；
- `ila_laser_axi_cfg/clk = u_system_wrapper/system_i/gt_ctrl_clk`；
- `ila_laser_tx`：implemented, instantiated。

本轮没有新增第三个 QPLL 专用 ILA，也没有把 QPLL lock/reset 直接挂入现有 AXI ILA probe。QPLL 相关信号已在 RTL 中通过 `keep/mark_debug` 保留，下一阶段如果做 10G/QPLL bring-up，应优先把 `qplllock_sync`、`qpllrefclklost_sync`、`qpllreset_ctrl`、`gt0_txsysclksel_effective` 和 QPLL reset/lock state 加入 AXI/FCLK ILA 或 status。

## 13. 功能等价性说明

Expected CPLL system behavior unchanged。

基于代码结构与 build 结果，本轮对现有 CPLL profiles 的预期影响如下：

- `qpll_selected` 固定为 0，因此 channel 仍选择 CPLL；
- `gt0_txsysclksel_effective` 在当前所有 supported profiles 下仍为 `2'b00`；
- rate controller 未修改，当前 rate set/status 行为不应变化；
- `laser_tx_core`、`pattern_tx_engine`、txdata/valid_mask 路径未修改；
- MMCM DRP、GT channel DRP、CPLL restore 逻辑未修改；
- current_rate 仍只能在 VERIFY_RATE 成功后更新。

Hardware regression was not run。本报告不能声明 500M/1000M/1250M/2000M/2500M/3125M/5000M/6250M 在本 bit 上已重新完成上板回归；只能声明 build/timing 未显示 CPLL path 的实现级退化。

## 14. 当前仍未开放 10G 的原因

本阶段只完成 QPLL-capable wrapper 架构准备，不等价于 10G dynamic profile 已实现。

当前仍未开放 10G 的原因：

- rate controller 尚未实现 QPLL profile request；
- `qpll_selected` 尚未由 profile/PLL type 控制；
- QPLLRESET 尚未纳入 rate controller reset/lock sequence；
- QPLLLOCK timeout / error_code 尚未接入执行状态机；
- 10G 的 GT channel DRP、MMCM DRP、TXUSRCLK2 expected window 尚未完成集成验证；
- 未执行 10G 上板 ILA / UDP 验证；
- 未验证外部光口质量、BER 或长期稳定性。

## 15. 下一阶段建议

下一阶段如果要进入 10G QPLL profile，应按以下顺序推进：

1. 确认 10G QPLL GT Wizard / generated HDL / official example design 参数；
2. 确认 QPLL reset / lock / refclk lost 的状态机接入方式；
3. 将 `qpll_selected` 改为 profile-driven，并保持 CPLL profile 默认路径不变；
4. 增加 QPLL lock timeout / refclk lost / PLL select mismatch 等 error_code；
5. 将 QPLL 同步状态加入 AXI/FCLK ILA 或 status；
6. 集成 10G MMCM DRP sequence 与 TXUSRCLK2 frequency window；
7. build/timing 通过后再上板验证；
8. 只有 UDP `rate set 10000`、ILA QPLL lock/ready/freq、TX data path 均通过后，才能声明 10G QPLL profile 初步通过。

## 16. 修改文件列表

| File | Change |
|---|---|
| `laser_tx.srcs/sources_1/new/laser_gt_tx_profile0.v` | 新增 QPLL COMMON、QPLL clock/refclk 接入、TXSYSCLKSEL mux、QPLL lock/refclk-lost 同步 debug。 |
| `constraints/laser_tx_gt_profile0.xdc` | 新增 `GTXE2_COMMON_X0Y2` LOC 约束，保留 `GTXE2_CHANNEL_X0Y8`。 |
| `scripts/run_qpll_wrapper_architecture_project_flow.tcl` | 新增 QPLL wrapper architecture project-flow build/report 脚本。 |
| `docs/debug_reports/32_qpll_wrapper_architecture_upgrade_report.md` | 新增本报告。 |

## 17. 边界声明

本阶段只完成 QPLL wrapper 架构升级或能力准备，不等价于 10G dynamic profile 已实现。

当前不能声明：

- 10G dynamic switching 已通过；
- QPLL profile 已上板验证通过；
- `rate set 10000` 可用；
- 任意速率动态调速完成；
- 宽范围连续调速完成；
- AD9528 动态输出完成；
- 156.25 MHz REFCLK 支持完成；
- 外部光口质量 / BER / 长期稳定性通过。


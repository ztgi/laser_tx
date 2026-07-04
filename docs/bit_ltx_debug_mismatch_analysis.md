# Vivado Hardware Manager bit/LTX 与 ILA 不匹配：根因、修复脚本与执行规程

## 1. 修改摘要

本次未修改 BD、XDC、HDL wrapper、功能 RTL、时钟/复位、AXI 地址或任何板级端口。新增/修正的是 Vivado 构建与 Hardware Manager 脚本：

| 文件 | 作用 |
|---|---|
| `scripts/run_build_bitstream.tcl` | 修正错误的 top 设置：生成 wrapper 后仍以 `laser_tx_board_top` 为综合 top |
| `scripts/verify_debug_build_inputs.tcl` | 只读预检 top、XDC、物理 SPI 端口、两颗 ILA 和 `dbg_hub` |
| `scripts/clean_rebuild_bit_ltx.tcl` | reset `synth_1`/`impl_1` 后完整重建同源 bit/LTX，并写入 manifest |
| `scripts/program_with_matching_ltx.tcl` | 只从 `laser_tx.runs/impl_1` 下载同一实现目录的 bit/LTX |
| `scripts/check_debug_cores.tcl` | 下载后检查 Hardware Manager 文件属性、ILA 和 probe 枚举结果 |

## 2. 修改前问题

问题不是单一 XDC 端口约束，也不是单纯需要 Refresh device。工程中存在两套不同的 FPGA bitstream：

| 位置 | 顶层 header | SHA-256 / 时间 | `.ltx` |
|---|---|---|---|
| `laser_tx.runs/impl_1/laser_tx_board_top.bit` | `laser_tx_board_top` | `91E7...E74B8DA`，2026-06-24 | 同目录 `laser_tx_board_top.ltx` |
| `vitis_bringup/bringup/_ide/bitstream/laser_tx_system_top.bit` | `laser_tx_system_top` | `AF0F...581CA76EB`，2026-06-26 | 无同目录 `.ltx` |

Vitis `IDE.log` 明确记录了多次：

```text
Device configured successfully with
.../vitis_bringup/bringup/_ide/bitstream/laser_tx_system_top.bit
```

因此，只要 Vitis Debug/Launch 在 Hardware Manager 下载前后执行，它就会把 FPGA 改写为 `laser_tx_system_top.bit`。随后将 `laser_tx_board_top.ltx` 关联到器件，会因两次实现的 debug UUID/层级不同而出现：

```text
The device design has 2 ILA core(s)
0 ILA core(s) ... are matched in the probes file(s)
```

这与所见“器件中有两颗 ILA、LTX 中也有两颗 ILA、但 0 匹配”完全一致。根因是**不同 build provenance 的 bit/LTX 混用及 Vitis 自动重配置**。

另一个构建风险已发现并修复：原 `scripts/run_build_bitstream.tcl` 在生成 `system_wrapper` 后执行：

```tcl
set_property top system_wrapper [get_filesets sources_1]
```

这会绕开用户维护的 `laser_tx_board_top`，也绕开 SS2 内部吸收的板级封装层，可能再次产生错误 top 的 bitstream。该行已改为 `laser_tx_board_top` 并增加一致性检查。

## 3. 修改后结构

构建与下载流程固定为：

```text
laser_tx_board_top
  -> clean_rebuild_bit_ltx.tcl
  -> laser_tx.runs/impl_1/laser_tx_board_top.bit
  -> laser_tx.runs/impl_1/laser_tx_board_top.ltx
  -> laser_tx_board_top.bit_ltx_manifest.txt
  -> program_with_matching_ltx.tcl
  -> check_debug_cores.tcl
```

`program_with_matching_ltx.tcl` 不会读取 `vitis_bringup` 下的任何 bitstream；它要求 manifest、bit 和 LTX 都位于同一个 `impl_1` 目录，并自动选择唯一的 `xc7z100*` Hardware Manager device。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
|---|---|---|---|
| 综合 top | 普通 build 脚本会改成 `system_wrapper` | 固定并检查 `laser_tx_board_top` | 保留板级封装和 SS2 内部 tie-off |
| bit/LTX 选择 | 可手工选择多个目录中任意文件 | 固定为同一个 `impl_1` 目录和 manifest | 消除旧/新、Vitis/工程产物混用 |
| ILA 检查 | 仅依赖 Hardware Manager 警告 | 构建后检查两颗 ILA、`dbg_hub` 和 probes 枚举 | 可区分生成问题、匹配问题和时钟问题 |
| Vitis 自动下载 | 可在不显眼处覆盖 FPGA | 明确禁止与 board-top LTX 混用 | 消除重配置导致的 UUID 不匹配 |
| XDC/端口检查 | 无自动门禁 | 检查无 `SPI_1_0_ss2_o` XDC 且 SPI 端口精确匹配 | 防止顶层回退 |

## 5. 接口与板级一致性说明

已用 Vivado `open_run synth_1` 和 `open_run impl_1` 实测：

```text
get_ports *ss2*     -> 空
get_ports SPI_1_0*  ->
SPI_1_0_io0_io SPI_1_0_io1_io SPI_1_0_sck_io
SPI_1_0_ss_io SPI_1_0_ss1_o
```

`rtl/laser_tx_board_top.v` 仅导出 SS0/SS1，`SPI_1_0_ss2_o` 接到内部 `spi_ss2_unused`。`constrs_1` 的 XDC 检查通过，未发现 `SPI_1_0_ss2_o` 约束。顶层端口、方向、位宽、IOSTANDARD、封装引脚均未修改。

## 6. 时钟与复位说明

时钟与复位拓扑未修改。当前 BD 脚本中：

- `ila_laser_axi_cfg/clk` 接 `processing_system7_0/FCLK_CLK0`；
- `ila_laser_tx/clk` 接 `laser_tx_core_0/txusrclk2`；
- 第一阶段临时模式中 `txusrclk2` 接 `FCLK_CLK0`。

Clock/reset behavior unchanged。

如果 bit/LTX 文件属性已匹配、但 `get_hw_ilas` 仍为空，下一优先级不是更换 LTX，而是确认 PS 已启动 FCLK。对 Zynq，下载 PL bitstream 后需通过既有 standalone/Vitis PS 初始化流程使 FCLK free-running，再 refresh Hardware Device。

## 7. AXI 地址与软件影响

AXI address map unchanged。未修改 BD、PS、AXI GPIO、BRAM、地址分配、Vitis 源码、BSP 或 XSA。

但是 Vitis 调试启动会自动下载 `laser_tx_system_top.bit`，这属于运行流程风险而非软件寄存器接口变化。使用 Hardware Manager 的 board-top 调试流程时，不要执行会调用下列命令的 Vitis launch 配置：

```tcl
fpga -file .../laser_tx_system_top.bit
```

若 Vitis 必须负责配置 FPGA，应在单独任务中从新的 `laser_tx_board_top` hardware export 重新生成 platform，并同时交付该 platform 的配套 LTX；当前脚本流程不混用 Vitis bitstream。

## 8. Validate Design / 生成文件 / 综合实现

已执行只读 Vivado preflight：

```powershell
D:\Vivado\2022.2\bin\vivado.bat -mode batch -nolog -nojournal `
  -source scripts/verify_debug_build_inputs.tcl
```

结果：

- `get_property top [current_fileset]` = `laser_tx_board_top`；
- `synth_1` 与原 `impl_1` 均发现 `ila_laser_tx`、`ila_laser_axi_cfg` 和 `dbg_hub`；
- LTX 中的 UUID 为：
  - `u_system_wrapper/system_i/ila_laser_axi_cfg`：`5FAAA34285FA5C26A51622F702DD0D1D`；
  - `u_system_wrapper/system_i/ila_laser_tx`：`154104E022E159959FD81F1488F3C7C5`。

随后已启动 `clean_rebuild_bit_ltx.tcl`。综合完成并通过 post-synth 检查，但 implementation 未开始：当前用户 Vivado GUI 占用同一工程 run 队列，`impl_1` 停在 `.Vivado_Implementation.queue.rst`，未生成 `runme.log`、新 `.bit` 或 `.ltx`。为避免终止用户 GUI，已停止本次 batch 等待进程。

因此：

```text
Validate Design was not run in this change.
Clean implementation/bitstream was not completed because the project GUI held the run queue.
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

## 9. QoR / timing / utilization 对比

本次仅修改构建/下载脚本，不改变网表功能。没有新的 completed implementation，因此没有新的 QoR 对比，也不应宣称 timing 改善。

```text
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

## 10. 功能等价性说明

Expected system behavior unchanged。

依据：未修改 RTL、BD、wrapper、XDC、IP 参数、外部端口、时钟/复位、AXI 地址和 Vitis 软件。唯一改变是构建脚本不再错误地覆盖 `laser_tx_board_top` 为 `system_wrapper`，这使实际构建与项目既定板级 top 一致。该结论基于结构检查；尚未完成本次新 bitstream 的硬件下载测试。

## 11. 修改文件列表

| 文件 | 修改 |
|---|---|
| `scripts/run_build_bitstream.tcl` | top 从 `system_wrapper` 更正为 `laser_tx_board_top`，新增 top 断言 |
| `scripts/verify_debug_build_inputs.tcl` | 新增只读 Vivado 预检 |
| `scripts/clean_rebuild_bit_ltx.tcl` | 新增 clean rebuild、ILA/端口/XDC 检查、manifest 生成 |
| `scripts/program_with_matching_ltx.tcl` | 新增同源 bit/LTX 下载脚本 |
| `scripts/check_debug_cores.tcl` | 新增 Hardware Manager ILA/probe 与时钟诊断 |
| `docs/bit_ltx_debug_mismatch_analysis.md` | 新增本报告 |

## 12. 风险与后续建议

1. 先关闭当前打开 `laser_tx.xpr` 的 Vivado GUI，确保没有 `.Vivado_Implementation.queue.rst` 占用，再从项目根目录执行：

   ```powershell
   D:\Vivado\2022.2\bin\vivado.bat -mode batch -source scripts/clean_rebuild_bit_ltx.tcl
   ```

2. 脚本成功后只执行：

   ```powershell
   D:\Vivado\2022.2\bin\vivado.bat -mode tcl -source scripts/program_with_matching_ltx.tcl
   source scripts/check_debug_cores.tcl
   ```

3. 执行 Hardware Manager 调试期间，不要运行会下载 `vitis_bringup/.../laser_tx_system_top.bit` 的 Vitis Debug/Launch。若已执行，重新运行 `program_with_matching_ltx.tcl`；这不是普通 Refresh 能修复的问题。
4. 若文件属性已指向 clean `impl_1` pair 而 `get_hw_ilas` 为 0，启动 PS/FCLK 后再 refresh；若发现 2 个 ILA，则匹配和 debug hub 都正常。
5. 在真实 GT user clock 接入后，仍需重新运行 implementation 和 timing；本脚本没有改变该要求。

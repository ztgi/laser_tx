# laser_tx_core Vivado 集成（TX Sequence V2）

## 1. 顶层结构

`laser_tx_core` 通过 BRAM Port B 读取配置，PS 通过 AXI BRAM Controller /
Port A 写入。V2 record 固定为 16 word，BRAM 地址步进为 4 byte、record
步进为 64 byte。

| BRAM 信号 | 方向 | 关系 |
|---|---:|---|
| bram_clk | output | axi_clk |
| bram_rst | output | `~axi_rstn`，高有效 |
| bram_en | output | loader 读使能 |
| bram_we[3:0] | output | 0 |
| bram_addr[31:0] | output | byte address |
| bram_din[31:0] | output | 0 |
| bram_dout[31:0] | input | Port B read data |

PS 先写 invalid header，再写 payload/CRC，最后提交 valid header。PL 只有在
16-word record 完整且 CRC/metadata/header 稳定时更新 active config。

## 2. Module Reference

`system.bd` 中的 module reference 为 `system_laser_tx_core_0_0`。修改
`laser_tx_core` 或子模块后必须：

1. 确认新源已加入 `sources_1`；
2. 对 module reference 执行 Refresh Changed Modules /
   `update_module_reference`；
3. 执行 `validate_bd_design`；
4. 更新 compile order；
5. 生成并核对 HDL wrapper；
6. 重新生成 output products、OOC synthesis 与 top implementation。

本轮使用 `scripts/refresh_tx_sequence_v2_bd_module_refs.tcl` 完成前五项，
结果为 `TX_SEQUENCE_V2_REFRESH_PASS`。`tx_eom_geometry_precompute.v` 和
`tx_eom_window_generator.v` 已进入 compile order；生成 wrapper 与 tracked
wrapper 的内容哈希一致。

## 3. AXI GPIO / BRAM / 地址

现有 AXI GPIO、AXI BRAM 和动态 rate mailbox 地址保持不变。V2 没有修改：

- AXI base address；
- GPIO bitfield；
- config select/apply toggle 的对外接口；
- PS SPI/UART/Ethernet 配置；
- GT supported rate ID。

`SELECT_CONFIG` 的 index 扩展为 0..127，但仍通过既有 config-index 控制字段
传递；record 的 source/length/phase/loop 不再由 `SELECT_CONFIG` 参数传入。

## 4. TX 与 EOM 时钟

- pattern engine 使用 `TXUSRCLK2`；
- EOM window 使用 profile 相关的 EOM clock；
- 500M/1000M/2000M 的 EOM clock 均为 125 MHz；
- 相应 K 为 16/8/4，EOM tick 均为 8 ns；
- TXDATA 保持 64-bit、`PIPELINE_LATENCY=0`。

EOM geometry 在 TX domain 计算，被选 window 在 EOM clock domain 输出。
reset、MMCM/GT not-ready 或 abort 必须通过 clock-safe 立即拉低 EOM。

当前 refresh 前 routed DCP 显示 TXUSRCLK2 与 EOM clock 之间仍有 setup/hold
失败和 CDC Critical。该结构尚不能作为上板安全结论，必须独立修复 CDC 并
重新实现，不能用 false path 掩盖功能跨域。

## 5. 外部同步端口

外部端口保持：

- `eom_out_0`
- `soa_gate_out_0`
- `acq_trig_out_0`
- `acq_gate_out_0`

没有新增、删除、重命名或改变方向/宽度。现有 routed timing report 指出这
四个 port 缺少 output delay；必须在板级接收时序模型明确后补充合理约束，
不能猜测数值。

## 6. ILA 建议

### AXI/config ILA（axi_clk）

- config index/apply toggle；
- BRAM enable/address/data；
- config loader state/error；
- header/sequence、CRC pass/fail；
- active config 更新脉冲。

### TX ILA（TXUSRCLK2）

- engine start/busy/done/state；
- txdata/valid_mask；
- phase offset；
- repeat index、gap index；
- head/gap/pattern active；
- EOM arm、geometry ready/request valid；
- selected phase/repeat。

### EOM/control ILA（稳定控制时钟或经同步后的状态）

- EOM active/fired/done；
- clock-safe；
- GT/MMCM ready/lock 的同步版本；
- abort/reset；
- profile EOM K/serial bits per tick。

不得把未经同步的跨域多位总线直接接入不相关时钟域 ILA。

## 7. V2 上板前验证顺序

当前阶段只完成仿真和软件 clean build；由于 EOM 公共 CDC/timing 不通过，
不建议下载当前 V2。

CDC/timing 修复并重新实现后，按以下顺序：

1. `DISABLE`；
2. `WRITE_CONFIG` 写入完整 V2 record；
3. `SELECT_CONFIG <index>`；
4. `APPLY`；
5. 检查 loader/CRC/active config；
6. `ENABLE`；
7. 用 ILA 检查 HEAD、N pattern、N-1 gap、phase 扫描；
8. 检查 global EOM 只触发一次；
9. loop 运行时 EOM 不重复；
10. reset/abort/MMCM unlock 时 EOM 立即拉低；
11. 分别验证 500M、1000M、2000M。

## 8. 当前验证状态

- Module Reference refresh：PASS；
- Validate Design：PASS（warning 见 53 号报告）；
- wrapper 接口核对：PASS；
- V2 protocol/RTL regression：PASS；
- Vitis managed clean build：PASS；
- refresh 后 synthesis/implementation：未运行；
- timing signoff：未通过；
- bit/LTX/XSA：未生成；
- hardware test：未运行。

详细结果见 `debug_reports/53_tx_sequence_v2_low_speed_validation_report.md`。

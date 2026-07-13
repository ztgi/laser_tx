# AD9528 OUT0 软件频率回读工程报告

## 1. 本阶段目标与边界

本阶段把既有 `IBUFDS_GTE2.ODIV2 -> Gray CDC -> gt_ctrl_clk 1 ms delta` 测量结果通过专用只读 AXI GPIO 暴露给 PS，并在 Vitis/UDP 中提供一致快照读取和整数频率换算。既有 ILA 继续保留。

本阶段不修改 Bank111 GTX REFCLK、GTNORTHREFCLK、CPLL/QPLL/MMCM DRP、rate profile、RATE_ID、普通 `rate set`、激光数据路径、trigger/gate/reset sequence，也不把 AD9528 candidate 自动标记为 supported 或 `board_verified=1`。

## 2. 修改前问题与只读检查

修改前，`rtl/laser_tx_board_top.v` 已在 `gt_ctrl_clk` 域锁存完整 1 ms ODIV2 delta，并生成 `alive/in_range/valid`；PS 不能访问这些值，因此 UDP 只能输出 `measured_out0_hz=UNKNOWN`。PS 不能直接读取 ODIV2 源域自由运行计数器，也不能在 count 和 status 分两次读取时忽略 1 ms 更新边界。

只读检查结论：

- `ad9528_odiv2_count_axi` 是 `gt_ctrl_clk` 域锁存的完整窗口 delta，不是 ODIV2 源域二进制计数器；
- 五个既有 ILA 观测量均在 `gt_ctrl_clk` 域产生；
- 现有 `axi_gpio_0` 的两个通道分别承担 control 和 laser status，`axi_gpio_gt_status` 承担 GT/rate status，没有可安全重解释的空闲 PS-readable channel；
- 两个既有 AXI GPIO 均由 PS FCLK0/`gt_ctrl_clk` 50 MHz 驱动；
- 修改前 BSP 中 AXI GPIO 仅有 `0x41200000` 和 `0x40020000` 两个实例；
- 因此采用优先级中的第二方案：新增专用双通道只读 AXI GPIO，不新增自定义 AXI-Lite slave。

以上结论来自当前 RTL、BD、旧 BSP `xparameters.h` 和 Vitis 源码的结构检查。

## 3. 修改后架构

```text
ODIV2 source counter
 -> registered Gray code
 -> 2FF CDC into 50 MHz gt_ctrl_clk
 -> 1 ms delta/count/flags snapshot
 -> sequence/version/status word
 -> dedicated dual-channel AXI GPIO
 -> XGpio coherent read
 -> uint64_t integer frequency conversion
 -> UDP read-only status
```

每个 1 ms 窗口同时更新 count、flags 和 16-bit sequence。软件按 `status_before -> count -> status_after` 读取；sequence 不一致时最多重试 4 次。format/version 不匹配、无有效窗口或读取无法收敛时不返回缓存频率冒充当前值。

## 4. AXI 设备与寄存器映射

| 项目 | 定义 |
| --- | --- |
| BD instance | `axi_gpio_ad9528_measure` |
| AXI base | `0x40030000` |
| AXI range | 64 KiB |
| AXI clock | PS FCLK0 / `gt_ctrl_clk` = 50 MHz |
| AXI reset | `rst_ps7_0_50M/peripheral_aresetn` |
| Channel 1 | `measurement_count[31:0]`, input-only |
| Channel 2 | `measurement_status[31:0]`, input-only |

`measurement_status[31:0]`：

| 位 | 含义 |
| --- | --- |
| `[31:16]` | `measurement_sequence` |
| `[15:8]` | reserved，固定 0 |
| `[7:4]` | format/version，当前为 1 |
| `[3]` | reserved，固定 0 |
| `[2]` | `odiv2_alive` |
| `[1]` | `measurement_in_range` |
| `[0]` | `measurement_valid` |

## 5. 修改前后差异

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| PS 测量访问 | 无 | 专用双通道只读 AXI GPIO | 新增软件可见只读接口 |
| count 来源 | 仅 ILA | 同一 `gt_ctrl_clk` snapshot 同时给 ILA/PS | 不读取源域计数器 |
| 快照一致性 | 不涉及 PS | sequence 前后检查，最多 4 次 | 防止跨窗口撕裂 |
| 频率换算 | 软件 UNKNOWN | `uint64_t count*1000`、`count*2000` | 无浮点 |
| candidate set/restore | 仅寄存器状态 | 成功后等待新 sequence，旧快照不作为当前值 | apply/restore 写序列不变 |
| GT/rate 数据路径 | 已验证路径 | 未修改 | 预期功能不变 |
| pipeline latency | 原值 | 未修改 | 无影响 |
| CDC | Gray+2FF | 原 CDC 保持，仅增加目标域 snapshot 输出 | 无新异步总线同步 |

## 6. RTL、BD、XDC、Vitis 修改

### 6.1 RTL

`rtl/laser_tx_board_top.v` 新增 sequence、format/version status word，并把既有 count/status snapshot 接到 wrapper。没有修改 ODIV2 counter、Gray CDC、GT/rate controller 或激光发送逻辑。

### 6.2 BD / wrapper / XSA

`system.bd` 新增 input-only dual-channel AXI GPIO；SmartConnect master 数量由 3 增为 4；PS 地址空间新增 `0x40030000/64K`；wrapper 新增两个内部 32-bit input。外部板级端口、PS MIO/EMIO、SPI、interrupt 和既有 AXI 地址均未改变。

Clock/reset behavior unchanged：新增 GPIO 复用现有 50 MHz FCLK0 和 `peripheral_aresetn`。AXI address map changed intentionally：仅新增测量 GPIO 地址，既有地址不移动。XSA / Platform / BSP dependency changed intentionally：Vitis 必须使用本次导出的 XSA 重建 platform/BSP。

### 6.3 XDC

本阶段未修改 XDC；AA8/AA7、`IBUFDS_GTE2`、ODIV2/BUFG 与既有测量时钟约束沿用上一阶段实现。

### 6.4 Vitis / UDP

新增 `laser_ad9528_measure.c/.h`，使用 `XGpio` 和新 BSP 命名宏访问专用 GPIO。新增只读命令：

```text
ad9528 measure status
```

`ad9528 candidate set/status/restore` 追加 measurement 字段；invalid 时 count/frequency 输出 `UNKNOWN`。candidate set/restore 成功后记录 transition sequence，下一完整窗口到来前不回报旧值。AD9528 SPI controller、SS、CPOL/CPHA、register write/readback、IO_UPDATE 和 rollback 实现均未改变。

## 7. 功能等价性与接口一致性

Functional behavior changed intentionally：新增 PS 只读测量接口和 UDP 查询字段。

除上述只读可见性外，预期系统行为不变。依据 RTL/BD/Vitis 结构检查：

- data/valid alignment、trigger pulse、reset、rate FSM、GT/MMCM DRP、candidate apply/restore 寄存器顺序未修改；
- 未新增 pipeline，接口 latency 不变；
- 新 AXI GPIO 为 input-only，不反馈功能逻辑；
- 既有 AXI base address、GPIO control bitfield 和 UDP 命令语义保持；
- Bank111 125 MHz GT 功能 REFCLK 结构未修改；
- 无 interrupt、DMA、cache-coherency 或 linker script 修改。

上述功能等价结论在上板前仅基于结构检查与 build，不等同于硬件回归。

## 8. 静态测试

`scripts/check_ad9528_measurement_interface.py` 检查 RTL/C 常量一致性，并覆盖：正常读取、sequence 跨窗口重试、valid=0、valid=1/in_range=0、format mismatch、64-bit 换算和 transition sequence 失效旧快照。

结果：`PASS: AD9528 measurement constants and coherent-read scenarios`。

## 9. Vivado / Vitis 构建结果

### 9.1 Vivado

执行：

```text
vivado.bat -mode batch -source scripts/run_ad9528_measurement_readback_build.tcl -notrace
```

结果：

- `validate_bd_design`、`save_bd_design`、output products 生成和 wrapper 更新完成；
- `synth_1`、`impl_1`、`write_bitstream`、`write_debug_probes` 完成；
- route status：40468/40468 条 routable nets fully routed，routing errors=0；
- setup WNS=7.029 ns，TNS=0，setup failing endpoints=0；
- hold WHS=0.023 ns，THS=0，hold failing endpoints=0；
- DRC：0 Error、5 Warning，其中 4 条 `PDCN-1569` 和 1 条 `RTSTAT-10` 均与 debug/LUT 无负载网络有关；未出现 `UCIO-1`、`NSTD-1` 或 GT REFCLK DRC；
- debug report 中 `dbg_hub`、`ila_laser_axi_cfg`、`ila_laser_tx` 和既有 `ila_ad9528_out0_measure` 均存在；
- XSA 导出完成。

CDC 报告仍将 ODIV2 Gray bus 标记为 `CDC-6 Multi-bit synchronized with ASYNC_REG`。该路径是既有的 registered Gray counter -> 2FF synchronizer 结构；本轮新增 AXI GPIO 只读取 `gt_ctrl_clk` 域 snapshot，没有新增异步总线跨越。完整 CDC 报告仍包含工程既有 debug/GT 跨域告警，因此本报告不将“build 通过”扩大为“全部 CDC 告警清零”。

### 9.2 静态接口检查

执行：

```text
python scripts/check_ad9528_measurement_interface.py
```

结果：

```text
PASS: AD9528 measurement constants and coherent-read scenarios
```

### 9.3 Vitis

由新 XSA 更新 platform/BSP 后，`xparameters.h` 生成第三个 XGpio 实例：

```text
XPAR_AXI_GPIO_AD9528_MEASURE_BASEADDR = 0x40030000
XPAR_AXI_GPIO_AD9528_MEASURE_HIGHADDR = 0x4003FFFF
XPAR_AXI_GPIO_AD9528_MEASURE_DEVICE_ID = 2
```

Vitis 2022.2 GUI workspace 当时处于占用状态，XSCT 无法建立 IDE channel；因此没有修改或提交 GUI 自动生成的 platform 元数据。随后使用该 platform/BSP 和 Vitis managed makefile 执行 `make clean` 与完整应用 build，新文件 `laser_ad9528_measure.c` 已实际编译并链接。

结果：compiler errors=0，link=PASS；未出现 compiler warning。ELF size：

| 段 | 大小（byte） |
| --- | ---: |
| text | 174751 |
| data | 3448 |
| bss | 3201088 |

本轮未修改 linker script、heap、stack、cache/MMU 配置，也未增加大块全局缓冲。`bss` 主要仍由既有应用缓冲构成；建议上板前继续使用当前 linker map/DDR 启动配置。

## 10. 软件命令与预期结果

```text
ad9528 candidate restore
ad9528 measure status

ad9528 candidate set vcxo_122p88
等待 measurement_sequence 更新
ad9528 measure status
ad9528 candidate status

ad9528 candidate restore
等待 measurement_sequence 更新
ad9528 measure status
ad9528 candidate status
```

candidate set 稳定后的预期是 count 约 61437～61440、ODIV2 约 61.437～61.440 MHz、OUT0 约 122.874～122.880 MHz，且 valid/alive/in_range 为 1。该数值是基于上一阶段 ILA 证据的预期；新 PS/UDP 回读尚未上板验证。

## 11. 生成文件路径

- bit：`D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit`
- LTX：`D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx`
- XSA：`D:/FPGA_Learn/laser_tx/reports/ad9528_out0_software_readback/laser_tx_board_top_ad9528_measure.xsa`
- ELF：`D:/FPGA_Learn/laser_tx/vitis_bringup/bringup/Debug/bringup.elf`

上述 bit/LTX/XSA/ELF 均为本地生成物，不提交 Git。

## 12. QoR / utilization

本次不是时序优化任务，且没有同一基线的修改前实现报告，因此不能声明 QoR 改善。修改后结果如下：

| Metric | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Setup WNS | 未提供同基线报告 | 7.029 ns | 满足当前约束 |
| Setup TNS | 未提供同基线报告 | 0 ns | 无 setup failing endpoint |
| Hold WHS | 未提供同基线报告 | 0.023 ns | hold 通过 |
| Hold THS | 未提供同基线报告 | 0 ns | 无 hold failing endpoint |
| LUT | 未提供同基线报告 | 24699 | 新增 AXI GPIO/sequence 逻辑后的总量 |
| FF | 未提供同基线报告 | 24565 | 同上 |
| BRAM tile | 未提供同基线报告 | 63.5 | 未新增软件读回 BRAM |
| DSP | 未提供同基线报告 | 0 | 无硬件除法器/DSP |
| BUFG/MMCM | 未提供同基线报告 | 7 / 1 | 测量时钟结构沿用 |
| GTXE2_CHANNEL/COMMON | 未提供同基线报告 | 1 / 1 | Bank111 GT 结构未变 |

## 13. 风险与后续建议

- 新 AXI GPIO、BSP device ID 和 UDP 回读需要实际上板验证；
- `in_range=0` 仅表示当前窗口不在候选范围，不等同于 SPI/apply 失败；
- 当前只报告单个 snapshot，没有实现连续多窗口稳定判定；
- `board_verified` 继续保持 0；
- 不声明示波器、Bank110->Bank111 GTNORTHREFCLK、外部光口、BER 或新 GT profile 已完成。
- Hardware test was not run for the new PS/UDP readback path；上一阶段 ILA 的约 61437 计数只能作为本轮上板预期，不能代替新接口实测。

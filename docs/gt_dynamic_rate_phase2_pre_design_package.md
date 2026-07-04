# GT 动态速率第二阶段前置设计包：1000M 对比与动态 TX 用户时钟方案

## 1. 本阶段目标与边界

本阶段只做“进入 GTX 动态速率实现前”的工程可行性核查与设计包整理，不实现实际运行时速率切换。

本阶段明确不做：

- 不实现 `rate set 500/1000` 的真实硬件动作；
- 不写 GTX DRP；
- 不修改 `laser_tx_core` 功能逻辑；
- 不修改当前已上板验证的固定 500 Mb/s Profile 0 发送链路；
- 不修改 BD / XDC / wrapper / XSA；
- 不重新生成 bitstream；
- 不声明 1000M 或动态速率已经上板通过。

本阶段完成：

- 生成隔离的 1000M GT Wizard 对比工程；
- 对比当前 500M Profile 0 与 1000M TX 配置差异；
- 提取 GT Wizard example design 中官方 TX user clocking 结构；
- 给出动态 TXUSRCLK/TXUSRCLK2 方案候选；
- 给出 `laser_gt_rate_ctrl` 接口与软件寄存器草案；
- 列出真正进入 RTL/BD/XDC/Vitis 修改前必须确认的条件。

## 2. 为什么当前不能直接写 DRP

当前固定 500 Mb/s Profile 0 的结构不是“只要改 GTX TXOUT_DIV 就能自动完成速率切换”的结构。

当前工程已验证链路中：

- line rate = 500 Mb/s；
- TXDATA width = 64 bit；
- TX internal datapath = 32 bit；
- TXOUT_DIV = 8；
- TXOUTCLK = 15.625 MHz；
- TXUSRCLK = 15.625 MHz；
- TXUSRCLK2 = 7.8125 MHz；
- `laser_tx_core`、TX ILA、`txdata[63:0]` / `valid_mask[63:0]` 运行在 TXUSRCLK2 域。

1000M TX 对比结果表明：

- TXOUT_DIV 需要从 8 变为 4；
- TXOUTCLK 将从 15.625 MHz 变为 31.25 MHz；
- TXUSRCLK 应变为 31.25 MHz；
- TXUSRCLK2 应变为 15.625 MHz；
- GT Wizard example design 对 500M 与 1000M 使用了不同 MMCM 参数。

因此运行时切速率至少涉及：

1. GTX/CPLL/TX divider 相关 DRP；
2. TX user clock MMCM 重配置或可控切换；
3. GT TX reset sequence；
4. MMCM lock / CPLL lock / txresetdone / gt_ready 状态机；
5. 多频率 XDC / CDC / ILA 采样时钟约束；
6. Vitis 软件命令与状态暴露。

如果只写 TXOUT_DIV，而不处理 TXUSRCLK/TXUSRCLK2，`laser_tx_core` 的每拍 64-bit 发送语义和 GT 用户接口时序将不自洽。

## 3. 1000M GT Wizard 对比生成结果

本轮新增脚本：

```text
scripts/create_gtwizard_1000m_compare.tcl
```

该脚本不打开、不修改 `laser_tx.xpr`。它将当前 Profile 0 XCI 复制到 `reports/` 下，在隔离 Vivado project 中设置 1000M TX 对比参数，并生成 output products 与 example design。

生成位置：

```text
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/
```

关键输出：

```text
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/gtwizard_1000m_selected_properties.txt
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/gtwizard_1000m_generation_summary.txt
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/copied_ip/gtwizard_0.xci
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/generated_ip/gtwizard_0/
reports/gt_dynamic_rate_phase2_design_pkg/gtwizard_1000m_compare/example_design/gtwizard_0_ex/
```

脚本运行命令：

```powershell
& 'D:\Vivado\2022.2\bin\vivado.bat' -mode batch -source 'D:\FPGA_Learn\laser_tx\scripts\create_gtwizard_1000m_compare.tcl'
```

脚本运行结果：

```text
OK generate_target all
OK open_example_project
```

注意：Vivado 在设置 RX line rate 时输出 disabled parameter warning。脚本最终 selected properties 显示：

```text
gt0_val_tx_line_rate = 1.0
gt0_val_rx_line_rate = 0.5
gt0_val_cpll_txout_div = 4
gt0_val_cpll_rxout_div = 4
```

本阶段只把该结果作为 TX 方向动态速率规划依据；RX line-rate 参数未形成完整一致的 1000M 对比结论，后续如需要 RX 或全双工动态速率，必须重新单独确认。

## 4. 500M Profile 0 与 1000M TX 对比

| 项目 | 当前 Profile 0 500M | 隔离 1000M TX 对比 | 结论 |
| --- | --- | --- | --- |
| TX line rate | 0.5 Gb/s | 1.0 Gb/s | 目标速率翻倍 |
| TXDATA width | 64 bit | 64 bit | 外部 TXDATA 保持 64 bit，不应改 `laser_tx_core` 数据宽度 |
| Encoding | None | None | 无 8b/10b 编码开销 |
| TX internal datawidth | 32 | 32 | GT 内部 datapath 语义不变 |
| CPLL_FBDIV | 4 | 4 | 未观察到变化 |
| CPLL_FBDIV_45 | 4 | 4 | 未观察到变化 |
| CPLL_REFCLK_DIV | 1 | 1 | 未观察到变化 |
| TXOUT_DIV | 8 | 4 | TX 速率变化的主要 GT divider 差异 |
| RXOUT_DIV | 8 | 4 | 生成 HDL 中变化，但 RX line-rate property 仍显示 0.5，需后续确认 |
| TXOUTCLK | 15.625 MHz | 31.25 MHz | 随 TXOUT_DIV 变化 |
| TXUSRCLK | 15.625 MHz | 31.25 MHz | 应与 TXOUTCLK 同频 |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz | `laser_tx_core` 运行频率会翻倍 |
| TXUSRCLK:TXUSRCLK2 | 2:1 | 2:1 | 关系保持，但频率改变 |

当前结论：对于 TX 方向 500M ↔ 1000M，已观察到的 GT primitive 参数差异主要是 `TXOUT_DIV` 从 8 到 4，同时 user clock MMCM 参数必须改变。

## 5. 官方 example design 的 TX user clocking 对比

500M Profile 0 example design：

```verilog
gtwizard_0_CLOCK_MODULE #(
    .MULT        (39.0),
    .DIVIDE      (1),
    .CLK_PERIOD  (64.0),
    .OUT0_DIVIDE (78.0), // TXUSRCLK2 = 7.8125 MHz
    .OUT1_DIVIDE (39)    // TXUSRCLK  = 15.625 MHz
)
```

1000M TX 对比 example design：

```verilog
gtwizard_0_CLOCK_MODULE #(
    .MULT        (20.0),
    .DIVIDE      (1),
    .CLK_PERIOD  (32.0),
    .OUT0_DIVIDE (40.0), // TXUSRCLK2 = 15.625 MHz
    .OUT1_DIVIDE (20)    // TXUSRCLK  = 31.25 MHz
)
```

两者共同结构：

```text
GT TXOUTCLK -> BUFG -> MMCME2_ADV -> BUFG -> TXUSRCLK
                                  -> BUFG -> TXUSRCLK2
```

结论：

- 官方 example design 使用 MMCM 生成 TXUSRCLK/TXUSRCLK2；
- 500M 与 1000M 的 MMCM 参数不同；
- `TXUSRCLK = 2 * TXUSRCLK2` 关系保持；
- 不能用普通 fabric 逻辑分频生成 GT 用户时钟；
- 动态速率实现必须把 GTX DRP 与 TX user clock MMCM 管理放在同一个受控状态机里。

## 6. 候选 DRP 差异表

下表不是可直接写硬件的 DRP 表，而是从当前 500M XCI/generated HDL 与隔离 1000M XCI/generated HDL 的参数差异整理出的候选修改项。当前 XCI/generated HDL 给出了 primitive generic 差异，但没有直接给出可安全写入的 DRP address/bitfield，因此地址栏标记为待确认。

### 6.1 500M -> 1000M 候选项

| DRP 地址 | Bits | 500M 值 | 1000M 值 | 含义 | 来源 | RMW 要求 | 风险 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 待 UG476 / GT Wizard DRP map 确认 | 待确认 | TXOUT_DIV=8 | TXOUT_DIV=4 | TX 输出 divider | 500/1000 generated HDL parameter delta | 必须 RMW，不能覆盖同寄存器其他位 | 高；未确认 address/bitfield 前禁止写 |
| 待 UG476 / GT Wizard DRP map 确认 | 待确认 | RXOUT_DIV=8 | RXOUT_DIV=4 | RX 输出 divider | 500/1000 generated HDL parameter delta | 必须 RMW，不能覆盖同寄存器其他位 | 高；本阶段 TX 优先，RX line-rate 仍有不一致 |
| 暂无变化 | 不适用 | CPLL_FBDIV=4 | CPLL_FBDIV=4 | CPLL feedback divider | generated HDL parameter delta | 不应写 | 低；当前对比未显示变化 |
| 暂无变化 | 不适用 | CPLL_REFCLK_DIV=1 | CPLL_REFCLK_DIV=1 | CPLL refclk divider | generated HDL parameter delta | 不应写 | 低；当前对比未显示变化 |

### 6.2 1000M -> 500M 候选项

| DRP 地址 | Bits | 1000M 值 | 500M 值 | 含义 | 来源 | RMW 要求 | 风险 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 待 UG476 / GT Wizard DRP map 确认 | 待确认 | TXOUT_DIV=4 | TXOUT_DIV=8 | TX 输出 divider | 1000/500 generated HDL parameter delta | 必须 RMW，不能覆盖同寄存器其他位 | 高；未确认 address/bitfield 前禁止写 |
| 待 UG476 / GT Wizard DRP map 确认 | 待确认 | RXOUT_DIV=4 | RXOUT_DIV=8 | RX 输出 divider | 1000/500 generated HDL parameter delta | 必须 RMW，不能覆盖同寄存器其他位 | 高；本阶段 TX 优先，RX line-rate 仍有不一致 |
| 暂无变化 | 不适用 | CPLL_FBDIV=4 | CPLL_FBDIV=4 | CPLL feedback divider | generated HDL parameter delta | 不应写 | 低 |
| 暂无变化 | 不适用 | CPLL_REFCLK_DIV=1 | CPLL_REFCLK_DIV=1 | CPLL refclk divider | generated HDL parameter delta | 不应写 | 低 |

进入真实 DRP 实现前，必须补齐：

- 当前 GTXE2_CHANNEL 下 TXOUT_DIV/RXOUT_DIV 对应 DRP address；
- bitfield 宽度与编码；
- 同寄存器 reserved bits 与其他功能位；
- 是否要求 CPLL reset / TX reset / MMCM reset 顺序；
- DRP 写后是否需要 readback verify；
- 是否需要等待 CPLL lock、MMCM lock、txresetdone。

## 7. TXUSRCLK/TXUSRCLK2 动态方案候选

### 方案 A：MMCM DRP 动态重配置

结构：

```text
GT TXOUTCLK -> 单个 MMCM -> TXUSRCLK/TXUSRCLK2
rate_ctrl 同时控制 GT DRP 与 MMCM DRP
```

优点：

- 时钟路径唯一；
- 不需要在多个 TXUSRCLK/TXUSRCLK2 之间做 glitch-sensitive mux；
- 适合后续扩展更多速率；
- 最符合“速率切换是一个状态机”的工程结构。

缺点：

- 需要实现 MMCM DRP；
- 需要处理 MMCM reset/lock；
- XDC 需要多模式或保守约束；
- 切换期间必须停止 `laser_tx_core` 并复位 TX 相关逻辑。

### 方案 B：500M/1000M 两套 MMCM 输出 + BUFGCTRL/BUFGMUX 切换

结构：

```text
GT TXOUTCLK -> MMCM_500 -> txusrclk_500 / txusrclk2_500
GT TXOUTCLK -> MMCM_1000 -> txusrclk_1000 / txusrclk2_1000
BUFGCTRL/BUFGMUX 选择输出到 GT 和 laser_tx_core
```

优点：

- 每套 MMCM 参数固定；
- 调试时容易观察两套 clock lock；
- 可避免 MMCM DRP 表错误。

缺点：

- 切换全局时钟 mux 风险高；
- BUFG/clocking 资源更多；
- 需要确保两个被 mux 的时钟同源且切换窗口严格受控；
- XDC 与 CDC 更复杂。

### 方案 C：只写 GTX TXOUT_DIV，复用同一套固定 MMCM

结构：

```text
GT TXOUTCLK 频率变化，固定 MMCM 参数不变
```

结论：不推荐作为当前实现方案。

原因：

- 当前 500M 与 1000M 官方 example design 使用不同 MMCM 参数；
- 当前 `laser_gt_usrclk_profile0.v` 是 500M 专用参数；
- 直接让 500M 专用 MMCM 接收 31.25 MHz 输入并输出目标 31.25/15.625 MHz 时钟，不符合已提取的官方 1000M example 结构；
- 即便某些频率数学上可工作，也必须重新验证 MMCM VCO、输出 jitter、XDC 与实现时序，不能当作安全动态切换方案。

## 8. 推荐方案

建议后续真实实现采用“方案 A：MMCM DRP 动态重配置”，但进入实现前必须先补齐 GTX DRP address/bitfield 证据。

推荐切换状态机大致顺序：

```text
IDLE
  -> reject if laser_tx_core busy
  -> DISABLE TX engine / hold laser_tx_core reset
  -> assert GT TX reset / hold tx datapath reset
  -> write GTX DRP candidate set
  -> reconfigure TX user clock MMCM
  -> wait MMCM lock
  -> release GT TX reset
  -> wait CPLL lock / txresetdone / gt_ready
  -> update active_rate status
  -> release laser_tx_core reset
  -> DONE or ERROR
```

切换期间必须保证：

- `laser_tx_core` 不在 busy；
- `txdata` / `valid_mask` 不被当作有效输出；
- ILA trigger 与 TXUSRCLK2 时钟变化关系被重新说明；
- 软件 status 能区分 `rate_busy`、`rate_error`、`active_rate`、`requested_rate`。

## 9. `laser_gt_rate_ctrl` 接口草案

以下只是接口设计草案，不代表已实现。

```verilog
module laser_gt_rate_ctrl (
    input  wire        axi_clk,
    input  wire        axi_rstn,

    input  wire        txusrclk2,
    input  wire        tx_reset_done,
    input  wire        cpll_lock,
    input  wire        tx_mmcm_lock,
    input  wire        laser_busy_tx,

    input  wire        rate_req_valid,
    input  wire [15:0] rate_req_mbps,
    output wire        rate_req_ready,

    output wire        rate_busy,
    output wire        rate_done,
    output wire        rate_error,
    output wire [15:0] active_rate_mbps,
    output wire [15:0] requested_rate_mbps,
    output wire [7:0]  rate_state,

    output wire        gt_drp_en,
    output wire        gt_drp_we,
    output wire [8:0]  gt_drp_addr,
    output wire [15:0] gt_drp_di,
    input  wire [15:0] gt_drp_do,
    input  wire        gt_drp_rdy,

    output wire        mmcm_drp_en,
    output wire        mmcm_drp_we,
    output wire [6:0]  mmcm_drp_addr,
    output wire [15:0] mmcm_drp_di,
    input  wire [15:0] mmcm_drp_do,
    input  wire        mmcm_drp_rdy,

    output wire        gt_tx_reset_req,
    output wire        tx_mmcm_reset_req,
    output wire        laser_tx_hold_reset
);
```

建议软件可见寄存器：

| Offset | 名称 | 方向 | 说明 |
| --- | --- | --- | --- |
| 0x00 | RATE_CTRL | W/R | bit0 request, bit1 abort/reserved, bit31 soft clear error |
| 0x04 | RATE_REQ_MBPS | W/R | 请求速率，第一阶段只允许 500/1000 |
| 0x08 | RATE_STATUS | R | busy/done/error/unsupported/active_profile |
| 0x0C | RATE_ACTIVE_MBPS | R | 当前生效速率 |
| 0x10 | RATE_ERROR_CODE | R | 参数非法、busy 拒绝、DRP timeout、MMCM unlock、GT reset timeout 等 |
| 0x14 | RATE_STATE | R | rate_ctrl FSM 当前状态 |

第一版应保持：

- `rate plan <Mbps>` 仍可 dry-run；
- `rate set <Mbps>` 在未实现硬件前仍返回 unsupported；
- 不允许软件绕过 `rate_ctrl` 直接写 GT DRP。

## 10. Wrapper / BD / XDC / XSA / Vitis 更新计划

真正实现动态速率时预计需要以下更新；本阶段没有执行这些修改。

| 模块 | 后续需要做什么 | 本阶段状态 |
| --- | --- | --- |
| GT wrapper | 暴露 GT DRP 端口、TX reset 控制、CPLL lock、txresetdone、TXOUTCLK、TXUSRCLK/TXUSRCLK2 clocking 状态 | 未修改 |
| user clocking | 将 `laser_gt_usrclk_profile0` 扩展为可重配置或替换为动态 clocking wrapper | 未修改 |
| BD | 接入 `laser_gt_rate_ctrl` 或等价控制模块，连接 AXI/status | 未修改 |
| XDC | 增加 500M/1000M 多模式或保守 clock constraints，更新 TXUSRCLK2 约束 | 未修改 |
| XSA | 任何 BD/地址图变化后必须重新导出 | 未修改 |
| Vitis | 新增 `rate set` 硬件分支、status readback、timeout/error handling | 未实现 |
| 测试 | 分别验证 500M、1000M 单速率，再验证切换 500->1000->500 | 未执行 |

## 11. 进入真实 RTL 实现前必须满足的条件

1. 从 UG476、GT Wizard 生成资料或 Xilinx 推荐脚本中确认当前 GTXE2_CHANNEL 的 TXOUT_DIV/RXOUT_DIV DRP address 与 bitfield；
2. 确认是否需要修改 TX_CLK25_DIV、CPLL 配置或其他辅助 divider；
3. 生成并保存 1000M TX-only 或 TX/RX 一致的最终目标 XCI；
4. 确认 1000M 单 profile 在独立 bitstream 中可综合、实现、timing 通过；
5. 确认 1000M 下 `laser_tx_core` 运行在 15.625 MHz TXUSRCLK2 域时业务节拍含义；
6. 确认 ILA 采样深度、trigger 与波形解释按新 TXUSRCLK2 周期更新；
7. 确认动态切换期间软件禁止 APPLY/ENABLE；
8. 确认失败回退策略：停在 error、回退 500M、还是要求重新下载 bitstream。

## 12. Profile 0 回滚保护

本轮对比过程中已确认当前工程生成文件仍为 500M Profile 0：

```text
laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0_gt.v:
  CPLL_FBDIV      = 4
  CPLL_FBDIV_45   = 4
  CPLL_REFCLK_DIV = 1
  RXOUT_DIV       = 8
  TXOUT_DIV       = 8

laser_tx.gen/sources_1/ip/gtwizard_0/gtwizard_0.xml:
  gt0_val_tx_line_rate     = 0.5
  gt0_val_cpll_txout_div   = 8
  gt0_val_rx_line_rate     = 0.5
  gt0_val_cpll_rxout_div   = 8
```

当前已上板验证的 Profile 0 链路不应被动态速率实验破坏。后续所有 1000M 和动态切换工作必须保持以下原则：

- 1000M 对比工程放在 `reports/` 或独立工程；
- 不直接修改当前 `laser_tx.srcs/sources_1/ip/gtwizard_0/gtwizard_0.xci`；
- 未完成单速率 1000M bitstream 验证前，不把 1000M 接入主工程；
- 未完成 GTX DRP + MMCM DRP 证据前，不实现真实 `rate set`；
- 如果任何实验污染 `laser_tx.gen`，必须先恢复 Profile 0 并重新确认 `TXOUT_DIV=8`。

## 13. 阶段性结论

本阶段已生成隔离的 1000M TX 对比资料，并提取官方 example design 的 TX user clocking 参数。对比结果说明：500M -> 1000M 不只是 `TXOUT_DIV=8 -> 4`，还必须同步处理 TX user clock MMCM，使 TXUSRCLK/TXUSRCLK2 从 15.625/7.8125 MHz 切到 31.25/15.625 MHz。

当前可推进到“动态速率 RTL 方案详细设计”，但还不应进入真实 DRP 写入实现。下一步应优先确认 GTXE2 DRP address/bitfield 与 1000M 独立 profile 的完整可实现性。


# Laser TX ILA signal map

两个 ILA 使用不同采样时钟，禁止把 AXI 域与 TX 域信号混入同一个 ILA。

## `ila_laser_axi_cfg`

采样时钟：`processing_system7_0/FCLK_CLK0`（`axi_clk`）。

| Probe | Width | Signal | Meaning |
|---|---:|---|---|
| 0 | 32 | `gpio_ctrl` | 配置索引、apply toggle、enable、soft reset 和模式选择 |
| 1 | 32 | `gpio_status` | 配置、发送、phase 和错误状态 |
| 2 | 1 | `dbg_bram_en` | PL 配置读取使能 |
| 3 | 32 | `dbg_bram_addr` | Port B 字节地址；一次 apply 应读取 `base+0x00` 到 `base+0x1c` |
| 4 | 32 | `dbg_bram_dout` | 当前 BRAM 读数据 |
| 5 | 1 | `dbg_bram_rst` | Port B 高有效复位，正常运行应为 0 |

`dbg_bram_*` 是原生 BRAM 接口信号的只读镜像，不参与功能逻辑。

### 配置读取波形

翻转 `gpio_ctrl[8]` 后，应看到 `dbg_bram_en` 拉高，地址以 4 字节步长读取 8 个 word。读取完成后：

- 合法配置：`gpio_status[0]=1`、`gpio_status[1]=0`。
- 非法配置：`gpio_status[0]=0`、`gpio_status[1]=1`，错误码位于 `[31:24]`。

首次联调可用 `gpio_ctrl[8]` 的任意边沿作为触发条件。apply 是 toggle，不要求固定上升沿。

## `ila_laser_tx`

采样时钟：`laser_tx_core_0/txusrclk2`。临时 bring-up 时它是 FCLK0；接入 GT 后必须换为 GT TX user clock。

| Probe | Width | Signal | Meaning |
|---|---:|---|---|
| 0 | 64 | `txdata` | 每个 TX user clock 产生的并行发送 word |
| 1 | 64 | `valid_mask` | 每个 lane 是否属于有效 pattern；gap lane 为 0 |
| 2 | 1 | `eom_out` | Word 级 EOM，等于 `|valid_mask` |
| 3 | 1 | `soa_gate_out` | 与 `eom_out` 共用同一个 EOM window net；逻辑周期完全一致 |
| 4 | 1 | `acq_trig_out` | 每个 phase 开始时单拍 |
| 5 | 1 | `acq_gate_out` | 当前 phase 的采集窗口；gap 期间保持高 |
| 6 | 1 | `dbg_busy_tx` | TX engine 当前 word 活跃 |
| 7 | 1 | `dbg_done_tx` | 非循环序列完成状态 |
| 8 | 1 | `dbg_phase_active_tx` | 当前输出 word 属于 phase |
| 9 | 1 | `dbg_phase_start_pulse_tx` | phase 开始的原始 TX 域单拍 |
| 10 | 8 | `dbg_phase_offset_tx` | 原始 TX 域 phase offset |
| 11 | 8 | `dbg_current_state_tx` | 原始 TX engine state |
| 12 | 1 | `dbg_cfg_update_pulse_tx` | 配置 toggle 同步到 TX 域后的单拍 |
| 13 | 1 | `dbg_pattern_valid_tx` | TX 域 pattern 有效状态 |
| 14 | 1 | `dbg_engine_start_tx` | TX engine 启动单拍 |

这些 `dbg_*_tx` 均直接镜像 `txusrclk2` 域内部状态，可用于逐拍对齐分析。`gpio_status` 属于 `axi_clk` 域，只保留在 `ila_laser_axi_cfg`，不再由 TX ILA 采样。

## Trigger suggestions

1. 首次启动：AXI ILA 触发 `gpio_ctrl[8]` 改变；TX ILA 触发 `dbg_cfg_update_pulse_tx`、`dbg_engine_start_tx` 或首个 `acq_trig_out`。
2. Phase 边界：触发 `dbg_phase_start_pulse_tx == 1` 或 `acq_trig_out == 1`。
3. Gap：设置 ILA 比较条件 `valid_mask != 64'hFFFF_FFFF_FFFF_FFFF`。
4. 纯 gap word：配置 `gap_len_bits=128`，触发 `valid_mask == 64'h0`，应同时看到 `txdata=0`、`eom_out=0`，而两个 gate 保持为 1。

AXI ILA 中的 `gpio_status` 仍用于验证 PS 可见状态与错误码，但不用于判断 TX word 级时序。

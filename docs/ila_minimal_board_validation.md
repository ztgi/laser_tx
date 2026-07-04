# laser_tx 最小 ILA 上板验证

本流程只验证一条默认 direct-63 发送链路，不增加 ILA、不修改 RTL：

```text
PS 写 BRAM/GPIO -> PL config_loader -> cfg_update TX CDC
-> engine_start -> txdata/valid_mask -> EOM/SOA/ACQ
```

## 1. 下载与运行顺序

1. 在 Vivado Hardware Manager 对 `xc7z100` 选择 **Program Device**。
2. 选择同一次 implementation 的文件：

   ```text
   laser_tx.runs/impl_1/laser_tx_board_top.bit
   laser_tx.runs/impl_1/laser_tx_board_top.ltx
   ```

3. Program 后确认两颗 ILA 出现。若没有两颗 ILA，不要运行 Vitis；先修复 bit/LTX 配对。
4. 在 Vitis 的 Run/Debug Configuration 中取消 **Program FPGA** / **Download bitstream**，只下载 `bringup.elf`。
5. 串口出现以下文字后不要按键：

   ```text
   PS init done. Set Vivado ILA trigger, then press any key to start laser_tx...
   ```

6. 回到 Vivado Arm ILA，最后再回串口按任意键。

## 2. 第一轮：配置侧 ILA

选择包含 `gpio_ctrl`、`dbg_bram_en`、`dbg_bram_addr`、`dbg_bram_dout` 的 ILA（通常为 `hw_ila_1` / `ila_laser_axi_cfg`）。

1. 打开 **Trigger Setup**，点击 **+**。
2. 选择 `axi_gpio_0_gpio_io_o[31:0]`（LTX 中也可能显示为 `gpio_ctrl` 或 `probe0`）。
3. Operator 选 `!=`，Radix 选 Hex，Value 填 `00000000`。
4. 点击 **Run Trigger**，确认显示 **Waiting For Trigger**。
5. 回串口按键。

应观察：

- `gpio_ctrl` 先出现 direct source/config index，再翻转 bit8 apply，最后 bit9 enable 为 1；
- `dbg_bram_en` 在 apply 后拉高；
- `dbg_bram_addr` 以 4 byte 步进读取一个配置记录；
- `dbg_bram_dout` 与 PS 写入的配置 word 对应；
- `gpio_status` 最终应报告 `cfg_valid`。

## 3. 第二轮：TX 启动 ILA

选择包含 `dbg_cfg_update_pulse_tx` 的 ILA（通常为 `hw_ila_2` / `ila_laser_tx`）。

1. Trigger 优先设置 `dbg_cfg_update_pulse_tx == 1`。
2. 若该单拍未抓到，改用 `dbg_engine_start_tx == 1`。
3. 保留以下观测项：
   `dbg_cfg_update_pulse_tx`、`dbg_engine_start_tx`、`dbg_current_state_tx`、
   `dbg_busy_tx`、`dbg_done_tx`、`dbg_phase_start_pulse_tx`、
   `dbg_pattern_valid_tx`、`txdata`、`valid_mask`。
4. Arm 后复位处理器/重新运行 ELF，使串口再次停在等待提示；然后按键。

通过时应依次看到：cfg-update 单拍、engine-start 单拍、状态离开 IDLE、`pattern_valid`/`busy` 变高、`txdata` 与 `valid_mask` 非零，非 loop 发送完成后 `done` 置位。

## 4. 第三轮：同步输出 ILA

继续使用 TX ILA。触发条件任选其一：

```text
eom_out == 1
soa_gate_out == 1
acq_trig_out == 1
acq_gate_out == 1
```

观察 `txdata`、`valid_mask` 与四个同步输出。

| 信号 | 正常关系 |
|---|---|
| `eom_out` | 等于 `|valid_mask` |
| `soa_gate_out` | phase 内为高 |
| `acq_gate_out` | phase 内为高 |
| `acq_trig_out` | 每个 phase 开始单拍 |

## 5. 信号含义

| 信号 | 含义 |
|---|---|
| `gpio_ctrl` | PS 写入的 index/apply/enable/reset/direct 选择控制字 |
| `gpio_status` | AXI 域 cfg/status 镜像，不用于 TX 单拍时序判断 |
| `dbg_bram_en/addr/dout` | config_loader 对 BRAM Port B 的读事务 |
| `dbg_cfg_update_pulse_tx` | apply 成功后跨至 `txusrclk2` 的单拍 |
| `dbg_engine_start_tx` | TX engine 的内部启动单拍 |
| `dbg_current_state_tx` | TX engine 状态，IDLE=0、RUN=1、DONE=2 |
| `dbg_busy_tx` / `dbg_done_tx` | 发送活动 / 非 loop 完成状态 |
| `dbg_phase_start_pulse_tx` | 每个 phase 的开始单拍 |
| `dbg_pattern_valid_tx` | pattern source 有效 |
| `txdata` / `valid_mask` | 64-bit TX word 与有效 lane 掩码 |
| `eom_out` / `soa_gate_out` / `acq_trig_out` / `acq_gate_out` | 与当前 TX word 对齐的同步输出 |

## 6. 快速判定表

| 现象 | 说明 | 下一步 |
|---|---|---|
| `gpio_ctrl` 不变 | PS 未写到 AXI GPIO | 查 ELF、GPIO device ID/base、Channel 1 direction、bit/LTX 配对 |
| `gpio_ctrl` 变，但 `cfg_update_pulse_tx` 无 | apply 未被识别，或 CDC/TX clock 有问题 | 先看 `dbg_bram_en`；再查 bit8、`txusrclk2`、TX reset |
| `cfg_update_pulse_tx` 有，`engine_start_tx` 无 | 配置未有效、enable 未到 TX 域或复位仍有效 | 查 `gpio_status.cfg_valid`、repeat_cycles、bit9、soft reset |
| `engine_start_tx` 有，状态机不动 | engine 时钟/复位或启动条件异常 | 查 `txusrclk2` 是否 free-running、`tx_rst`、`pattern_valid` |
| 状态机动，但 `txdata/valid_mask` 全 0 | pattern/BRAM/gap 配置异常 | 查 `pattern_valid`、BRAM word、direct source/length、gap |
| `txdata/valid_mask` 正常，但 EOM/SOA/ACQ 无变化 | 同步输出或 phase 配置异常 | 查 `phase_active`、phase-start 与 `sync_signal_gen` 关系 |


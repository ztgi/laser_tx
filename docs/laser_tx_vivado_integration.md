# laser_tx_core Vivado 集成与第一阶段上板验证

## 1. 顶层接口结论

`laser_tx_core` 的 BRAM 端口已补全并标注为 Vivado 原生 `BRAM_PORTB` master 接口：

| 信号 | 方向 | 固定关系/用途 |
|---|---:|---|
| `bram_clk` | 输出 | `axi_clk` |
| `bram_rst` | 输出 | `~axi_rstn`，高有效 |
| `bram_en` | 输出 | 配置读取使能 |
| `bram_we[3:0]` | 输出 | 固定 `4'b0000` |
| `bram_addr[31:0]` | 输出 | 字节地址，配置项间隔 4 字节 |
| `bram_din[31:0]` | 输出 | 固定 `32'd0` |
| `bram_dout[31:0]` | 输入 | BRAM Port B 读数据 |

PL 仅通过 Port B 读取。PS 经 AXI BRAM Controller/Port A 写入，写完完整的 8 个 word 后再翻转 `apply_toggle`，避免读写同一配置记录时发生碰撞。

## 2. 添加 Module Reference

1. 打开 `laser_tx.xpr` 和 `system.bd`。
2. 确认 `laser_tx_core.v` 及六个子模块都在 **Design Sources** 中；工程已经登记这些文件。
3. 在 BD 空白处右键选择 **Add Module**，或点击工具栏的 **Add Module**。
4. 选择 `laser_tx_core`。不要把其子模块分别加入 BD。
5. 如果修改 RTL 后端口没有刷新，右键 Module Reference，选择 **Refresh Module**。
6. 执行 **Validate Design**，再重新生成 BD Output Products。

## 3. BRAM Port B

当前 BD 已把 Block Memory Generator 的 Port B 导出为 `BRAM_PORTB_0`。集成时：

1. 删除外部接口端口 `BRAM_PORTB_0`，保留 `blk_mem_gen_0/BRAM_PORTB`。
2. 将 `laser_tx_core/BRAM_PORTB` 直接连接到 `blk_mem_gen_0/BRAM_PORTB`。
3. 保持 Block Memory Generator 为 **True Dual Port RAM**、Port B 数据宽度 32 bit、读延迟 1。
4. Port A 继续连接 `axi_bram_ctrl_0/BRAM_PORTA`，供 PS 读写。

若 Vivado 没有自动把端口显示为一束 `BRAM_PORTB`，先 Refresh Module；仍未分组时可展开 BMG 的接口，按第 1 节表格逐根连接。不要额外接常量到 `WE/DIN`，顶层内部已经固定为只读。

## 4. AXI GPIO

现有 `axi_gpio_0` 是单通道全输出配置，必须调整：

1. 双击 `axi_gpio_0`，启用 **Dual Channel**。
2. Channel 1：GPIO Width = 32，配置为 **All Outputs**。
3. Channel 2：GPIO2 Width = 32，配置为 **All Inputs**。
4. 删除当前导出的 `gpio_rtl_0` 外部端口。
5. 展开 GPIO 接口后连接：
   - `axi_gpio_0/gpio_io_o[31:0]` → `laser_tx_core/gpio_ctrl[31:0]`
   - `laser_tx_core/gpio_status[31:0]` → `axi_gpio_0/gpio2_io_i[31:0]`

GPIO bit 定义保持现有 RTL 约定。软件每次应用新配置时应翻转 bit 8，而不是输出一个可能被漏采的窄脉冲。

## 5. GT Wizard 与发送时钟

1. `txusrclk2` 必须来自 GT TX user-clock 网络，不得使用 PS FCLK 或原始参考时钟代替。
2. 对 7-series GT Wizard，使用 `TXOUTCLK` 经向导 example design 的 TX user-clock helper 生成同源 `TXUSRCLK`/`TXUSRCLK2`；Profile 0 中 `TXUSRCLK=15.625 MHz` 接 GT `txusrclk`，`TXUSRCLK2=7.8125 MHz` 同时接 GT `txusrclk2` 和 `laser_tx_core/txusrclk2`。
3. GT Wizard 的 TX 用户接口宽度配置为 64 bit，然后连接：
   - `laser_tx_core/txdata[63:0]` → 对应通道的 `txdata_in[63:0]`
4. `tx_rst` 使用 `txusrclk2` 域的复位。推荐在 GT TX reset 完成前保持复位，并保证复位同步释放。
5. `valid_mask` 不送入 GTX；第一阶段接发送侧 ILA。`EOM/SOA/ACQ` 全部由同一发送状态机派生。

GT Wizard 不同版本的端口前缀可能是 `gt0_`、`ch0_` 或无通道前缀，以生成实例的实际端口名为准。如果生成的 TXDATA 宽度不是 64 bit，应先修改 Wizard 用户数据宽度，不能截断 `txdata`。

## 6. 外部同步端口与 XDC

在 BD 中分别右键以下端口并选择 **Make External**：

- `eom_out`
- `soa_gate_out`
- `acq_trig_out`
- `acq_gate_out`

建议外部端口沿用上述名称。XDC 至少添加对应的 `PACKAGE_PIN` 和 `IOSTANDARD`，具体值必须按板卡原理图填写。若外部器件要求相对时序，还应基于实际采样时钟添加 `set_output_delay`，不能用猜测值代替板级时序参数。

## 7. 推荐 ILA

不要用一个 ILA 跨两个时钟域；使用两个 ILA。

### AXI/配置侧 ILA（时钟 `axi_clk`）

- `gpio_ctrl[31:0]`
- `gpio_status[31:0]`
- `bram_en`
- `bram_addr[31:0]`
- `bram_dout[31:0]`
- `bram_rst`
- `cfg_update_toggle_axi`
- `cfg_valid_axi`
- `cfg_error_axi`
- `error_code_axi[7:0]`

后三项是 `laser_tx_core` 内部网，可在 RTL 中 `MARK_DEBUG`，或在综合后的网表中 Mark Debug。基础 BD 联调只观察前六项也足够确认 8-word 读取过程。

### 发送侧 ILA（时钟 `txusrclk2`）

- `txdata[63:0]`
- `valid_mask[63:0]`
- `eom_out`
- `soa_gate_out`
- `acq_trig_out`
- `acq_gate_out`
- `busy_tx`
- `done_tx`
- `phase_active_tx`
- `phase_start_pulse_tx`
- `phase_offset_tx[7:0]`
- `current_state_tx[7:0]`
- `pattern_len_tx[7:0]`
- `cfg_update_pulse_tx`

触发建议：先用 `cfg_update_pulse_tx` 捕获启动过程，再用 `phase_start_pulse_tx` 捕获 phase 边界，最后用 `valid_mask != 64'hffff_ffff_ffff_ffff` 捕获 gap。

## 8. 第一阶段上板验证顺序

每项测试均按以下顺序操作：停止/复位发送；写完 BRAM 的 8 个 word；设置 GPIO 模式位；翻转 `apply_toggle`；确认 `cfg_valid=1` 且 `cfg_error=0`；使能发送；用发送侧 ILA 比较数据、mask 和同步信号。

### A. Direct 63 bit

- `pattern_source_sel=1`，`direct_pattern_len_sel=0`
- `prbs_order=6`（配置合法性检查仍要求为 6 或 7）
- 使用容易识别的 63-bit walking-one 或交替 pattern
- 先设 `phase_shift_en=0`、`repeat_cycles=2`、`gap_len_bits=0`
- 确认仅使用 `pattern_in[62:0]`，上部 64 bit 不进入 TX 流
- 再加入 gap，检查 gap 位 `txdata=0`、`valid_mask=0`，而 SOA/ACQ gate 保持高

### B. PRBS6

- `pattern_source_sel=0`，`prbs_order=6`，seed 建议 `6'h3f`
- `phase_shift_en=1`，检查 `phase_offset` 从 0 到 62
- 检查每个 phase 的 `acq_trig_out` 单拍及移位关系
- seed 写 0 再测试一次，确认自动替换为默认非零 seed

### C. Direct 127 bit

- `pattern_source_sel=1`，`direct_pattern_len_sel=1`，`prbs_order=7`
- 四个 pattern word 使用互不相同的测试值
- 确认拼接为 `{pattern_top[30:0], pattern_high, pattern_mid, pattern_low}`
- 检查 phase 范围为 0 到 126，绝不出现 phase 127/128-bit 数据

### D. PRBS7

- `pattern_source_sel=0`，`prbs_order=7`，seed 建议 `7'h7f`
- 检查完整 127-bit 周期和 phase 0 到 126
- 用 gap 验证 `valid_mask` 与 `eom_out=|valid_mask`。若希望 ILA 明确捕获纯 gap word，可把 gap 设为 128 bit，以保证无论起始 lane 如何至少出现一个全零 mask word

### E. 非法配置

依次测试：

- `repeat_cycles=0` → `error_code=8'h01`
- `prbs_order=5` → `error_code=8'h02`
- `insert_after > repeat_cycles` → `error_code=8'h03`

每次应观察到 `cfg_error=1`、`cfg_valid=0`、`busy=0`，GT TX 用户数据保持空闲，不应出现新的 phase trigger。

## 9. 集成完成检查

- BD Validate Design 无接口宽度或方向错误
- BRAM Port A/Port B 时钟均为 `axi_clk`，Port B 读延迟为 1
- AXI GPIO Channel 2 可由 PS 读回 `gpio_status`
- `txusrclk2` 与 GT TX 用户接口同源
- 两个 ILA 分别使用各自时钟域
- 外部同步输出已约束管脚和 I/O 标准
- 完成 implementation 后检查 `txusrclk2` 域 timing summary，再开始上板发送

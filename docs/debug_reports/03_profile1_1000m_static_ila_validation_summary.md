# Profile1 1000M static ILA 上板验证摘要

本文是当前 1000M Profile1 static 上板 ILA 验证的正式摘要入口，重点整理真实 Vivado GUI 截图证据。

本报告仅整理既有文档和证据，不修改 RTL、BD、XDC、Vitis、build 脚本、bitstream 或 LTX。

## 1. 来源

主要来源：

```text
docs/debug_reports/archive/profile1_1000m_intermediate_reports/20260629_gt_profile1_1000m_axi_bringup_ila_fix.md
docs/gt_dynamic_rate_phase2_1000m_static_validation.md
docs/images/
```

## 2. 本次 UDP 配置

本次 AXI/FCLK ILA 波形对应的配置命令为：

```text
SOFT_RESET
WRITE_CONFIG 0 0x5A 4 8 2 7 0 0 0x89ABCDEF 0x01234567 0x76543210 0x52A55AA5
SELECT_CONFIG 0 1 1
APPLY
ENABLE
```

配置含义：

```text
index = 0
seed = 0x5A
repeat_cycles = 4
gap_len_bits = 8
insert_after = 2
prbs_order = 7
phase_shift_en = 0
loop_en = 0
direct_source = 1
direct_len_127 = 1
```

即：

```text
127bit direct pattern；
重复 4 次；
第 2 次 pattern 后插入 8bit gap；
不循环。
```

Pattern 字段：

```text
pattern_low  = 0x89ABCDEF
pattern_mid  = 0x01234567
pattern_high = 0x76543210
pattern_top  = 0x52A55AA5
```

配置截图：

```text
docs/images/phase1_static_ila/1000m_static/udp_1000m_direct127_gap8_repeat4_config.png
```

## 3. AXI/FCLK ILA 截图证据

### 3.1 APPLY 前：GT ready 与 txusrclk2 alive

截图：

```text
docs/images/phase1_static_ila/1000m_static/ila_1000m_axi_00_before_apply_gt_ready_idle.png
```

该图对应 `SOFT_RESET + WRITE_CONFIG + SELECT_CONFIG` 后、`APPLY` 前。可保留解释：

```text
GT/MMCM/txusrclk2 已经处于可工作状态；
cplllock_sync = 1；
txresetdone_sync = 1；
tx_mmcm_locked_sync = 1；
gt_ready_ctrl = 1；
txusrclk2_alive_axi = 1；
txusrclk2_freq_counter_axi 持续递增；
此时 BRAM 配置已写入并已选择 index=0/direct127，但尚未 APPLY。
```

### 3.2 APPLY 后：cfg_update_seen

截图：

```text
docs/images/phase1_static_ila/1000m_static/ila_1000m_axi_01_after_apply_cfg_update_seen.png
```

可保留解释：

```text
APPLY toggle 已进入 PL；
dbg_axi_cfg_update_seen = 1；
dbg_axi_cfg_valid = 1；
dbg_axi_cfg_error = 0；
dbg_axi_pattern_valid = 1；
dbg_axi_engine_start_seen = 0。
```

结论：

```text
WRITE_CONFIG / SELECT_CONFIG / APPLY 控制链路有效；
配置已经被 PL 接收并校验通过；
因为尚未 ENABLE，所以 engine_start_seen = 0 是正常现象。
```

### 3.3 ENABLE 后：engine_start_seen

截图：

```text
docs/images/phase1_static_ila/1000m_static/ila_1000m_axi_02_after_enable_engine_start_seen.png
```

可保留解释：

```text
GPIO enable bit 已置 1；
dbg_axi_engine_start_seen = 1；
dbg_axi_cfg_valid = 1；
dbg_axi_cfg_error = 0；
dbg_axi_pattern_valid = 1；
GT/MMCM/txusrclk2 状态仍保持正常。
```

结论：

```text
ENABLE 控制已经进入 PL；
laser_tx_core 的发送启动事件已经发生；
PS/UDP -> AXI GPIO -> PL -> txusrclk2 域发送启动链路有效。
```

如果截图中 `busy_tx` 当前值为 0，不应判定失败。本次配置 `loop_en=0`，且 direct127 repeat4 gap8 是有限短序列，发送窗口很短，ILA cursor 位置可能已经落在发送结束后。

## 4. txusrclk2 域既有截图

以下真实 GUI 截图当前存在并保留：

```text
docs/images/phase1_static_ila/500m_profile0/ila_apply_config_update.png
docs/images/phase1_static_ila/500m_profile0/ila_apply_with_txdata_validmask.png
docs/images/phase1_static_ila/500m_profile0/ila_enable_engine_start.png
docs/images/phase1_static_ila/500m_profile0/ila_enable_txdata_validmask.png
```

以下文件名曾作为建议命名出现，但当前未检测到实际文件，不能作为已有截图证据：

```text
docs/images/phase1_static_ila/500m_profile0/ila_enable_txdata_validmask2.png
```

txusrclk2 域截图用于说明：

```text
APPLY / ENABLE 在发送时钟域中的进一步观察；
txdata[63:0]；
valid_mask[63:0]；
engine_start；
pattern_valid。
```

AXI/FCLK ILA 与 txusrclk2 ILA 的关系：

```text
AXI/FCLK ILA：证明系统状态和控制链路；
txusrclk2 ILA：证明发送数据路径和 valid_mask 输出。
```

## 5. 当前可以保留的 1000M static ILA 结论

可以写：

```text
1000M Profile1 static 在 AXI/FCLK bring-up ILA 下已验证：
GT/MMCM ready；
txusrclk2 alive；
APPLY 进入 PL；
配置校验通过；
ENABLE 进入 PL；
发送启动事件发生。
```

更完整的阶段性结论：

```text
1000M Profile1 static 的 GT/MMCM/txusrclk2 alive、配置加载和发送启动链路已经通过 AXI/FCLK ILA 阶段性验证。
```

## 6. 当前不能扩大为的结论

不能写成：

```text
1000M 动态调速已经完成；
GTX DRP/MMCM DRP 已完成；
外部光口链路闭环已经通过；
1000M static build 通过等于上板闭环通过；
AXI/FCLK ILA 的状态验证等于外部 TX 光口实际输出验证。
```

## 7. 后续建议

后续如果继续 1000M static 验证，建议优先补强：

```text
txusrclk2 域 txdata[63:0] / valid_mask[63:0] 的长窗口真实 GUI 截图；
eom_out / soa_gate_out / acq_trig_out / acq_gate_out 的真实 GUI 截图；
必要时用示波器或外部接收链路验证外部同步和光口实际输出。
```


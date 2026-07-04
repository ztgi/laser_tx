# Testbench 启动时序修复报告：engine_start_tx=1 但 busy_tx=0

## 1. 问题背景

本轮仿真中曾观察到一个容易误判的现象：

```text
engine_start_tx = 1
busy_tx         = 0
valid_mask      = 0
txdata          = 0
```

乍看起来，这像是 `pattern_tx_engine` 收到了 `start`，但没有真正进入 active / busy 状态；也像是发送状态机没有接收启动事件。

但这个现象不能直接判定为 RTL bug。原因是 `laser_tx_core` 的发送启动不是只看一个 `engine_start_tx` 波形，而是依赖一整条启动链路：配置有效、GT ready、TX reset 释放、ENABLE 生效、pattern 有效，然后 `pattern_tx_engine` 才能离开 IDLE 并输出 `busy_tx / valid_mask / txdata`。

因此，本轮没有直接修改 `laser_tx_core` 或 `pattern_tx_engine`，而是先检查 testbench 是否完整模拟了真实硬件启动前提。

## 2. 发送启动链路

当前设计的发送启动链路可以按下面顺序理解：

```text
BRAM 配置写入/读取
-> APPLY toggle
-> config_loader 解析
-> cfg_valid_tx=1 且 cfg_error=0
-> ENABLE=1
-> gt_ready=1
-> enable_tx 有效
-> engine_start_tx
-> pattern_tx_engine 离开 IDLE
-> busy_tx / pattern_valid_tx
-> valid_mask / txdata
-> SOA / ACQ / EOM 输出
```

这条链路里，`txdata / valid_mask / SOA / ACQ / EOM` 是较靠后的结果信号。如果它们不动，不应直接从输出端判断 `pattern_tx_engine` 错误，而应沿着下面的顺序逐级定位：

```text
cfg_valid / cfg_error
-> gt_ready / tx_rst / ENABLE
-> engine_start_tx
-> busy_tx
-> pattern_valid_tx
-> valid_mask
-> txdata
-> SOA / ACQ / EOM
```

本轮排查后确认，原始异常更符合 testbench 启动条件不完整造成的观察失真，而不是 `pattern_tx_engine` RTL start 接收错误。

## 3. 修复前现象与原因

![修复前：gt_ready 未建模，engine_start 与 busy/valid_mask 不匹配]()

图 1 修复前：`gt_ready` 未建模，ENABLE 启动边界不清，`engine_start_tx` 与 `busy_tx / valid_mask` 不匹配。

修复前 testbench 的关键问题是：它相当于“没有告诉 DUT GT 已经准备好，就直接按了启动键”。

在 `laser_tx_core` 中，ENABLE 并不是单独生效，而是受 `gt_ready` 门控：

```verilog
enable_meta <= gpio_ctrl[9] & gt_ready;
enable_tx   <= enable_meta;
```

所以 testbench 如果不显式驱动 `gt_ready=1`，启动条件就是不完整的。此时即使局部波形中能看到 `engine_start_tx` 的迹象，也不能稳定证明 `pattern_tx_engine` 已经按真实硬件流程进入 active。

另一个问题是，原 testbench 中 `gpio_ctrl[9]` 即 ENABLE 在复位前就已经固定为 1。这样 APPLY 配置完成和 ENABLE 启动发送之间没有清晰边界，仿真波形中很难判断当前是在“加载配置”阶段，还是已经进入“正式启动发送”阶段。

因此，修复前的 `engine_start_tx=1` 但 `busy_tx=0` 现象，不能直接作为 `pattern_tx_engine` RTL bug 的证据。

## 4. 修改内容

本轮只修改 testbench：

```text
D:/FPGA_Learn/laser_tx/laser_tx.srcs/sim_1/new/tb_laser_tx_core.sv
```

未修改：

```text
laser_tx_core
pattern_tx_engine
BD
XDC
GT Wizard
Vitis
UDP 协议
GTX/MMCM DRP 逻辑
AD9528
```

具体修改如下。

### 4.1 新增 `gt_ready`

testbench 中新增并驱动 `gt_ready`，用于模拟真实 GT ready 状态。

目的：让 `gpio_ctrl[9]` 的 ENABLE 能通过 `laser_tx_core` 内部的 `gt_ready` 门控，形成真实有效的 `enable_tx`。

### 4.2 连接 `dbg_gt_ready_tx`

testbench 接出 `dbg_gt_ready_tx`。

目的：确认 TX 域实际看到的 ready 状态，而不只是 testbench 侧变量为 1。

### 4.3 复位前保持 ENABLE=0

修复后 testbench 不再在复位前把 `gpio_ctrl[9]` 固定为 1。

目的：避免复位释放、配置加载和发送启动混在一起，使 APPLY 与 ENABLE 两个事件边界清晰。

### 4.4 先 `gt_ready=1`，再释放 `tx_rst`

修复后启动顺序调整为：

```text
axi_rstn 释放
-> gt_ready 拉高并稳定
-> tx_rst 释放
-> APPLY 配置
-> cfg_valid 确认
-> ENABLE 拉高
```

目的：让发送侧在启动前已经具备真实硬件中的 GT ready / reset released 前提。

### 4.5 APPLY 完成后再 ENABLE

每个有效 scenario 中，先执行 APPLY 并等待 `cfg_valid`，再拉高 ENABLE。

目的：模拟真实控制流程，明确区分：

```text
APPLY = 配置加载/校验事件
ENABLE = 启动发送事件
```

### 4.6 增加 `monitor_start_window()`

新增启动窗口诊断，在 `engine_start_tx` 后 1~10 个 `txusrclk2` 周期内检查：

```text
gt_ready
dbg_gt_ready_tx
tx_rst
cfg_valid_tx
cfg_error
current_state_tx 是否离开 IDLE
busy_tx 是否至少出现过一拍
done_tx 是否快速出现
pattern_valid_tx
valid_mask 是否非 0
repeat_cycles / insert_after / gap_len_bits / loop_en / direct_len_sel 是否合法
```

目的：如果后续再次出现 `engine_start_tx=1` 但 `busy_tx=0`，可以判断是 testbench 条件缺失、配置非法、reset/ready 问题，还是确实需要进一步检查 `pattern_tx_engine`。

## 5. 修复后仿真结果

![修复后：gt_ready 建模且 APPLY/ENABLE 分离，busy/valid_mask/txdata 正常输出]()

图 2 修复后：`gt_ready` 建模，APPLY 与 ENABLE 分离，发送链路正常进入 active。

修复后仿真显示：

```text
gt_ready=1
dbg_gt_ready_tx=1
tx_rst=0
cfg_valid_tx=1
cfg_error=0
current_state_tx 离开 IDLE
busy_tx 至少出现过一拍
pattern_valid_tx=1
valid_mask 非 0
txdata 非 0
SOA/ACQ/EOM 随发送状态变化
```

结合截图和仿真日志可以看到：

1. `gpio_ctrl` 先进入 APPLY 阶段，随后进入 ENABLE 阶段；
2. `bram_dout` 读出有效配置内容；
3. `dbg_cfg_update_pulse_tx` 出现，说明 APPLY toggle 已进入 TX 域；
4. `dbg_engine_start_tx` 出现，说明配置有效后发送启动事件已经产生；
5. `dbg_busy_tx` 拉高，说明 `pattern_tx_engine` 已离开 IDLE；
6. `dbg_pattern_valid_tx=1`，说明 pattern 配置有效；
7. `valid_mask` 出现非零，说明发送窗口中存在有效 bit；
8. `txdata` 出现非零，说明数据路径已输出有效数据；
9. `soa_gate_out / acq_trig_out / acq_gate_out / eom_out` 开始随发送状态变化。

这说明修复后 testbench 的启动流程已经与真实硬件控制链路一致。

## 6. GPIO 为什么会变化

本轮波形中 `gpio_ctrl` 的变化是预期行为。它不是单一控制位，而是多个控制字段组合。

当前相关字段为：

| 字段 | 含义 |
| --- | --- |
| `gpio_ctrl[7:0]` | 配置 index |
| `gpio_ctrl[8]` | APPLY toggle |
| `gpio_ctrl[9]` | ENABLE |
| `gpio_ctrl[11]` | `source_sel`，0=PRBS，1=Direct |
| `gpio_ctrl[12]` | `direct_len_sel`，0=63bit，1=127bit |

典型值解释如下。

### `0x00000300`

```text
gpio_ctrl[8] = 1
gpio_ctrl[9] = 1
index        = 0
source_sel   = 0
direct_len   = 0
```

含义：

```text
APPLY toggle 当前为 1；
ENABLE=1；
index=0；
PRBS/63bit 场景。
```

### `0x00001801`

```text
index        = 1
source_sel   = 1
direct_len   = 1
ENABLE       = 0
APPLY toggle 已相对上一轮翻转
```

含义：

```text
Direct127 场景的配置应用阶段；
此时尚未正式 ENABLE 发送。
```

### `0x00001a01`

这是在 `0x00001801` 基础上拉高 ENABLE：

```text
gpio_ctrl[9] = 1
```

含义：

```text
Direct127 场景正式启动发送。
```

需要特别注意：APPLY 是 toggle，不是固定电平。因此：

```text
APPLY 从 0 变 1 表示一次新 APPLY；
APPLY 从 1 变 0 也表示一次新 APPLY。
```

不能把 APPLY 简单理解成“1 才有效、0 无效”的电平控制。

## 7. 修改前后对照表

| 项目 | 修改前 | 修改后 | 影响 | 为什么重要 |
| --- | --- | --- | --- | --- |
| `gt_ready` 连接 | DUT 未连接 | TB 显式连接并驱动 | 启动条件完整 | `laser_tx_core` 的 ENABLE 受 `gt_ready` 门控，未建模会导致启动条件不完整 |
| `dbg_gt_ready_tx` | 未观察 | TB 接出 | 可确认 TX 域 ready | 避免只看 TB 变量，确认 DUT 内部 debug 输出一致 |
| ENABLE 时序 | 复位前常高 | APPLY/cfg_valid 后再拉高 | 控制事件边界清楚 | 区分配置加载和启动发送两个事件 |
| reset/ready 顺序 | `tx_rst` 释放前无 GT ready 建模 | `gt_ready` 先稳定，再释放 `tx_rst` | 更接近上板 bring-up 时序 | 避免在 GT 未 ready 的条件下模拟发送启动 |
| 启动窗口检查 | 只等待 `busy_tx` | 并行检查 10 项启动条件 | 增强定位能力 | 能判断是 TB 条件缺失、配置非法，还是 RTL start 接收问题 |
| RTL 功能 | 未修改 | 未修改 | 不改变硬件功能 | 本轮只修仿真环境，不改变综合逻辑 |
| pipeline latency | 未修改 | 未修改 | 无 pipeline 变化 | 不影响数据/valid 对齐 |
| 测试覆盖 | 原有三组 scenario | 原有三组 scenario + 启动窗口诊断 | 覆盖增强 | 能覆盖 `gt_ready/tx_rst/cfg_valid/busy/valid_mask` 的启动链路 |

## 8. 验证结果

执行过的仿真命令为：

```bat
call D:\Vitis\2022.2\settings64.bat
xvlog -sv laser_tx.srcs/sources_1/new/laser_tx_core/cdc_toggle_sync.v laser_tx.srcs/sources_1/new/laser_tx_core/config_loader.v laser_tx.srcs/sources_1/new/laser_tx_core/pattern_source.v laser_tx.srcs/sources_1/new/laser_tx_core/pattern_tx_engine.v laser_tx.srcs/sources_1/new/laser_tx_core/sync_signal_gen.v laser_tx.srcs/sources_1/new/laser_tx_core/status_register.v laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v laser_tx.srcs/sim_1/new/tb_laser_tx_core.sv
xelab -debug typical tb_laser_tx_core -s tb_laser_tx_core_sim
xsim tb_laser_tx_core_sim -runall
```

关键日志摘录：

```text
Scenario 1: PRBS6, 63 phases, repeat/gap checking
scenario 1 startup window: gt_ready=1 dbg_gt_ready_tx=1 tx_rst=0 cfg_valid_tx=1 cfg_error=0 pattern_valid_tx=1 state_left_idle=1 busy_seen=1 done_seen=0 valid_mask_seen=1 repeat_cycles=4 insert_after=2 gap_len_bits=5 loop_en=0 direct_len_sel=0

Scenario 2: direct 127-bit pattern
scenario 2 startup window: gt_ready=1 dbg_gt_ready_tx=1 tx_rst=0 cfg_valid_tx=1 cfg_error=0 pattern_valid_tx=1 state_left_idle=1 busy_seen=1 done_seen=1 valid_mask_seen=1 repeat_cycles=2 insert_after=1 gap_len_bits=8 loop_en=0 direct_len_sel=1

Scenario 3: invalid repeat_cycles=0
PASS: all laser_tx_core scenarios passed
```

这说明：

```text
gt_ready=1；
dbg_gt_ready_tx=1；
tx_rst=0；
cfg_valid_tx=1；
cfg_error=0；
current_state_tx 离开 IDLE；
busy_tx 至少出现过一拍；
pattern_valid_tx=1；
valid_mask 非 0；
txdata 非 0；
SOA/ACQ/EOM 随发送状态变化。
```

因此，当前不能再记录为 `pattern_tx_engine` start 接收问题。

## 9. 边界与结论

本轮只修 testbench，不影响综合 RTL 和上板 bit/LTX。

本轮不解决 500M->1000M 动态切换中的 `MMCM_LOCK_TIMEOUT`。这两个问题不是同一条主线：

```text
本报告：testbench 启动条件建模问题；
MMCM_LOCK_TIMEOUT：动态速率切换时 MMCM DRP / reset / lock sequence 问题。
```

本轮未修改：

```text
laser_tx_core
pattern_tx_engine
BD
XDC
GT Wizard
Vitis
UDP 协议
GTX/MMCM DRP 逻辑
AD9528
```

最终结论：

修复后，仿真启动流程与真实硬件控制链路一致：`gt_ready` 先稳定，APPLY 完成后再 ENABLE。`pattern_tx_engine` 能离开 IDLE，`busy_tx`、`pattern_valid_tx`、`valid_mask`、`txdata` 以及 SOA/ACQ/EOM 输出均能正常出现。因此 `engine_start_tx=1` 但 `busy_tx=0` 的原始现象属于 testbench 启动条件不完整造成的观察失真，不是 `pattern_tx_engine` RTL 功能错误。


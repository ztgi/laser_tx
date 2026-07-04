# 500M -> 1000M 首次真实动态切换 MMCM_LOCK_TIMEOUT 分析报告

## 1. 本轮目标与边界

本轮只分析首次 500M -> 1000M 真实动态切换上板失败原因，重点定位：

```text
为什么 GTX DRP done、MMCM DRP done 后，TX user clock MMCM locked 没有回来。
```

本轮不做以下事项：

```text
不修改 RTL；
不修改 BD；
不修改 XDC；
不修改 Vitis；
不修改 UDP 协议；
不修改 GTX/MMCM DRP 参数；
不新增速率；
不接 AD9528；
不重新生成 bit/LTX；
不声明动态切换成功。
```

本报告结论基于：

```text
1. 用户提供的 UDP / Vivado ILA GUI 截图；
2. 当前 RTL 结构检查；
3. 当前 DRP 参数确认报告；
4. 当前静态 500M / 1000M clocking helper 对比。
```

## 2. 截图证据归档

用户提供的两张截图已复制到：

```text
D:/FPGA_Learn/laser_tx/docs/images/dynamic_rate/udp_status/udp_rate_status_mmcm_lock_timeout_500_to_1000.png
D:/FPGA_Learn/laser_tx/docs/images/dynamic_rate/500_to_1000_mmcm_lock_timeout/ila_rate_switch_500_to_1000_mmcm_drp_wait.png
```

### 2.1 UDP rate status / GT status 截图

![UDP rate status MMCM_LOCK_TIMEOUT]()

图 1 UDP `rate status` 与 `READ_GT_STATUS` 结果。可以看到最终状态为：

```text
mode=dynamic_500m_1000m
current_rate=500
current_rate_id=1
rate_state=RATE_ERROR
error_code=MMCM_LOCK_TIMEOUT
gt_drp_written=1
mmcm_drp_written=1
gt_drp_done=1
mmcm_drp_done=1
gt_ready=0
raw=0x0680f829
```

### 2.2 AXI/FCLK ILA rate switch 截图

![ILA rate switch MMCM DRP wait]()

图 2 AXI/FCLK ILA 波形。该截图显示 500M -> 1000M 切换过程中：

```text
target_rate_mbps = 1000
current_rate_mbps = 500
gt_drp_write_attempted = 1
mmcm_drp 相关信号有动作
rate_state 经过 04 / 05 / 06 / 08
txusrclk2_alive_axi = 0
txusrclk2_freq_counter_axi 停留在旧计数附近
```

截图中 cursor 处 `rate_error_code=0`，而 UDP 最终返回 `MMCM_LOCK_TIMEOUT`，二者不矛盾：ILA cursor 捕获的是 timeout 发生前的中间时刻，UDP 查询的是最终状态。

## 3. UDP raw status 解析

当前 `gt_status_out` 在 `laser_gt_tx_profile0.v` 中定义为：

```verilog
assign gt_status_out = {
    rate_error_code,
    rate_state,
    mmcm_drp_write_attempted,
    gt_drp_write_attempted,
    mmcm_drp_done,
    gt_drp_done,
    rate_error,
    rate_busy,
    rate_done,
    already_current_rate,
    1'b0,
    current_rate_id,
    ctrl_rst,
    ~gt_ready_tx,
    gt_ready_tx,
    txresetdone_sync,
    cplllock_sync
};
```

对 `raw=0x0680f829` 解码如下：

| 字段 | 值 | 含义 |
|---|---:|---|
| `rate_error_code` | `0x06` | `MMCM_LOCK_TIMEOUT` |
| `rate_state` | `0x80` | `RATE_ERROR` |
| `mmcm_drp_write_attempted` | `1` | 已尝试写 MMCM DRP |
| `gt_drp_write_attempted` | `1` | 已尝试写 GT DRP |
| `mmcm_drp_done` | `1` | MMCM DRP 写流程完成 |
| `gt_drp_done` | `1` | GT DRP 写 + readback 流程完成 |
| `rate_error` | `1` | 已进入错误状态 |
| `rate_busy` | `0` | 错误后不再 busy |
| `rate_done` | `0` | 未成功完成 |
| `current_rate_id` | `1` | 仍停留在 500M |
| `ctrl_rst` | `0` | 控制复位未拉高 |
| `~gt_ready_tx` | `1` | TX 侧未 ready |
| `gt_ready_tx` | `0` | GT ready 为 0 |
| `txresetdone_sync` | `0` | TX reset done 未恢复 |
| `cplllock_sync` | `1` | CPLL lock 仍为 1 |

结论：

```text
GT CPLL 本身没有丢 lock；
GT DRP 和 MMCM DRP 都走到 done；
失败点不是 UDP 命令解析，也不是 DRP ready timeout；
失败点是 release/reset 后 MMCM locked 没能回来，随后 GT TX resetdone/gt_ready 也无法恢复。
```

## 4. 当前状态机走到哪一步

`laser_gt_rate_switch_500m_1000m.v` 中状态编码：

| 状态 | 编码 | 说明 |
|---|---:|---|
| `RATE_ASSERT_RESET` | `0x04` | assert GT TX reset / txuserrdy block / MMCM reset |
| `RATE_PROGRAM_GT_DRP` | `0x05` | 写 GTX `TXOUT_DIV` |
| `RATE_PROGRAM_MMCM_DRP` | `0x06` | 写 MMCM DRP 表 |
| `RATE_WAIT_LOCK` | `0x08` | 等待 MMCM lock / CPLL lock / TX resetdone / gt_ready |
| `RATE_ERROR` | `0x80` | 错误终态 |

ILA 显示状态经过：

```text
04 -> 05 -> 06 -> 08
```

UDP 最终显示：

```text
RATE_ERROR, error_code=MMCM_LOCK_TIMEOUT
```

因此当前状态机至少已经完成：

```text
TX quiesce；
reset assert；
GT DRP；
MMCM DRP；
进入 WAIT_LOCK；
等待 MMCM locked 超时；
进入 RATE_ERROR。
```

## 5. MMCM DRP 写序列检查

当前 MMCM DRP 地址序列来自 `laser_gt_rate_switch_500m_1000m.v`：

| index | DRP addr | 含义 |
|---:|---:|---|
| 0 | `0x28` | Power register |
| 1 | `0x14` | CLKFBOUT Reg1 |
| 2 | `0x15` | CLKFBOUT Reg2 |
| 3 | `0x16` | DIVCLK_DIVIDE |
| 4 | `0x08` | CLKOUT0 Reg1 |
| 5 | `0x09` | CLKOUT0 Reg2 |
| 6 | `0x0A` | CLKOUT1 Reg1 |
| 7 | `0x0B` | CLKOUT1 Reg2 |
| 8 | `0x0C` | CLKOUT2 Reg1 |
| 9 | `0x0D` | CLKOUT2 Reg2 |
| 10 | `0x18` | LOCK Reg1 |
| 11 | `0x19` | LOCK Reg2 |
| 12 | `0x1A` | LOCK Reg3 |
| 13 | `0x4E` | FILTER Reg1 |
| 14 | `0x4F` | FILTER Reg2 |

1000M 目标写值：

| DRP addr | value | 含义 |
|---:|---:|---|
| `0x28` | `0xFFFF` | POWER |
| `0x14` | `0x128A` | CLKFBOUT Reg1 |
| `0x15` | `0x0000` | CLKFBOUT Reg2 |
| `0x16` | `0x1041` | DIVCLK_DIVIDE |
| `0x08` | `0x1514` | CLKOUT0 Reg1, divide 40 |
| `0x09` | `0x0000` | CLKOUT0 Reg2 |
| `0x0A` | `0x128A` | CLKOUT1 Reg1, divide 20 |
| `0x0B` | `0x0000` | CLKOUT1 Reg2 |
| `0x0C` | `0x1041` | CLKOUT2 Reg1 |
| `0x0D` | `0x00C0` | CLKOUT2 Reg2 |
| `0x18` | `0x00F4` | LOCK Reg1 |
| `0x19` | `0x7C01` | LOCK Reg2 |
| `0x1A` | `0x7DE9` | LOCK Reg3 |
| `0x4E` | `0x0800` | FILTER Reg1 |
| `0x4F` | `0x1800` | FILTER Reg2 |

当前写时序：

```text
当 timeout_count == 0：
  mmcm_drp_addr <= table[index]
  mmcm_drp_di   <= data[index]
  mmcm_drp_en   <= 1
  mmcm_drp_we   <= 1

之后等待：
  mmcm_drp_rdy == 1

收到 DRDY 后：
  index++
  进入下一项
```

检查结果：

```text
DEN/DWE 为单拍写；
每项写后等待 DRDY；
DRDY timeout 未触发；
MMCM DRP done 已置 1；
LOCK/FILTER 相关寄存器已写；
当前没有 MMCM DRP readback；
当前没有将 mmcm_drp_do/readback 接入 ILA。
```

因此，当前证据只能说明：

```text
MMCM DRP 接口完成了写事务；
不能证明写入值已经 readback 正确；
也不能证明 MMCM reset 已经真正释放；
更不能证明 MMCM 输入 clock 在等待 lock 阶段仍然存在。
```

## 6. 1000M MMCM 参数一致性检查

静态 500M `laser_gt_usrclk_profile0.v`：

```text
MMCM input TXOUTCLK = 15.625 MHz
CLKIN1_PERIOD      = 64.000 ns
DIVCLK_DIVIDE      = 1
CLKFBOUT_MULT_F    = 39.0
CLKOUT0_DIVIDE_F   = 78.0 -> TXUSRCLK2 = 7.8125 MHz
CLKOUT1_DIVIDE     = 39   -> TXUSRCLK  = 15.625 MHz
```

静态 1000M `laser_gt_usrclk_profile1_1000m.v`：

```text
MMCM input TXOUTCLK = 31.25 MHz
DIVCLK_DIVIDE      = 1
CLKFBOUT_MULT_F    = 20.0
CLKOUT0_DIVIDE_F   = 40.0 -> TXUSRCLK2 = 15.625 MHz
CLKOUT1_DIVIDE     = 20   -> TXUSRCLK  = 31.25 MHz
```

当前动态表中的 1000M 目标值与前置参数确认报告一致，目标方向是正确的：

```text
TXOUTCLK 31.25 MHz；
CLKFBOUT_MULT 20；
CLKOUT0 divide 40；
CLKOUT1 divide 20。
```

注意：

```text
CLKIN1_PERIOD 是 MMCME2_ADV 静态属性，不通过当前 MMCM DRP 表动态修改。
这通常主要影响时序/模型属性，不一定是锁定失败的直接原因；
但动态切换后实际输入周期从 64 ns 变为 32 ns，后续仍应确认 Vivado timing/DRC 对动态场景的约束表达。
```

## 7. reset / lock sequence 检查

当前连接结构：

```verilog
assign tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate;

.soft_reset_tx_in      (ctrl_rst | rate_gt_tx_reset)
.gt0_tx_mmcm_reset_out (tx_mmcm_reset_wizard)
.gt0_gttxreset_in      (ctrl_rst | rate_gt_tx_reset | ~cplllock_sync)
.gt0_txuserrdy_in      (~ctrl_rst & ~rate_txuserrdy_block &
                         cplllock_sync & tx_mmcm_locked_sync)
.gt0_txoutclk_out      (txoutclk)
```

当前状态机行为：

```text
RATE_ASSERT_RESET:
  rate_gt_tx_reset     = 1
  rate_txuserrdy_block = 1
  rate_mmcm_reset      = 1

RATE_PROGRAM_GT_DRP:
  rate_gt_tx_reset     = 1
  rate_txuserrdy_block = 1
  rate_mmcm_reset      = 1

RATE_PROGRAM_MMCM_DRP:
  rate_gt_tx_reset     = 1
  rate_txuserrdy_block = 1
  rate_mmcm_reset      = 1

RATE_RELEASE_RESET:
  rate_gt_tx_reset     = 1
  rate_txuserrdy_block = 1
  rate_mmcm_reset      = 0

RATE_WAIT_LOCK:
  if !tx_mmcm_locked_sync:
      rate_gt_tx_reset     = 1
      rate_txuserrdy_block = 1
      rate_mmcm_reset      = 0
      等待 MMCM lock
```

高风险点：

```text
虽然 rate_mmcm_reset 在 RATE_RELEASE_RESET / RATE_WAIT_LOCK 中释放为 0，
但 tx_mmcm_reset 实际是：

tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate

此时 rate_gt_tx_reset 仍为 1，soft_reset_tx_in 仍为 1。
GT Wizard TX reset FSM 很可能继续保持 tx_mmcm_reset_wizard=1。

因此 MMCM 的真实 RST 输入可能并没有释放。
如果 MMCM RST 一直为 1，tx_mmcm_locked 永远不会回来，最终必然进入 MMCM_LOCK_TIMEOUT。
```

这是当前最直接、最优先的嫌疑。

## 8. MMCM 输入时钟检查

当前 MMCM 输入路径：

```text
GT gt0_txoutclk_out -> txoutclk -> BUFG -> MMCME2_ADV CLKIN1
```

也就是说，TX user clock MMCM 的输入来自 GT `TXOUTCLK`。

当前 ILA2 clock stopped 与 `txusrclk2_alive_axi=0` 表明：

```text
TXUSRCLK2 在切换过程中确实停止或不可用。
```

但目前 ILA 中没有：

```text
txoutclk_alive；
tx_mmcm_reset_wizard；
tx_mmcm_reset_rate；
tx_mmcm_reset；
tx_mmcm_locked_raw；
```

所以还不能区分以下两种情况：

1. MMCM 真实 reset 没有释放；
2. MMCM reset 已释放，但 GT TXOUTCLK 在 GT reset / TXOUT_DIV DRP 后没有稳定输入。

两者都会导致 `tx_mmcm_locked_sync=0`，表现为同一个 `MMCM_LOCK_TIMEOUT`。

## 9. GT DRP 与 MMCM DRP 顺序检查

当前顺序是：

```text
1. assert GT TX reset / txuserrdy block / MMCM reset；
2. 写 GT TXOUT_DIV；
3. 写 MMCM DRP；
4. release rate_mmcm_reset；
5. 等 MMCM lock；
6. MMCM lock 后才释放 GT reset / txuserrdy block；
7. 等 txresetdone / gt_ready。
```

该顺序的潜在问题是：

```text
等待 MMCM lock 时仍保持 rate_gt_tx_reset=1；
而 rate_gt_tx_reset 同时驱动 soft_reset_tx_in 和 gttxreset；
GT Wizard reset FSM 可能持续要求 MMCM reset；
GT TXOUTCLK 也可能在该阶段不稳定或停止。
```

因此，当前 sequence 可能形成闭环死锁：

```text
等待 MMCM lock
  -> 但 GT soft reset / wizard mmcm reset 仍在
  -> MMCM reset 或输入 clock 不满足 lock 条件
  -> MMCM lock 永不回来
  -> rate controller 保持 GT reset
  -> 继续等 MMCM lock
  -> timeout
```

## 10. 最可能原因排序

### 第一嫌疑：MMCM 实际 reset 没有释放

证据：

```text
tx_mmcm_reset = tx_mmcm_reset_wizard | tx_mmcm_reset_rate；
RATE_WAIT_LOCK 中 rate_gt_tx_reset 仍为 1；
soft_reset_tx_in = ctrl_rst | rate_gt_tx_reset；
GT Wizard 的 tx_mmcm_reset_wizard 可能仍为 1；
UDP 最终为 MMCM_LOCK_TIMEOUT；
txresetdone_sync=0，gt_ready=0；
ILA2 clock stopped。
```

如果该判断成立，问题不在 MMCM DRP 写值本身，而在 reset sequencing。

### 第二嫌疑：GT TX reset 期间 TXOUTCLK 停止或不稳定

证据：

```text
MMCM 输入来自 GT TXOUTCLK；
切换期间 ILA2 clock stopped；
等待 MMCM lock 时 GT reset 仍保持；
若 TXOUTCLK 在此阶段停掉，MMCM 不可能 lock。
```

需要新增 `txoutclk_alive` 或等效计数器验证。

### 第三嫌疑：MMCM DRP 写值或写序列未被 readback 验证

证据：

```text
当前 mmcm_drp_done 只代表 DRDY 返回；
没有 readback 每个 MMCM DRP register；
没有 ILA 观测 mmcm_drp_addr/di/do/den/dwe/drdy；
如果某个 LOCK/FILTER 或 divide register 写错，MMCM 也可能不 lock。
```

但由于 1000M 写值与前置确认报告一致，且现象强烈指向 reset/clock 输入，当前排序低于 reset sequence 问题。

### 第四嫌疑：MMCM lock timeout 过短

当前参数：

```text
LOCK_TIMEOUT_CYCLES = 5,000,000
ctrl_clk = 50 MHz
timeout ≈ 100 ms
```

100 ms 对正常 MMCM relock 通常已经不短。因此“单纯 timeout 太短”的可能性较低。

## 11. 建议新增 debug-only probe

当前 ILA 不足以区分“MMCM reset 未释放”和“TXOUTCLK 输入停止”。建议下一轮只增加 debug-only probe，不修改功能逻辑：

```text
tx_mmcm_reset_wizard
tx_mmcm_reset_rate
tx_mmcm_reset
tx_mmcm_locked_raw
tx_mmcm_locked_sync
rate_gt_tx_reset
gt0_gttxreset_effective
rate_txuserrdy_block
gt0_txuserrdy_effective
mmcm_drp_addr[6:0]
mmcm_drp_di[15:0]
mmcm_drp_do[15:0]
mmcm_drp_en
mmcm_drp_we
mmcm_drp_rdy
txoutclk_alive_axi 或 txoutclk_toggle_axi
wait_lock_counter / timeout_count
rate_state[7:0]
rate_error_code[7:0]
```

其中 `txoutclk_alive_axi` 应采用安全 CDC：

```text
在 txoutclk 或 MMCM 输入侧生成 toggle/counter；
同步到 gt_ctrl_clk；
不要把未同步的多 bit counter 直接接 AXI ILA。
```

## 12. 下一步最小修复建议

建议分两步走，不要直接大改 MMCM 参数。

### Step 1：先加 debug-only probe 验证真实 reset/clock

目的：

```text
确认 RATE_WAIT_LOCK 阶段：
1. tx_mmcm_reset_wizard 是否仍为 1；
2. tx_mmcm_reset 是否真的释放；
3. txoutclk 是否 alive；
4. tx_mmcm_locked_raw 是否曾经拉高；
5. mmcm_drp_addr/di/do 是否按预期写完。
```

如果 `tx_mmcm_reset` 在 WAIT_LOCK 中仍为 1，则根因基本确认。

### Step 2：再调整 reset sequence

候选方向：

```text
1. 将 GT Wizard soft_reset_tx_in 与手动 gttxreset 控制解耦；
2. 在等待 MMCM lock 前，确保 tx_mmcm_reset_wizard 和 tx_mmcm_reset_rate 都释放；
3. 确保 MMCM 输入 TXOUTCLK 已经恢复或持续 alive；
4. MMCM locked 后，再按 GT Wizard 推荐 TX reset sequence 释放 txuserrdy / 等 txresetdone；
5. 保留 timeout/error_code，不允许失败后假装 current_rate 已更新。
```

注意：该修复需要 RTL 修改、重新 synthesis / implementation / bitstream / LTX，并重新上板验证。

## 13. 是否需要重新生成 bit/LTX

本轮只是分析和归档截图：

```text
不需要重新生成 bit/LTX。
```

如果下一轮新增 debug-only probe 或修复 reset sequence，则必须重新生成：

```text
bit
ltx
timing report
debug probe report
```

并确保 Hardware Manager 使用同源 bit/LTX。

## 14. 当前结论

当前首次真实动态切换没有成功。

可以确认：

```text
UDP 控制链路可通信；
rate set 已触发；
目标速率为 1000M；
GT DRP 已尝试且 done；
MMCM DRP 已尝试且 done；
CPLL lock 仍为 1；
最终失败在 MMCM_LOCK_TIMEOUT；
txresetdone / gt_ready 未恢复；
txusrclk2 在切换中停止或不可用。
```

不能声明：

```text
500M -> 1000M 动态切换成功；
1000M 动态速率已稳定；
外部光口闭环通过；
宽范围动态调速完成。
```

当前最可能根因是：

```text
等待 MMCM lock 时，GT Wizard 侧 `tx_mmcm_reset_wizard` 或 GT TX reset/soft reset 仍然使 MMCM reset 或 TXOUTCLK 输入条件不满足，导致 MMCM 无法重新 lock。
```

下一步应先用 debug-only probe 确认 `tx_mmcm_reset` 和 `txoutclk_alive`，再做最小 reset sequence 修复。

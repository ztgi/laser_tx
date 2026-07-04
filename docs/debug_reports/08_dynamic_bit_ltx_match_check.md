# dynamic_500m_1000m bit / LTX 匹配检查报告

生成时间：2026-07-01  
工程目录：`D:/FPGA_Learn/laser_tx`

## 1. 本轮问题现象

上板时 Vivado Hardware Manager 报错：

```text
Mismatch between the design programmed into the device and the probes file.
Device design has 2 ILA core(s), but the probes file has mismatched ILA input ports.
refresh_hw_device failed.
```

同时 UDP 通信正常：

```text
PING -> OK PONG
READ_GT_STATUS -> OK GT_STATUS 0x00000027
rate status -> OK RATE_STATUS mode=dynamic_500m_1000m current_rate=500 rate_state=RATE_IDLE ...
```

判断：

```text
这不是 UDP / lwIP / Vitis 命令解析问题。
当前问题是 FPGA 中已下载的 bitstream 与 Vivado Hardware Manager 加载的 probes/LTX 文件不是同一次实现生成的匹配组合。
```

## 2. 当前已通过的层级

```text
UDP PING：已通过
READ_GT_STATUS：已通过
rate status：已通过
dynamic_500m_1000m 软件模式读取：已通过
```

## 3. 当前未通过的层级

```text
Vivado Hardware Manager bit/LTX 匹配：修复前未通过
rate set 1000：尚未执行
rate set 500：尚未执行
动态切换上板验证：尚未执行
```

## 4. 本轮检查的 bit / LTX 文件

### 4.1 GUI/project impl_1 最新产物

| 文件 | Size | LastWriteTime | SHA256 |
|---|---:|---|---|
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.bit` | 17416462 bytes | 2026-07-01 13:34:25 | `700E431BF27CE7839F06F113A18A637E327C2E2977FC9687AB88E8B64F61DBDB` |
| `D:/FPGA_Learn/laser_tx/laser_tx.runs/impl_1/laser_tx_board_top.ltx` | 77478 bytes | 2026-07-01 13:34:25 | `5A5C5D8716D8A24159E01898018024C769A92E9442D3012D2BBFFFFA5B2331EA` |

### 4.2 artifacts 标准路径当前产物

本轮已将同一个 `impl_1` implemented design 的 bit/LTX 同步到 artifacts 标准路径：

| 文件 | Size | LastWriteTime | SHA256 |
|---|---:|---|---|
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 17416462 bytes | 2026-07-01 13:34:25 | `700E431BF27CE7839F06F113A18A637E327C2E2977FC9687AB88E8B64F61DBDB` |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 77478 bytes | 2026-07-01 14:54:29 | `5A5C5D8716D8A24159E01898018024C769A92E9442D3012D2BBFFFFA5B2331EA` |

结论：

```text
artifacts 标准路径中的 dynamic bit/LTX 当前已经与 GUI/project impl_1 最新产物匹配。
```

## 5. mismatch 原因说明

修复前，工程中存在两组 dynamic 相关产物：

1. `laser_tx.runs/impl_1/` 下的最新 GUI/project flow 产物；
2. `reports/dynamic_rate_500m_1000m/artifacts/` 下的旧 direct/artifact 产物。

修复前检查到 artifacts 旧文件时间为：

```text
laser_tx_board_top_dynamic_500m_1000m.bit  2026-06-30 23:37:11
laser_tx_board_top_dynamic_500m_1000m.ltx  2026-06-30 23:37:12
```

而 GUI/project 最新产物时间为：

```text
laser_tx_board_top.bit  2026-07-01 13:34:25
laser_tx_board_top.ltx  2026-07-01 13:34:25
```

并且修复前旧 artifacts LTX 中记录的 ILA clock 信息与最新 LTX 不一致：

```text
旧 artifacts LTX: clk_input_freq_hz = 50000000
最新 GUI/project LTX: clk_input_freq_hz = 7812500
```

因此 Hardware Manager 报：

```text
Device design has 2 ILA core(s), but the probes file has mismatched ILA input ports.
```

属于典型的“下载 bit 与加载 LTX 来自不同实现批次”的问题。

## 6. 哪个 bit 被下载、哪个 LTX 被加载

本轮没有直接读取用户 Vivado GUI 当时的 Program Device 历史选择，因此不能从本地文件系统绝对确认当时具体选择了哪两个路径。

结合现象和本地文件状态，最可能的情况是：

```text
FPGA 中下载的是最新 GUI/project dynamic bit，
但 Hardware Manager 加载了旧 artifacts LTX；
或反过来，下载旧 artifacts bit，却加载了最新 GUI/project LTX。
```

由于修复前两组 bit/LTX 的 hash、时间戳和 LTX 内容不一致，任意跨组混用都会触发 probes mismatch。

## 7. implemented design 中的 ILA core / probe 信息

从当前 `impl_1` implemented design 重新导出：

```text
report: D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_debug_cores_impl_1.rpt
```

implemented design 中 debug core：

```text
dbg_hub
ila_laser_axi_cfg
ila_laser_tx
```

debug hub 连接的 ILA peripheral 数量：

```text
2
```

ILA core：

| ILA core | probe port 数 | 主要观测内容 |
|---|---:|---|
| `ila_laser_axi_cfg` | 6 | `axi_gpio_0_gpio_io_o`、`gpio_status`、`dbg_bram_en`、`dbg_bram_addr`、`dbg_bram_dout`、`dbg_bram_rst` |
| `ila_laser_tx` | 15 | `txdata`、`valid_mask`、`eom_out`、`soa_gate_out`、`acq_trig_out`、`acq_gate_out`、`busy/done/phase/current_state/cfg_update/pattern_valid/engine_start` |

## 8. LTX 中 ILA/probe 匹配检查

当前 artifacts LTX：

```text
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

检查结果：

```text
ILA_CORE_COUNT = 2
TOTAL_PROBE_PORT_COUNT = 21
ILA core names:
  u_system_wrapper/system_i/ila_laser_axi_cfg
  u_system_wrapper/system_i/ila_laser_tx
clk_input_freq_hz = 7812500
```

与 implemented design 的：

```text
ila_laser_axi_cfg: 6 probe ports
ila_laser_tx: 15 probe ports
total: 21 probe ports
```

一致。

## 9. 本轮修改内容

本轮未修改 RTL / BD / XDC / Vitis / rate controller。

本轮只做：

1. 从当前 `impl_1` implemented design 重新导出匹配 LTX；
2. 将当前 `impl_1` bit 复制到 dynamic artifacts 标准路径；
3. 生成 debug core report；
4. 新增本报告。

修改/生成文件：

| 文件 | 说明 |
|---|---|
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit` | 已更新为当前 `impl_1` 同源 bit |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx` | 已从当前 `impl_1` implemented design 重新导出 |
| `D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/gui_project_debug_cores_impl_1.rpt` | 当前 implemented design debug core 报告 |
| `D:/FPGA_Learn/laser_tx/scripts/report_gui_project_debug_cores_impl_1.tcl` | 重新导出 debug core report 与 LTX 的辅助脚本 |
| `D:/FPGA_Learn/laser_tx/docs/debug_reports/08_dynamic_bit_ltx_match_check.md` | 本报告 |

## 10. 硬件接口一致性说明

本轮明确未修改：

```text
未修改 RTL
未修改 BD
未修改 XDC
未修改 Vitis
未修改 rate controller
未新增速率
未接 AD9528
未修改 GPIO / BRAM / GT status 地址
未修改 GTX DRP / MMCM DRP 逻辑
```

## 11. 构建验证记录

本轮未重新综合/实现/生成 bitstream。

使用已有 GUI/project `impl_1` implemented design：

```text
synth_1: 已完成
impl_1: 已完成
write_bitstream: 已完成
timing: 已通过，WNS=7.029 ns，TNS=0.000 ns
```

本轮执行：

```text
open_project ./laser_tx.xpr
open_run impl_1
report_debug_core -file reports/dynamic_rate_500m_1000m/gui_project_debug_cores_impl_1.rpt
write_debug_probes -force reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
Copy-Item impl_1/laser_tx_board_top.bit -> artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
Get-FileHash 检查 bit/LTX hash
```

## 12. 上板验证记录

用户当前已观察到：

```text
UDP PING -> OK PONG
READ_GT_STATUS -> OK GT_STATUS 0x00000027
rate status -> OK RATE_STATUS mode=dynamic_500m_1000m current_rate=500 rate_state=RATE_IDLE ...
```

当前仍未执行：

```text
rate set 1000
rate set 500
500M -> 1000M -> 500M 动态切换验证
```

本轮只收口 bit/LTX 匹配，不声明动态切换已通过。

## 13. 当前分层结论

| 层级 | 结论 |
|---|---|
| UDP PING | 已通过 |
| READ_GT_STATUS | 已通过 |
| rate status | 已通过 |
| bit/LTX 匹配 | artifacts 当前已修复为同源匹配对 |
| Hardware Manager refresh | 需要重新 Program Device 后验证 |
| rate set 1000 | 尚未执行 |
| rate set 500 | 尚未执行 |
| 动态切换上板验证 | 尚未通过，不能声明完成 |

## 14. 正确上板使用的 bit/LTX

请使用以下一对文件，不要跨目录混用：

```text
Bitstream:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit

Debug probes:
D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
```

这两个文件当前 hash 与 `impl_1` 同源产物一致。

## 15. 最终上板操作步骤

1. Open Hardware Manager；
2. Program Device；
3. Bitstream file 选择：

   ```text
   D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.bit
   ```

4. Debug probes file 选择：

   ```text
   D:/FPGA_Learn/laser_tx/reports/dynamic_rate_500m_1000m/artifacts/laser_tx_board_top_dynamic_500m_1000m.ltx
   ```

5. 点击 Program；
6. Program 完成后执行 Refresh Device；
7. 确认不再出现 bit/LTX mismatch；
8. 先执行：

   ```text
   PING
   READ_GT_STATUS
   rate status
   ```

9. 确认 Hardware Manager 和 UDP 状态都正常后，再进入：

   ```text
   rate set 1000
   rate status
   rate set 500
   rate status
   ```

## 16. 风险说明与下一步建议

1. 如果仍报 mismatch，优先检查 Vivado GUI Program Device 对话框中是否缓存了旧 LTX 路径；
2. 如果 GUI 自动加载了 `laser_tx.runs/impl_1/laser_tx_board_top.ltx`，也可以使用，但必须与 `laser_tx.runs/impl_1/laser_tx_board_top.bit` 成对使用；
3. 当前推荐统一使用 artifacts 标准路径，避免 GUI 自动混用旧路径；
4. bit/LTX 匹配通过前，不要继续执行 `rate set 1000`；
5. UDP 通信正常不等于动态切换上板通过。


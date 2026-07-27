# UDP 协议：TX Sequence V2 与动态速率控制

## 1. 当前边界

当前软件保留既有动态 rate planner/executor 命令，并将 TX 配置升级为唯一的 V2 record。V2 不兼容旧 8-word 配置和旧 `WRITE_CONFIG` 参数格式。

常用命令：

```text
PING
READ_STATUS
READ_GT_STATUS
WRITE_CONFIG ...
SELECT_CONFIG <index>
APPLY
ENABLE
DISABLE
SOFT_RESET
rate status
rate list
rate plan <Mbps> [nearest]
rate set <Mbps>
ad9528 status|dump|measure status|profile plan|candidate set/status/restore
```

动态速率支持状态以 `rate list` 和统一 profile table 为准；本文不再保留早期 500M/1000M dry-run 描述。普通 `rate set` 只允许 exact、verified profile，unsupported/nearest 规划不得静默触发 PL。

## 2. WRITE_CONFIG V2

语法：

```text
WRITE_CONFIG index seed repeat prbs direct direct127 phase loop head \
  gap0 ... gap(repeat-2) \
  eom_enable eom_global_index eom_lead_ticks eom_trail_ticks \
  pattern_low pattern_mid pattern_high pattern_top
```

参数约束：

| 参数 | 约束 |
|---|---|
| index | 0..127 |
| repeat | 1..16 |
| prbs | 6 或 7 |
| direct/direct127/phase/loop/eom_enable | 0 或 1 |
| head | 0..255 serial bits |
| gap0..gap14 | 每项 0..255 serial bits；只提供 repeat-1 项 |
| eom_global_index | 0..2047，且 enable 时必须落入本任务实例范围 |
| lead/trail | 0..65535 EOM ticks |
| pattern_top bit31 | 必须为 0 |

成功响应：

```text
OK WRITE_CONFIG index=<n> repeat=<n> gaps=<repeat-1> format=2 words=16
```

错误响应包括：

```text
ERR WRITE_CONFIG_ARGS
ERR WRITE_CONFIG_RANGE
ERR WRITE_CONFIG_GAP index=<n>
ERR WRITE_CONFIG_SEMANTICS
ERR WRITE_CONFIG_VERIFY
```

示例：

```text
# repeat=1，无 gap 参数
WRITE_CONFIG 0 0x3f 1 6 1 0 0 0 0 1 0 0 0 0x55555555 0x2aaaaaaa 0 0

# repeat=4，依次提供 gap0=5、gap1=13、gap2=21
WRITE_CONFIG 1 0x3f 4 6 1 0 1 0 8 5 13 21 1 7 2 3 0x55555555 0x2aaaaaaa 0 0
```

## 3. SELECT_CONFIG / APPLY / ENABLE

```text
SELECT_CONFIG <index>
APPLY
ENABLE
```

- `SELECT_CONFIG` 只接受 0..127，不再接收 source/length 等额外参数；
- source、length、phase、loop 等均在 V2 record 内；
- `APPLY` 翻转既有 toggle，PL 加载并验证整条 record；
- `ENABLE` 只在配置成功后启动任务。

推荐顺序：

```text
DISABLE
WRITE_CONFIG ...
SELECT_CONFIG <index>
APPLY
READ_STATUS
ENABLE
READ_STATUS
```

## 4. 原子性与 CRC

PS 按 invalid header → payload/CRC → readback → DMB → valid header 的顺序发布。PL 只有在 header 稳定、format/metadata/reserved 合法且 CRC32(words1..14) 匹配后才更新 active config。任一校验失败都不得覆盖 last-good config。

## 5. phase/repeat/gap/global EOM

每个 phase 结构：

```text
HEAD → pattern0 → gap0 → pattern1 → ... → gapN-2 → patternN-1
```

每个 repeat 从 phase 初始 offset 重新开始。global EOM index 按 phase-major、repeat-minor 编号。每个被接受任务最多产生一个 EOM；loop 不重新 arm。

详细 record 与时序语义见：

- `bram_config_map.md`
- `tx_phase_repeat_gap_global_eom.md`

## 6. rate 命令安全规则

- `rate list` 来自统一 verified profile table；
- `rate plan <Mbps>` 返回 EXACT/UNSUPPORTED；
- 显式 `nearest` 只给建议，不写 GPIO；
- `rate set <Mbps>` 只接受 exact verified profile；
- unsupported 请求不翻转 request toggle；
- DONE 成功还必须匹配 requested/current rate id；
- current rate 只在 VERIFY_RATE 成功后更新。

3000M 继续保持 blocked/unsupported，普通 `rate set 3000` 不得映射到 3125M。

## 7. AD9528 OUT0 只读测量

```text
ad9528 measure status
```

有效 snapshot：

```text
OK AD9528_MEASURE state=VALID_IN_RANGE valid=1 in_range=1 alive=1 \
sequence=<n> odiv2_count=<n> measured_odiv2_hz=<n> \
measured_out0_hz=<n> window_us=1000
```

无有效窗口时不得返回旧缓存频率。candidate status 的 `board_verified` 不因 FPGA 内部计数自动置 1；外部仪器和最终系统验证仍是独立边界。

## 8. 兼容性提示

```text
Functional behavior changed intentionally
```

旧 ELF、旧 bitstream、旧 8-word BRAM 内容和旧 UDP `WRITE_CONFIG` 命令不兼容。必须配套使用同一 V2 版本的 software 与 bitstream。

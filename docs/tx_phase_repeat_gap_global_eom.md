# TX Sequence V2：phase、repeat、独立 gap 与全局单次 EOM

## 1. 版本与兼容性

TX Sequence V2 是一次有意的协议不兼容升级。唯一配置格式为 16 个
32-bit word 的固定 record；不再支持旧 8-word record、单一公共 gap、
`insert_after`、continuation slot 或 V1/V2 自动判断。

旧 ELF、旧 bitstream 和旧 `WRITE_CONFIG` 命令不能与 V2 任意混搭。主机、
Vitis application、PL config loader 和 bitstream 必须来自同一 V2 版本。

## 2. 配置空间

配置 BRAM 容量为 8 KiB，即 2048 个 32-bit word。每条 record 固定占用
16 word（64 byte），因此：

```text
MAX_CONFIGS = 2048 / 16 = 128
index       = 0 .. 127
base_word   = index * 16
base_byte   = index * 64
```

`SELECT_CONFIG <index>` 只选择 record；`APPLY` 翻转既有 apply toggle，由 PL
加载、校验并原子更新 active config。

## 3. 16-word record 布局

所有多字节数值均按 32-bit little-endian word 写入 BRAM。

| Word | Bit | 字段 |
|---:|---:|---|
| 0 | 31:16 | magic = `16'h5458` |
| 0 | 15:12 | format version = 2 |
| 0 | 11 | commit valid；1 表示完整 record 已发布 |
| 0 | 10:8 | reserved，必须为 0 |
| 0 | 7:0 | sequence id |
| 1 | 31:0 | legacy seed reserved/ignored |
| 2 | 4:0 | repeat_cycles，合法范围 1..16 |
| 2 | 12:5 | legacy PRBS order reserved/ignored |
| 2 | 13 | phase_shift_en |
| 2 | 14 | loop_en |
| 2 | 15 | legacy source select reserved/ignored |
| 2 | 16 | configured pattern length；0=63，1=127 |
| 2 | 17 | eom_enable |
| 2 | 28:18 | eom_global_pattern_index |
| 2 | 31:29 | reserved，必须为 0 |
| 3 | 7:0 | head_delay_bits |
| 3 | 31:8 | reserved，必须为 0 |
| 4 | 每 8 bit | gap0、gap1、gap2、gap3 |
| 5 | 每 8 bit | gap4、gap5、gap6、gap7 |
| 6 | 每 8 bit | gap8、gap9、gap10、gap11 |
| 7 | 23:0 | gap12、gap13、gap14 |
| 7 | 31:24 | reserved，必须为 0 |
| 8 | 15:0 | eom_lead_ticks |
| 8 | 31:16 | eom_trail_ticks |
| 9 | 31:0 | configured pattern `[31:0]` |
| 10 | 31:0 | configured pattern `[63:32]` |
| 11 | 31:0 | configured pattern `[95:64]` |
| 12 | 30:0 | configured pattern `[126:96]` |
| 12 | 31 | reserved，必须为 0 |
| 13 | 7:0 | sequence mirror |
| 13 | 15:8 | record word count = 16 |
| 13 | 23:16 | max repeat = 16 |
| 13 | 31:24 | gap width = 8 |
| 14 | 31:0 | reserved，必须为 0 |
| 15 | 31:0 | CRC32(words 1..14) |

只有前 `repeat_cycles - 1` 个 gap 字段可以非零；其余 gap 必须为 0。

configured pattern是唯一pattern来源。PRBS周期由PS预生成后写入word9..12；
PL内部PRBS/LFSR和PRBS/direct source mux已删除。任务被接受时，
`pattern_tx_engine`锁存完整active pattern；随后BRAM shadow发生变化不会
污染正在执行的任务。

## 4. CRC 与原子提交

CRC 使用 reflected CRC-32/ISO-HDLC：

```text
polynomial = 0xEDB88320
initial    = 0xFFFFFFFF
final xor  = 0xFFFFFFFF
coverage   = word1 .. word14
byte order = each 32-bit word least-significant byte first
```

PS 原子写入顺序：

1. 先写 `commit_valid=0` 的 word0，使旧 record 失效；
2. 写 word1..word15（payload、metadata、CRC）；
3. 回读比较全部 16 word；
4. 执行 DMB；
5. 最后写 `commit_valid=1` 的 word0，作为唯一提交点；
6. 回读 word0，并再次执行 DMB。

PL 对 header 做前后两次稳定性检查，只在 magic、version、metadata、
reserved bits、sequence mirror 和 CRC 全部通过后，一次性更新 active config。
半写 record、CRC 错误或提交期间 header 改变均不得破坏 last-good active
config。

## 5. phase / HEAD / repeat / gap 语义

单个 phase 的发送顺序为：

```text
HEAD
pattern[0]
gap[0]
pattern[1]
gap[1]
...
gap[N-2]
pattern[N-1]
```

其中 `N = repeat_cycles`。所以 N 个 pattern 之间恰好有 N-1 个独立 gap；
最后一个 pattern 后没有 gap。每个 repeat 均从当前 phase 的初始 offset
重新开始，不会沿用上一个 repeat 的 pattern index。

`phase_shift_en=0` 时仅执行 phase 0；使能后：

```text
63-bit pattern  : phase 0..62
127-bit pattern : phase 0..126
```

每个 phase 都重新执行 HEAD 和该 phase 的 N 个 pattern/N-1 个 gap。

## 6. 全局 pattern index 与单次 EOM

全局 pattern instance 的编号顺序为 phase-major、repeat-minor：

```text
phase_count  = phase_shift_en ? pattern_len : 1
instance_cnt = phase_count * repeat_cycles
phase_index  = floor(global_index / repeat_cycles)
repeat_index = global_index % repeat_cycles
```

当 `eom_enable=1` 时，`eom_global_pattern_index` 必须小于
`instance_cnt`。geometry precompute 计算被选 pattern 的 bit 起止位置，
再按当前 profile 的 `serial_bits_per_eom_tick` 转换为 EOM clock tick，并应用
lead/trail。

EOM 每个被接受的任务最多触发一次。`loop_en=1` 只循环 pattern sequence，
不会重新 arm EOM；只有新的任务启动才会重新 arm。

## 7. 低速固定档的 EOM 时基

| Line rate | TXUSRCLK2 | EOM clock | K=`2^subdiv` | serial bits/tick | tick |
|---:|---:|---:|---:|---:|---:|
| 500 Mb/s | 7.8125 MHz | 125 MHz | 16 | 4 | 8 ns |
| 1000 Mb/s | 15.625 MHz | 125 MHz | 8 | 8 | 8 ns |
| 2000 Mb/s | 31.25 MHz | 125 MHz | 4 | 16 | 8 ns |

pattern 的理想串行持续时间：

| Line rate | 63 bit | 127 bit |
|---:|---:|---:|
| 500 Mb/s | 126 ns | 254 ns |
| 1000 Mb/s | 63 ns | 127 ns |
| 2000 Mb/s | 31.5 ns | 63.5 ns |

HEAD 与每个 gap 的配置范围均为 0..255 serial bits，实际时间等于
`bits / line_rate`。EOM 起止边界量化到 8 ns tick；这不改变 pattern engine
按 serial-bit 计数的 HEAD/gap 语义。

## 8. UDP 命令

唯一 V2 写配置语法为：

```text
WRITE_CONFIG index repeat pattern127 phase loop head \
  gap0 ... gap(repeat-2) \
  eom_enable eom_global_index eom_lead_ticks eom_trail_ticks \
  pattern_low pattern_mid pattern_high pattern_top
```

`repeat=1` 时没有 gap 参数。命令成功返回：

```text
OK WRITE_CONFIG index=<n> repeat=<n> gaps=<repeat-1> pattern_bits=<63|127> format=2 words=16 pattern_source=CONFIGURED internal_prbs=REMOVED
```

随后使用：

```text
SELECT_CONFIG <index>
APPLY
ENABLE
```

## 9. reset / abort / clock-safe 行为

reset 或 clock-safe 失效时，EOM 物理输出由组合安全门立即拉低。时钟恢复后先
经过两个 EOM clock edge 清除 stale state，再允许重新打开窗口。abort、
MMCM/GT 不 ready 或新任务重置均不得保留旧 EOM 高电平。

当前仿真已覆盖上述 V2 协议、原子加载、phase/repeat/gap、单次 EOM 和
clock-safe abort 行为。旧 routed DCP 仍存在 EOM 公共跨时钟 setup/hold
违例及 CDC Critical，因此仿真通过不等价于可安全上板；必须先完成 CDC
结构修复并重新实现。

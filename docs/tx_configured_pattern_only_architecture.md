# TX configured-pattern-only 架构

## 1. 变更性质

本变更是有意的功能裁剪，不是bug修复。PL内部实时PRBS6/PRBS7 LFSR和
PRBS/direct source mux已移除。当前准确表述为：

> 支持由PS配置的63/127-bit周期PRBS码发送及相对Delay空间扫描。

PL继续负责确定性的HEAD、phase、repeat、独立gap、wrap、loop、EOM调度和
每个TXUSRCLK2周期64-bit输出。PRBS码内容由软件预生成并写入配置BRAM。

## 2. 数据路径

修改前：

```text
seed/prbs_order -> internal LFSR
                              \
direct_pattern ----------------> source mux -> base_pattern -> pattern_tx_engine
```

修改后：

```text
PS/BRAM configured_pattern[126:0]
-> AXI active bundle
-> TX-domain config snapshot
-> task active snapshot
-> pattern_tx_engine
```

`pattern_tx_engine`接受任务时把configured pattern锁存到
`phase_zero_pattern_state`。任务执行期间新的BRAM shadow或后续配置更新不会
改变该active snapshot；下一次任务才使用新pattern。

## 3. 16-word布局兼容

record仍为16个32-bit word，stride仍为64 byte，index仍为0..127，CRC仍覆盖
word1..14，原子提交仍为invalid header → payload/CRC → valid header。

| 位置 | 当前语义 |
|---|---|
| word1 | legacy seed，reserved/ignored |
| word2[12:5] | legacy prbs_order，reserved/ignored |
| word2[15] | legacy source select，reserved/ignored |
| word2[16] | configured pattern长度；0=63，1=127 |
| word9..12 | configured pattern唯一payload |

没有重排BRAM字段，没有改变AXI地址，也没有改变CRC或header格式。

## 4. legacy PRBS黄金周期

黄金向量只用于证明旧发生器输出可以由configured pattern逐bit复现，不再是
production RTL模块。

### PRBS6

```text
polynomial       = x^6 + x^5 + 1
seed input       = 0x0000005A
effective seed   = seed[5:0] = 6'h1A
output bit       = lfsr[5]
feedback         = lfsr[5] XOR lfsr[4]
shift            = {lfsr[4:0], feedback}
configured bit i = 第i个输出bit
bit0发送顺序     = configured_pattern[0]先发送
period           = 63 bit
golden           = 0x376938BCA3083F56
```

BRAM word：

```text
word9  = 0xA3083F56
word10 = 0x376938BC
word11 = 0x00000000
word12 = 0x00000000
```

### PRBS7

```text
polynomial       = x^7 + x^6 + 1
seed input       = 0x0000005A
effective seed   = seed[6:0] = 7'h5A
output bit       = lfsr[6]
feedback         = lfsr[6] XOR lfsr[5]
shift            = {lfsr[5:0], feedback}
configured bit i = 第i个输出bit
bit0发送顺序     = configured_pattern[0]先发送
period           = 127 bit
golden           = 0x491C2F95CD13C50C103FAA6774B1BDAD
```

BRAM word：

```text
word9  = 0x74B1BDAD
word10 = 0x103FAA67
word11 = 0xCD13C50C
word12 = 0x491C2F95
```

RTL自检对每个TX word的64个lane分别比较`txdata`和`valid_mask`，不是只比较
十六进制显示。

## 5. 功能边界

保持：

- 63/127-bit周期；
- phase和每repeat从相同phase offset重新开始；
- HEAD、1..16 repeat、最多15个独立gap；
- word中间跨segment拼接、wrap和loop；
- 每任务最多一次EOM；
- `first_sequence_word_fire`和两路scope debug输出；
- `PIPELINE_LATENCY=0`及64-bit/周期吞吐；
- reset/abort/clock-unsafe安全行为。

删除：

- production `pattern_source.v`；
- PRBS6/PRBS7 LFSR；
- seed/prbs_order/source select的TX-domain状态和宽source mux。

未证明：

- 本变更后的硬件上板功能；
- 外部光口、眼图或BER；
- timing signoff（必须以本轮重新实现报告为准）。

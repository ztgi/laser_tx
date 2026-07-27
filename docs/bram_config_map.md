# BRAM 配置表（TX Sequence V2）

## 格式版本

TX Sequence V2 只支持 16 个 32-bit word（64 byte）的固定 record。8 KiB 配置 BRAM 共 2048 word，因此：

```text
LASER_TX_RECORD_WORD_COUNT  = 16
LASER_CONFIG_STRIDE_BYTES   = 64
LASER_TX_RECORD_MAX_CONFIGS = 128
index                       = 0..127
base_word                   = index << 4
```

旧 8-word 配置、`insert_after`、单一公共 gap 和 V1/V2 兼容分支均已删除。

## 逐 word 定义

| Word | 内容 |
|---:|---|
| 0 | `[31:16]=0x5458` magic，`[15:12]=2` version，`[11]` commit valid，`[10:8]=0`，`[7:0]` sequence |
| 1 | seed |
| 2 | repeat、PRBS/direct/phase/loop/EOM 控制和 global EOM index |
| 3 | `[7:0]` head_delay_bits，其余保留 0 |
| 4..6 | gap0..gap11，每项 8 bit |
| 7 | gap12..gap14，`[31:24]=0` |
| 8 | `[15:0]` EOM lead ticks，`[31:16]` EOM trail ticks |
| 9..11 | direct pattern `[95:0]` |
| 12 | direct pattern `[126:96]`，bit31 保留 0 |
| 13 | sequence mirror、word count=16、max repeat=16、gap width=8 |
| 14 | 保留 0 |
| 15 | words 1..14 的 reflected CRC-32/ISO-HDLC |

word2 bit packing：

| Bit | 字段 |
|---:|---|
| 4:0 | repeat_cycles，1..16 |
| 12:5 | prbs_order，6/7 |
| 13 | phase_shift_en |
| 14 | loop_en |
| 15 | direct_source |
| 16 | direct_len_127 |
| 17 | eom_enable |
| 28:18 | eom_global_pattern_index |
| 31:29 | reserved=0 |

## CRC、字节序与原子写

CRC 参数：

```text
poly       = 0xEDB88320
init       = 0xFFFFFFFF
final xor  = 0xFFFFFFFF
coverage   = word1..word14
byte order = little-endian within each 32-bit word
```

PS 写入顺序：

```text
invalid word0
→ word1..word15
→ readback
→ DMB
→ valid word0（唯一 commit 点）
→ readback + DMB
```

PL 通过前后两次 header 读取、metadata/reserved 检查和 CRC 校验，只在完整 record 稳定有效后更新 active config。错误或半写 record 必须保留 last-good config。

BRAM Port B 继续为 PL 只读：`bram_clk=axi_clk`、`bram_rst=~axi_rstn`、`bram_we=0`、`bram_din=0`。

完整 phase/repeat/gap/EOM 语义见 `tx_phase_repeat_gap_global_eom.md`。

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
| 1 | legacy seed reserved/ignored（保留布局，不再驱动PL LFSR） |
| 2 | repeat、configured-pattern length、phase/loop/EOM 控制和 global EOM index |
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
| 12:5 | legacy prbs_order reserved/ignored |
| 13 | phase_shift_en |
| 14 | loop_en |
| 15 | legacy source select reserved/ignored |
| 16 | configured_pattern_len_127；0=63 bit，1=127 bit |
| 17 | eom_enable |
| 28:18 | eom_global_pattern_index |
| 31:29 | reserved=0 |

`word9..12`中的127-bit configured pattern是唯一TX pattern来源。63-bit
模式仅使用`pattern[62:0]`。软件可以预生成PRBS周期并写入该payload；PL中
不再包含PRBS6/PRBS7 LFSR或PRBS/direct source mux。

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

## 动态 descriptor 物理存储拓扑

动态 descriptor 地址窗口为 `0x42000000`、4 KiB（1024×32-bit）。当前 BD 只有
一块 `blk_mem_dyn_desc` True Dual Port RAM：

```text
PS AXI → axi_bram_dyn_desc (SINGLE_PORT_BRAM=1) / BRAM_PORTA
       → blk_mem_dyn_desc / BRAM_PORTA
PL mailbox (gt_ctrl_clk) → blk_mem_dyn_desc / BRAM_PORTB
```

历史自动生成的 `axi_bram_dyn_desc_bram` 已从 BD 和 active compile order 删除，
因此 PS 写入、PS 回读以及 PL mailbox 读出的 sequence/CRC/首尾 word 均来自同一
物理 RAM。该结论已由 BD 连接检查和 mailbox descriptor 仿真验证；尚未替代真实
硬件读写回归。

BRAM Port B 为 PL 只读：`bram_clk=gt_ctrl_clk`、`bram_rst=gt_ctrl_rst`、
`bram_we=0`、`bram_din=0`。Port A 由 PS AXI controller 访问；两端共享同一
`blk_mem_dyn_desc` 实例而非两块独立 RAM。

完整 phase/repeat/gap/EOM 语义见 `tx_phase_repeat_gap_global_eom.md`。

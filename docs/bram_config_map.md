# BRAM 配置表

每个配置项占 8 个 32-bit word（32 byte）；`LASER_CONFIG_STRIDE_BYTES=32`，格式保持原有 RTL 定义。

| Word | 内容 |
|---:|---|
| 0 | seed |
| 1 | repeat_cycles |
| 2 | gap_len_bits / insert_after 等控制字段 |
| 3 | mode_cfg：source、direct 长度、PRBS、phase、loop 等 |
| 4 | pattern_low |
| 5 | pattern_mid |
| 6 | pattern_high |
| 7 | pattern_top |

准确 bit packing 以 `config_loader.v` 与现有 `laser_bram.c` 为唯一实现依据；UDP `WRITE_CONFIG`、UART 测试和 `SET_TEST_CASE` 必须复用同一生成/校验函数，不能维护多份格式。

BRAM Port B：`bram_clk=axi_clk`、`bram_rst=~axi_rstn`、只读 `bram_we=0`、`bram_din=0`。

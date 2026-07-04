# Laser TX first-stage board bring-up checklist

本阶段只验证 PS→BRAM/GPIO→PL 数据流和同步信号。不要连接激光器，不配置 AD9528，不做 GTX 动态速率切换。

## 1. Build preparation

- [ ] 执行 `scripts/bd_connect_laser_tx_core.tcl`。
- [ ] 当前无 GT Wizard 时确认日志出现临时 FCLK0 警告。
- [ ] 执行 `scripts/bd_add_laser_ila.tcl`。
- [ ] 打开 `constraints/laser_sync_pins_template.xdc`，根据板卡原理图填写管脚和电压；不确定时保持注释，不连接外部激光硬件。
- [ ] Validate Design 无错误。
- [ ] 执行 `scripts/run_build_bitstream.tcl`，确认 synthesis、implementation、bitstream 完成。
- [ ] 检查 `txusrclk2` 时钟域 timing summary，不接受 unconstrained path。
- [ ] 用生成的 `laser_tx.xsa` 创建/更新 Vitis platform，构建 `vitis_bringup` 裸机程序。

## 2. Common test procedure

每次测试都执行：

1. `enable=0`。
2. 置位再清除 `soft_reset`。
3. 向指定 `index` 的 BRAM 区域写入全部 8 个 32-bit word。
4. 立即读回比较 8 个 word，全部一致才继续。
5. 设置 `config_index`、source select 和 direct length select。
6. 翻转 `apply_toggle`；不要生成窄脉冲，也不要强制每次写 1。
7. AXI ILA 确认 Port B 读取 `base+0x00 ... base+0x1c`。
8. 等待 `cfg_valid=1 && cfg_error=0`；非法测试则等待 `cfg_error=1`。
9. 合法测试拉高 `enable`。
10. TX ILA 检查数据、mask、EOM、SOA 和 ACQ。

## 3. Test A — Direct 63 bit

- [ ] `index=0`，direct source，63-bit length。
- [ ] seed `0x3f`，order 6，repeat 2，无 gap，phase shift 关闭，loop 关闭。
- [ ] pattern words：`55555555 2aaaaaaa 00000000 00000000`。
- [ ] `cfg_valid=1`，`pattern_valid=1`，随后 busy 拉高。
- [ ] TXDATA 只使用 direct pattern 的 `[62:0]`，不存在第 64/128 bit。
- [ ] Phase shift 关闭时 phase offset 保持 0，最终 done 拉高。

## 4. Test B — Direct 63 bit plus gap

- [ ] repeat 4，insert after 2，gap 128，phase shift 关闭。
- [ ] 触发 `valid_mask==0`，至少捕获一个纯 gap word。
- [ ] 纯 gap word：`txdata=0`、`valid_mask=0`、`eom_out=0`。
- [ ] 同一个 gap word：`soa_gate_out=1`、`acq_gate_out=1`。
- [ ] Gap 结束后 pattern 数据继续，不能提前结束 phase。

## 5. Test C — PRBS6

- [ ] seed `0x3f`，order 6，repeat 4，insert after 2，gap 5。
- [ ] phase shift 开启、loop 关闭。
- [ ] phase offset 覆盖 0 到 62，没有 63。
- [ ] 每个 phase 开头 `acq_trig_out` 仅持续一个 TX user clock。
- [ ] 部分 gap word 中 `valid_mask` 对应 lane 为 0，`eom_out` 仍等于 mask 的 OR。

## 6. Optional extension — Direct 127 / PRBS7

- [ ] Direct 127 使用 `{pattern_top[30:0], high, mid, low}`，明确忽略 top bit 31。
- [ ] PRBS7 使用 order 7 和非零 7-bit seed。
- [ ] phase offset 覆盖 0 到 126，不出现 127。

## 7. Test D — Illegal configuration

- [ ] 设置 `repeat_cycles=0` 并 apply。
- [ ] `cfg_error=1`、`cfg_valid=0`、`busy=0`。
- [ ] `error_code=0x01`。
- [ ] 没有新的 `acq_trig_out`，TXDATA/valid mask 保持空闲。
- [ ] 可继续测试 order 5 → error `0x02`，insert_after 大于 repeat → error `0x03`。

## 8. Pass criteria before GT integration

- [ ] PS BRAM 写入和读回完全一致。
- [ ] apply 后 AXI ILA 看到正确的 8-word Port B 读取。
- [ ] GPIO status 合法/非法状态符合预期。
- [ ] 四类 pattern 测试的 phase 范围正确。
- [ ] Gap、EOM、SOA、ACQ 波形关系正确。
- [ ] 两个 ILA 均工作且无跨时钟采样。
- [ ] 临时 FCLK0 验证不连接激光器或 GTX 串行输出。

## 9. When to connect GT Wizard

以上检查全部通过后再添加 GT Wizard。届时必须：

1. 配置 64-bit TX user interface；宽度不符时修改 Wizard，不能截断 `txdata`。
2. `txdata[63:0]` 接 Wizard 对应通道 `txdata_in[63:0]`。
3. TXOUTCLK 经 Wizard/example clock helper 生成两路同源 TX user clock：`TXUSRCLK` 驱动 GT `txusrclk`，`TXUSRCLK2` 驱动 GT `txusrclk2` 与 `laser_tx_core/txusrclk2`。
4. 删除 FCLK0→`txusrclk2` 和 peripheral_reset→`tx_rst` 的临时连接。
5. 用 `txusrclk2` 域同步复位，并在 GT TX reset done 前保持 core reset。
6. `valid_mask` 仍然只接 ILA，不接 GTX。
7. 重新实现、检查 TX 时钟约束和 timing，再考虑连接外部激光驱动。

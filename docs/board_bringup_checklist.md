# TX Sequence V2 low-speed board bring-up checklist

> 当前 V2 routed 结果存在公共 EOM CDC 与 setup/hold 违例。本清单只定义
> 后续通过 timing/CDC 后的上板步骤；在 53 号报告的 blocker 关闭前，不应
> 下载当前 V2 artifact。

## 1. Build gate

- [ ] Module Reference 已 refresh，两个 EOM RTL 均进入 compile order。
- [ ] `validate_bd_design` 无 error。
- [ ] HDL wrapper 与 BD 一致。
- [ ] OOC synthesis 和 top synthesis/implementation 均基于 refresh 后源码。
- [ ] route fully routed，无 unrouted nets。
- [ ] DRC error=0。
- [ ] setup WNS>=0、TNS=0。
- [ ] hold WHS>=0、THS=0。
- [ ] EOM request/geometry/clock-safe CDC 无 Critical。
- [ ] 四个同步输出的板级 output-delay 模型已明确。
- [ ] 生成同一 build 的 bit/LTX/XSA。
- [ ] Vitis platform/BSP 使用该 XSA，clean build 配套 ELF。

## 2. V2 common procedure

每个配置执行：

1. `DISABLE`；
2. 必要时 `SOFT_RESET`；
3. 执行唯一 V2 `WRITE_CONFIG`；
4. 确认返回 `format=2 words=16`；
5. `SELECT_CONFIG <index>`，index 必须为 0..127；
6. `APPLY`；
7. AXI ILA 检查 16-word loader、CRC 和 active update；
8. 确认 config valid、无 loader error；
9. `ENABLE`；
10. TX/EOM ILA 检查 sequence 与单次 EOM。

旧 8-word、`insert_after` 和公共 gap 命令不得使用。

## 3. Record / CRC / atomicity

- [ ] magic=`0x5458`、version=2、commit valid=1。
- [ ] word13 sequence mirror 与 word0 相同。
- [ ] word13 metadata 为 words=16、max repeat=16、gap width=8。
- [ ] reserved fields 全为 0。
- [ ] word15 CRC 覆盖 word1..14。
- [ ] 半写 payload 时 active config 不改变。
- [ ] CRC 错误时 active config 不改变。
- [ ] commit 期间 header 变化时 active config 不改变。
- [ ] 正确 record 只原子更新一次。

## 4. Sequence cases

### A. repeat=1

- [ ] 不提供 gap 参数。
- [ ] 每个 phase 为 HEAD→pattern。
- [ ] 不访问 gap0。
- [ ] EOM global index 0 选择第一个 pattern。

### B. repeat=2

- [ ] 提供 gap0。
- [ ] 每个 phase 为 HEAD→pattern0→gap0→pattern1。
- [ ] pattern1 后无 gap。
- [ ] 两个 repeat 都从当前 phase 初始 offset 开始。

### C. mixed gaps

- [ ] repeat=5，提供四个不同 gap。
- [ ] gap0..gap3 的顺序和持续 bit 数分别正确。
- [ ] gap 期间 `valid_mask=0`，pattern 恢复后数据相位正确。

### D. repeat=16 boundary

- [ ] 提供 gap0..gap14。
- [ ] 未使用的 gap 字段不存在。
- [ ] 15 个 gap 均逐项匹配，最后 pattern 后无 gap。

### E. phase

- [ ] Direct/PRBS 63-bit：phase 0..62。
- [ ] Direct/PRBS 127-bit：phase 0..126。
- [ ] 每个 phase 都重新执行 HEAD 与全部 repeat/gap。

## 5. Global one-shot EOM

- [ ] global index 采用 phase-major、repeat-minor。
- [ ] index 合法时每个任务最多一脉冲。
- [ ] lead/trail 以当前 EOM tick 表达。
- [ ] loop 数据循环时 EOM 不重复。
- [ ] 新任务才重新 arm。
- [ ] invalid index/eom disabled 不输出脉冲。
- [ ] reset/abort/MMCM/GT not-ready 时 EOM 立即为低。
- [ ] 时钟恢复后不会 stale reopen。

## 6. 低速档核对

| Rate | TXUSRCLK2 | EOM clock | K | tick |
|---:|---:|---:|---:|---:|
| 500M | 7.8125 MHz | 125 MHz | 16 | 8 ns |
| 1000M | 15.625 MHz | 125 MHz | 8 | 8 ns |
| 2000M | 31.25 MHz | 125 MHz | 4 | 8 ns |

- [ ] 500M：63/127-bit pattern 为 126/254 ns。
- [ ] 1000M：63/127-bit pattern 为 63/127 ns。
- [ ] 2000M：63/127-bit pattern 为 31.5/63.5 ns。
- [ ] HEAD/gap 时间等于配置 serial bits 除以 line rate。

## 7. Pass criteria

- [ ] 三档 rate set 均为 target=current、DONE、error=0。
- [ ] GT/MMCM lock、TXRESETDONE、gt_ready 正常。
- [ ] V2 loader/CRC/atomicity 全部通过。
- [ ] sequence cases A..E 全部通过。
- [ ] global one-shot EOM 全部通过。
- [ ] reset/abort/clock-unsafe 安全拉低通过。
- [ ] 实际 ILA/UART/UDP 证据已归档。

在真实完成上述上板步骤前：

```text
Hardware test was not run.
board_verified remains 0.
```

# AD9528 OUT0 VCXO 122.88 MHz Candidate Apply 实现报告

## 1. 阶段目标与边界

本阶段在已审核的七项 dry-run transaction 基础上实现三个工程候选命令：

```text
ad9528 candidate set vcxo_122p88
ad9528 candidate status
ad9528 candidate restore
```

这些命令只服务第一套 OUT0 独立 bring-up，不修改 GT、RATE_ID、supported list、
普通 `rate set`、RTL、BD、XDC、CPLL/QPLL/MMCM 或 Bank110 到 Bank111 路径。

## 2. 修改前问题

原软件只有只读 dry-run，不能安全执行已审核配置。若直接逐条写寄存器，将缺少写前
身份检查、当前 old-value 防护、完整字节快照、buffer/post readback、VCXO status
验收和失败回滚，存在覆盖未知运行配置或留下半配置状态的风险。

## 3. Candidate executor 状态机

```text
IDLE
-> PRECHECK
-> SNAPSHOT
-> PROGRAM <-> BUFFER_READBACK
-> IO_UPDATE
-> POST_READBACK
-> READY_UNMEASURED

任一写后错误
-> ROLLBACK
-> ERROR (rollback success recorded)
   或 ERROR/ROLLBACK_FAILED

手动恢复
READY_UNMEASURED -> ROLLBACK -> RESTORED
```

成功状态刻意命名为 `READY_UNMEASURED`，不使用 GT 的 `DONE`，也不使用
`BOARD_VERIFIED/MEASURED/SUPPORTED`。

## 4. 写前检查

在任何配置写入前重新读取：

- identity `0x0003/0x0006/0x000C = 0x05/0x03/0x56`；
- serial port `0x0000 & 0x18 == 0x18`；
- OUT0 LDO `0x0503 & 1 == 1`；
- OUT0 channel `0x0501 & 1 == 0`；
- chip/clock distribution `0x0500 & 3 == 0`；
- 七项 masked old value。

precheck 或 initial old mismatch 发生在首个写入前，因此直接拒绝且不执行无意义的
rollback；一旦进入配置写阶段，即使 SPI write 返回失败也按“可能已写入”处理并尝试
完整 rollback。

## 5. 七项实际写入逻辑

| 顺序 | 地址 | Mask | Value | Expected masked old |
|---:|---:|---:|---:|---:|
| 0 | `0x0108` | `0x05` | `0x01` | `0x00` |
| 1 | `0x0109` | `0x38` | `0x38` | `0x00` |
| 2 | `0x0300` | `0xE0` | `0x20` | `0x00` |
| 3 | `0x0301` | `0xC0` | `0x00` | `0x00` |
| 4 | `0x0302` | `0xFF` | `0x00` | `0x04` |
| 5 | `0x0501` | `0x01` | `0x00` | `0x00` |
| 6 | `0x0500` | `0x0C` | `0x0C` | `0x00` |

每项在写入前重新读取 current，并执行：

```text
new = (current & ~mask) | (value & mask)
```

随后立即读回并比较 masked value。不会用固定完整字节覆盖 mask 外字段。

## 6. 快照与 IO_UPDATE

只有七个完整寄存器和 `0x0508/0x0509` 全部读取成功后才置
`snapshot_valid=1`。同时保存此前 candidate state 和
`configured_out0_hz`。

七项 buffer readback 全部通过后，仅向 `0x000F` 写一次 `0x01`，并等待 10 ms。
该 IO_UPDATE 不计入 `config_writes=7`，单独记录 `io_update_writes=1`。不执行
SYNC、RESET、SYSREF_REQ 或 PLL calibration。

## 7. Postcondition

IO_UPDATE 后重新检查七项 masked readback、OUT0 LDO、channel power、global power
和 `0x0508/0x0509`。VCXO valid 使用 ADI register definition 的 `0x0508 bit5`。

本profile有意关闭PLL1和PLL2，所以 lock不作为验收条件：

```text
pll1_lock_required=0
pll2_lock_required=0
```

全部条件满足后仅设置：

```text
state=READY_UNMEASURED
configured_out0_hz=122880000
runtime_active_likely=1
measured_out0_hz=UNKNOWN
board_verified=0
```

## 8. Rollback 与手动 Restore

rollback按快照恢复七个完整原始字节，每项读回完整字节，然后执行一次IO_UPDATE，
等待后再次读回。任一恢复写、读或IO_UPDATE失败均标记 `ROLLBACK_FAILED`，不会把
candidate标成READY。

手动 `restore` 只允许在 `snapshot_valid=1` 且candidate已应用时执行。成功返回
`state=RESTORED`、`snapshot_restored=1`、`readback_ok=1`、
`io_update_writes=1`。

## 9. UDP与错误码

候选状态输出包含 profile、state、configured/measured、VCXO/readback、snapshot、
rollback、失败寄存器和expected/actual。错误包括 identity、precondition、SPI read/write、
buffer/post readback、IO_UPDATE、VCXO status、rollback和no snapshot。

没有增加任意寄存器写命令，也没有将candidate接入普通rate planner。

## 10. 构建结果

Vitis 2022.2 Debug make clean build通过：compiler/link error为0。

```text
text = 170361
data = 3432
bss  = 3201088
total = 3374881
```

PL RTL未修改，因此未运行Vivado synthesis/implementation，未生成bit/LTX。

## 11. 硬件验证状态

```text
Candidate apply hardware test was not run.
OUT0 frequency measurement was not run.
```

代码提交后停止。下一步由用户下载新ELF，依次执行set/status、保存日志、测量频率、
restore，并回归现有GT速率。未取得这些证据前不能声明OUT0为实测122.88 MHz。


# UDP 协议与 Phase A dry-run 速率命令说明

## 当前状态

当前工程已经进入固定 Profile 控制层和 Phase A dry-run rate controller 阶段：

```text
UDP / lwIP 控制层：已具备 PING、READ_STATUS、READ_GT_STATUS、WRITE_CONFIG、SELECT_CONFIG、APPLY、ENABLE、DISABLE、SOFT_RESET 等基础命令；
Phase A rate controller：仅实现 dry-run，不执行 GTX DRP，不执行 MMCM DRP，不改变 TXOUT_DIV，不改变 TXUSRCLK/TXUSRCLK2；
真实 500M <-> 1000M 动态速率切换：仍未实现。
```

因此，本文件中的 `rate set <Mbps>` 只表示 dry-run 请求链路已经打通，不代表硬件真实 line rate 已改变。

## 固定 Profile 控制命令

当前 UDP server 支持以下业务控制命令：

```text
PING
READ_STATUS
READ_GT_STATUS
WRITE_CONFIG
SELECT_CONFIG
APPLY
ENABLE
DISABLE
SOFT_RESET
rate status
rate plan <Mbps>
rate set <Mbps>
```

其中 `WRITE_CONFIG`、`SELECT_CONFIG`、`APPLY`、`ENABLE` 仍用于控制 `laser_tx_core` 的 BRAM/GPIO 配置和发送启动流程，不改变 GTX line rate。

## Phase A dry-run rate 命令

### `rate status`

读取 dry-run rate controller 当前状态。

示例：

```text
rate status
OK RATE_STATUS mode=dry-run current_static_rate=1000 current_rate=1000 target_rate=none rate_state=IDLE dry_run=1 gt_drp_written=0 mmcm_drp_written=0 error_code=0
```

字段含义：

```text
mode=dry-run            当前仅为 dry-run 模式；
current_static_rate     当前 bitstream 的静态基线速率；
current_rate            软件不得在 dry-run 后伪装改变，仍等于静态基线速率；
target_rate             最近一次 dry-run 目标速率，未请求时为 none；
rate_state              dry-run FSM 状态；
dry_run=1               明确标记本阶段不做真实切换；
gt_drp_written=0        未写 GTX DRP；
mmcm_drp_written=0      未写 MMCM DRP；
error_code              dry-run 错误码。
```

### `rate plan <Mbps>`

查询目标速率对应的规划参数。当前只支持：

```text
500
1000
```

示例：

```text
rate plan 500
OK RATE_PLAN target_rate=500 TXOUT_DIV=8 TXOUTCLK=15625000Hz TXUSRCLK=15625000Hz TXUSRCLK2=7812500Hz requires_gt_drp=1 requires_mmcm_drp=1 executed=0 dry_run_only=1

rate plan 1000
OK RATE_PLAN target_rate=1000 TXOUT_DIV=4 TXOUTCLK=31250000Hz TXUSRCLK=31250000Hz TXUSRCLK2=15625000Hz requires_gt_drp=1 requires_mmcm_drp=1 executed=0 dry_run_only=1
```

非法目标速率示例：

```text
rate plan 750
ERROR unsupported_rate target=750
```

### `rate set <Mbps>`

Phase A 中 `rate set` 只执行 dry-run：

```text
1. 解析目标速率；
2. 检查目标速率是否在 500M/1000M 参数表中；
3. 检查发送侧是否可 quiesce；
4. 检查当前静态 GT ready/status；
5. 触发 AXI/FCLK 域 dry-run request toggle；
6. 不写 GTX DRP；
7. 不写 MMCM DRP；
8. 不改变真实 line rate。
```

示例：

```text
rate set 500
OK RATE_SET_DRY_RUN target=500 actual_rate_unchanged=1 current_rate=1000 gt_drp_written=0 mmcm_drp_written=0

rate set 1000
OK RATE_SET_DRY_RUN target=1000 actual_rate_unchanged=1 current_rate=1000 gt_drp_written=0 mmcm_drp_written=0
```

非法目标速率示例：

```text
rate set 750
ERROR unsupported_rate target=750
```

注意：`current_rate` 示例中的 `1000` 表示当前 ELF 编译时的静态基线速率。若用于 500M Profile0 bitstream，应以编译宏或工程配置将 `LASER_STATIC_RATE_MBPS` 设为 `500`，避免串口/UDP 状态误报。

## 500M / 1000M 参数摘要

| 参数 | 500M static | 1000M static |
| --- | ---: | ---: |
| TX line rate | 500 Mb/s | 1000 Mb/s |
| TXDATA width | 64 bit | 64 bit |
| encoding | None | None |
| internal datawidth | 32 | 32 |
| TXOUT_DIV | 8 | 4 |
| TXOUTCLK | 15.625 MHz | 31.25 MHz |
| TXUSRCLK | 15.625 MHz | 31.25 MHz |
| TXUSRCLK2 | 7.8125 MHz | 15.625 MHz |
| requires_gt_drp | 1 | 1 |
| requires_mmcm_drp | 1 | 1 |
| Phase A executed | 0 | 0 |

## 明确禁止误解

不能把 Phase A dry-run 写成：

```text
真实 rate set 500/1000 已完成；
GTX DRP 已完成；
MMCM DRP 已完成；
TXOUT_DIV 已在运行时改变；
TXUSRCLK/TXUSRCLK2 已在运行时改变；
外部光口动态切换已经验证通过。
```

可以写成：

```text
Phase A dry-run rate controller 已实现；
500M/1000M 参数表与 UDP rate status/plan/set dry-run 命令已接入；
rate set 500/1000 仅触发 dry-run 状态机，不改变真实速率；
GTX/MMCM DRP 和真实动态切换仍属于后续阶段。
```

## AD9528 OUT0 软件频率回读

> 本文前部保留早期 Phase A dry-run 描述用于追溯；当前 rate planner/profile 状态以最新 integration report 和实际 `rate list/status` 为准。本节命令不修改普通 rate 命令。

新增纯只读命令：

```text
ad9528 measure status
```

有效 snapshot 示例格式：

```text
OK AD9528_MEASURE state=VALID_IN_RANGE valid=1 in_range=1 alive=1 sequence=<n> odiv2_count=61437 measured_odiv2_hz=61437000 measured_out0_hz=122874000 window_us=1000
```

无有效完整窗口时不返回旧缓存值：

```text
OK AD9528_MEASURE state=NOT_VALID valid=0 in_range=<0|1> alive=<0|1> sequence=<n> odiv2_count=UNKNOWN measured_odiv2_hz=UNKNOWN measured_out0_hz=UNKNOWN window_us=1000
```

读取采用 `status_before -> count -> status_after`，sequence 跨窗口变化时最多重试 4 次。format/version 不匹配或读取无法收敛时返回 `ERROR AD9528_MEASURE`。

以下 candidate 命令的原有字段和 apply/restore 语义保持不变，并追加 measurement 字段：

```text
ad9528 candidate set vcxo_122p88
ad9528 candidate status
ad9528 candidate restore
```

candidate set/restore 成功后，软件等待新的 measurement sequence，避免把切换前 snapshot 当成当前频率。`in_range=0` 只表示该完整窗口不在 60000～62900 的 ODIV2 count 候选范围，不等同于 AD9528 SPI/apply 失败。本接口不修改 AD9528、GT 或 supported rate list，且不会自动把 candidate 标记为 `board_verified`。

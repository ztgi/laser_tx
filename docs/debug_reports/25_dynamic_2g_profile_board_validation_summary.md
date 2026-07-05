# 2.000G dynamic profile 上板验证总结

## 1. 总结范围

本报告收口 2.000G dynamic profile 的初步上板验证结果。当前系统已经在 125MHz REFCLK、CPLL、固定 profile table 架构下支持：

```text
rate set 500
rate set 1000
rate set 2000
```

本报告只总结 500M/1000M/2000M 三档固化 profile 的动态切换结果，不声明宽范围动态调速、任意连续速率、AD9528 动态输出、156.25MHz refclk、QPLL 或外部光口闭环已完成。

## 2. 当前已完成内容

当前阶段已经完成：

1. 500M/1000M/2000M 三档 dynamic profile 集成；
2. dynamic bit/LTX 生成；
3. Vitis/UDP 支持 `rate set 2000`；
4. 2G dynamic profile 初步上板验证；
5. UDP 侧 500M、1000M、2000M 多次切换均返回 DONE；
6. ILA 捕获 1000M -> 2000M 切换过程、GT/MMCM DRP 细节、TX 域 `txdata/valid_mask` 活动。

## 3. 关键证据

### 3.1 UDP 三档循环成功

![UDP 三档循环成功](../images/dynamic_rate/dynamic_2g_profile/udp_dynamic_500_1000_2000_loop_pass.png)

该图证明 `rate set 500`、`rate set 1000`、`rate set 2000` 均返回 OK，`current_rate` 与目标一致，`state=DONE`，`gt_drp_written=1`，`mmcm_drp_written=1`。

### 3.2 1000M -> 2000M 切换过程

![1000M 到 2000M 切换过程](../images/dynamic_rate/dynamic_2g_profile/ila_dynamic_1000_to_2000_switch_in_progress_overview.png)

该图证明 `target_rate_mbps` 已更新为 2000，状态机进入动态切换流程，GT/MMCM DRP、reset、lock、ready 链路有动作。图中 `current_rate_mbps` 仍为 1000、`txusrclk2_freq_counter_axi` 仍约为 15625，是切换尚未完成时的中间状态，不代表失败。

### 3.3 2G GT/MMCM DRP 细节

![2G GT/MMCM DRP 细节](../images/dynamic_rate/dynamic_2g_profile/ila_dynamic_2g_gt_mmcm_drp_detail.png)

该图证明 GT DRP 与 MMCM DRP 写入过程实际发生。GT DRP addr=0x088，写入/readback 从 1000M 对应值切换到 2G 对应值；MMCM DRP addr/di/do/en/we/rdy 连续动作，DRP done 置位，`error_code=0`。

### 3.4 2G TX 域发送活动

![2G TX 域发送活动](../images/dynamic_rate/dynamic_2g_profile/ila_dynamic_2g_txdata_validmask_activity.png)

该图证明 2G dynamic 切换后，TXUSRCLK2 域捕获到 `engine_start`、`busy`、`txdata[63:0]`、`valid_mask[63:0]` 活动，说明 `laser_tx_core` 发送链路能够启动。

### 3.5 2G 配置命令返回 OK

![2G 配置命令返回 OK](../images/dynamic_rate/dynamic_2g_profile/udp_dynamic_2g_config_apply_enable_ok.png)

该图证明 `WRITE_CONFIG`、`SELECT_CONFIG`、`APPLY`、`ENABLE` 等 UDP 配置命令均返回 OK，PS/UDP 到 PL 配置链路正常。

## 4. 关于过程图中 freq_counter=15625 的解释

在 1000M -> 2000M 的 ILA 过程图中，`target_rate_mbps` 已经变为 2000，但 `current_rate_mbps` 仍为 1000，同时 `txusrclk2_freq_counter_axi` 仍显示约 15625。该现象不是异常，而是动态切换过程中的正常中间状态。

原因是：

1. `target_rate` 表示“请求目标”，收到 `rate set 2000` 后会先更新；
2. `current_rate` 表示“已验证通过的当前速率”，只有切换流程完成并通过 `VERIFY_RATE` 后才更新；
3. `txusrclk2_freq_counter_axi` 是统计窗口计数值，不会在 `target_rate` 改变的瞬间立即跳变；
4. 因此在切换执行过程中看到 `target_rate=2000`、`current_rate=1000`、`freq_counter≈15625` 是合理的；
5. 最终成功应以 `rate set 2000` 返回 `current_rate=2000`、`state=DONE`、`error_code=NONE`、`gt_ready=1` 为准。

## 5. VERIFY_RATE 与 current_rate 更新条件

当前 rate controller 中 `current_rate` 不是收到命令后立即更新，而是在 `VERIFY_RATE` 成功后才更新。`VERIFY_RATE` 用于确认：

- GT DRP 完成且无错误；
- MMCM DRP 完成且无错误；
- MMCM locked raw/sync 已恢复；
- GT resetdone / gt_ready 已恢复；
- `txusrclk2_alive_axi` 有效；
- `txusrclk2_freq_counter_axi` 落入当前 profile 的预期窗口；
- 没有 timeout / error_code。

因此，当 UDP 返回：

```text
current_rate=2000
state=DONE
error_code=NONE
gt_ready=1
```

可以说明 2G profile 已通过 PL rate controller 的内部验收。这里的 `current_rate=2000` 不是单纯的软件打印，而是 PL rate controller 完成 `VERIFY_RATE` 后的结果。

## 6. 验证结果表

| 验证项 | 结果 | 证据 |
|---|---|---|
| `rate set 500` | PASS | UDP 返回 `current_rate=500 state=DONE` |
| `rate set 1000` | PASS | UDP 返回 `current_rate=1000 state=DONE` |
| `rate set 2000` | PASS | UDP 返回 `current_rate=2000 state=DONE` |
| 500/1000/2000 循环 | PASS | UDP 循环图 |
| 1000 -> 2000 状态机过程 | PASS | ILA process overview |
| 2G GT/MMCM DRP 写入 | PASS | ILA DRP detail |
| 2G TX 发送活动 | PASS | TX 域 ILA `txdata/valid_mask` |
| 外部光口/误码率 | NOT TESTED | 本轮未测 |
| 长期稳定性 | NOT TESTED | 本轮未测 |
| 156.25MHz/AD9528/QPLL | NOT INVOLVED | 本轮未涉及 |

## 7. 最终结论

2G dynamic profile 已完成初步上板验证。UDP 日志显示 500M、1000M、2000M 三档 `rate set` 均可返回 DONE，`current_rate` 与目标速率一致，`error_code=NONE`。ILA 进一步显示 1000M -> 2000M 切换过程中 GT/MMCM DRP、reset/lock/ready 链路正常动作；DRP 细节图显示 2G 对应的 GT TXOUT_DIV 和 MMCM DRP sequence 被实际写入；TXUSRCLK2 域 ILA 捕获到 `engine_start`、`busy`、`txdata` 和 `valid_mask` 活动，说明 2G 动态切换后发送链路能够启动。

当前结论限定为：

```text
500M/1000M/2000M 三档固化 profile 的初步动态切换验证通过。
```

## 8. 边界声明

不要将本阶段结论扩大为：

- 宽范围动态调速完成；
- 任意连续速率支持；
- 156.25MHz refclk 支持；
- AD9528 动态输出支持；
- QPLL profile 支持；
- 外部光口闭环通过；
- 误码率验证通过；
- 长期稳定性验证完成。

后续如要继续推进，应在当前三档 profile 证据冻结后，再进入更多 static profile、profile table 扩展、失败回退和更高等级链路质量验证。


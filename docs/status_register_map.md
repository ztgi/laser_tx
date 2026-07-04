# 状态寄存器位图

## 原 laser GPIO 状态（保持不变）

| 位 | 含义 |
|---|---|
| 0 | cfg_valid |
| 1 | cfg_error |
| 2 | pattern_valid |
| 3 | busy |
| 4 | done |
| 5 | phase_active |
| 6 | sequence_active |
| 7 | 保留 |
| 15:8 | phase_offset |
| 23:16 | current_state |
| 31:24 | error_code |

## 新 GT 状态 GPIO（独立 AXI GPIO）

地址由 BD 指定为 `0x40020000`，软件必须最终以新 BSP 的宏为准。

| 位 | 含义 |
|---|---|
| 0 | CPLL lock（同步到控制域） |
| 1 | TX reset done（同步） |
| 2 | gt_ready |
| 3 | GT 尚未 ready |
| 4 | GT 控制复位有效 |
| 7:5 | 当前编译期 profile ID |
| 31:8 | `valid_mask != 0` 的有效发送 word 计数 |

`GET_STATUS` 应同时回传两个 raw status。位图已实现于 RTL/BD，但尚未通过最终 XSA/BSP、综合实现或硬件验证。

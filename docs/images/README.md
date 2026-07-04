# docs/images 图片目录说明

本目录保存 laser_tx 工程报告中使用的真实截图和仿真截图。整理原则：

```text
1. 不删除图片；
2. 不压缩图片；
3. 不修改图片内容；
4. 按验证阶段和主题分目录保存；
5. 第一阶段静态 ILA 图与 500M -> 1000M 动态切换失败图分开保存。
```

## 目录用途

| 子目录 | 用途 |
| --- | --- |
| `phase1_static_ila/500m_profile0/` | 固定 500M Profile0 有效发送 case 的 Vivado GUI / ILA 截图，例如 APPLY、ENABLE、`txdata`、`valid_mask` 观察。 |
| `phase1_static_ila/1000m_static/` | 1000M Profile1 static 阶段的 AXI/FCLK bring-up ILA 截图和对应 UDP 配置截图，用于证明 static 1000M 下 GT/MMCM/txusrclk2 alive、APPLY/ENABLE 控制链路。 |
| `simulation/tb_laser_tx_core/` | `tb_laser_tx_core.sv` 相关仿真截图，包括修复前失败现象与修复后 busy/valid_mask/txdata 正常输出。 |
| `dynamic_rate/500_to_1000_mmcm_lock_timeout/` | 500M -> 1000M 动态切换失败分析截图，重点是 ILA 中 MMCM DRP / reset / lock timeout 相关波形。 |
| `dynamic_rate/udp_status/` | 动态切换调试时 PC/UDP 工具状态截图，例如 `rate status` / `READ_GT_STATUS` 返回。 |
| `vivado_project/source_management/` | Vivado 工程源管理、compile order、source set 等问题截图。当前可为空，后续按需归档。 |
| `vivado_project/build_warnings/` | Vivado build warning / critical warning 截图。当前可为空，后续按需归档。 |
| `archive_old/` | 旧图片或暂不归类图片归档区。当前可为空；仅用于移动保留，不作为主报告证据入口。 |

## 证据优先级

正式报告中的图片证据优先级如下：

```text
真实 Vivado Hardware Manager / ILA GUI 截图
> 原始 log / timing report / debug core report
> 原始 ILA CSV
> 早期辅助可视化图
```

当前目录不再新增“CSV 重绘 PNG”作为主证据。


# AD9528 OUT0 实际频率测量路径报告

## 1. 修改摘要

新增隔离 Vivado 可实现性脚本 `scripts/verify_ad9528_out0_odiv2_measurement_path.tcl`。它在内存工程中验证：

```text
AA8/AA7 (Bank110 MGTREFCLK0)
-> IBUFDS_GTE2.ODIV2
-> BUFG
-> 保持的自由运行计数器
```

该脚本不打开或保存主工程，不实例化 Bank110/Bank111 GTX 数据通道，不接入现有 SFP+ GT，也不生成 bitstream。

## 2. 修改前问题

寄存器条件推导不能证明 OUT0 实际正在输出正确频率。锁定信号也不能证明 FPGA_REF0_CLK 的真实频率、输出 enable 状态、板级信号完整性或 OUT0 与寄存器假设一致。

## 3. 修改后结构

隔离 probe 仅把 `IBUFDS_GTE2` 的公开 `ODIV2` 输出送入 BUFG 并保留计数器。`ODIV2` 是专用 MGT 输入 buffer 的分频 fabric-side 输出；设计不将 MGTREFCLK 经普通组合逻辑反向驱动或使用 `CLOCK_DEDICATED_ROUTE FALSE`。

未来实际测量需要在独立测试镜像中加入已知 FCLK 参考窗口、同步计数器和可读观测接口；本阶段没有将这些接口接入主工程或板卡。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- |
| OUT0 频率测量路径 | 无实现性证据 | 隔离 IBUFDS_GTE2/ODIV2/BUFG probe | 不影响主工程 |
| Bank111 SFP GTX | 现有路径 | 未触及 | 功能不变 |
| Bank110 GTX channel | 未使用 | 未实例化 | 不占用通道 |
| bit/LTX | 无 | 未生成 | 未上板 |

## 5. 功能等价性说明

Expected system behavior unchanged。该 Tcl 只创建 in-memory Vivado 工程，所有临时 HDL/XDC/日志写入 `reports/ad9528_runtime/isolated_out0_measurement_path/`。主工程 RTL、BD、XDC、GT wrapper、AD9528 寄存器、Vitis platform 和 UDP rate 命令均未由该 probe 修改。

## 6. 测试与验证

执行：

```text
vivado -mode batch -source scripts/verify_ad9528_out0_odiv2_measurement_path.tcl
```

已获得：

- synthesis 完成；
- `IBUFDS_GTE2`、`BUFG` 与保持计数器在综合网表中存在；
- `place_design completed successfully`；
- `route_design` 前置 DRC：0 errors。

`route_design` 长时间停在 Phase 1 Build RT Design，未产生错误或完成结果；已终止该仅用于探测的孤立 Vivado 进程。因此不能声明完整 routing、clock-network report、timing 或可下载测试 bitstream 通过。

Oscilloscope hardware validation was not run。FPGA_REF0_CLK 实测频率为 UNKNOWN。

## 7. QoR / timing 对比

| Metric | 结果 | 说明 |
| --- | --- | --- |
| synthesis | 完成 | 孤立 probe |
| placement | 完成 | 孤立 probe |
| route precondition DRC | 0 errors | 仅 route 前检查 |
| route_design | 未完成 | Phase 1 长时间无进展后中止 |
| timing summary | 未获得 | 不可宣称通过 |
| 主工程 QoR | 未运行 | 主工程未改 |

Timing/QoR result not confirmed yet; rerun synthesis/implementation is required。

## 8. 风险与后续建议

1. 当前没有可读取的硬件测量计数，也没有示波器结果；`measured_out0_hz=UNKNOWN`。
2. 不允许因为 probe 的 synthesis/placement 完成就假定 OUT0 已存在或为任意频率。
3. 后续应优先取得可用 Vitis/Vivado 批处理环境，并在独立测试设计中引入已知 PS FCLK 计时窗口和只读观测通道；若该路径最终不能 route，不使用宽泛时钟例外绕过。
4. 只有 register-derived 与 measured OUT0 频率一致，且 PLL2 lock/OUT0 enable 均可确认后，才能生成 `reports/ad9528_runtime/ad9528_runtime_image.json` 并重新做 runtime-constrained candidate 枚举。


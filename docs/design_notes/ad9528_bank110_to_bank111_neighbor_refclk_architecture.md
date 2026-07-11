# AD9528 OUT0 经 Bank110 到 Bank111 GTX 相邻 Quad 参考时钟架构确认

## 1. 修改摘要

本阶段新增隔离 Vivado 路由验证脚本 `scripts/verify_bank110_bank111_refclk_routing.tcl` 和本说明文档。脚本仅在内存中创建 XC7Z100-2FFG900 测试工程，并将所有临时 HDL、XDC 与报告写入 `reports/ad9528_gt_refclk_candidates/isolated_route_probe/`；不会打开、保存或修改主工程 `laser_tx.xpr`。

该工作确认 AD9528 OUT0 所在 Bank110 的 MGTREFCLK0 能否通过 7-series 专用相邻 Quad 参考时钟网络供 Bank111 的 SFP+ GTX Quad 使用。它不是 AD9528 输出频率配置、不是主工程集成、不是新增 GT rate profile。

## 2. 修改前问题

原工程已知 AD9528 OUT0 接到 FPGA Bank110 的差分参考时钟管脚，但当前 SFP+ TX 通道位于 Bank111。仅凭“Bank110 与 Bank111 相邻”不能判断方向、逻辑选择端或是否存在专用资源路径；若错误地将 Bank110 当作普通 GTX 数据 Quad 使用，或者硬编码错误的 north/south 选择，会破坏后续设计依据。

当前 active GT wrapper 也没有把相邻 Quad 的 `GTNORTHREFCLK*` / `GTSOUTHREFCLK*` 作为真实参考时钟输入使用：这些端口被绑到常量，QPLL/CPLL 默认使用 Bank111 本地 `GTREFCLK0`。因此不能根据当前主工程推导 OUT0 已被 GTX 使用。

## 3. 修改后结构

隔离设计只包含以下专用参考时钟路径：

```text
AD9528 OUT0 差分网络
  -> AA8/AA7 (Bank110 MGTREFCLK0)
  -> IBUFDS_GTE2
  -> Bank110 到 Bank111 的 north-bound 专用 GT reference-clock 网络
  -> Bank111 GTXE2_COMMON / GTXE2_CHANNEL 的 GTNORTHREFCLK0 逻辑输入
  -> QPLLREFCLKSEL / CPLLREFCLKSEL = 3'b011
```

隔离设计刻意**不实例化 Bank110 GTXE2_CHANNEL**。Bank111 放置一个 `GTXE2_COMMON_X0Y2` 和一个保持复位的 `GTXE2_CHANNEL_X0Y8`，后者仅消费 QPLL 输出以使 Vivado 完整检查 Common-to-Channel 与参考时钟路由；没有功能 TX 数据通道或 package TX/RX 引脚。

| 项目 | 实测位置 / 选择 |
| --- | --- |
| AD9528 OUT0 FPGA 引脚 | `AA8/AA7`，Bank110 MGTREFCLK0 |
| Bank110 Common tile | `GTX_COMMON_X335Y75`，clock region `X1Y1` |
| Bank111 Common tile | `GTX_COMMON_X335Y127`，clock region `X1Y2` |
| 当前 SFP+ Bank111 channel | `GTXE2_CHANNEL_X0Y8`，tile `GTX_CHANNEL_0_X335Y110` |
| 相对方向 | Bank110 位于 Bank111 **下方** |
| 逻辑参考时钟端 | `GTNORTHREFCLK0`（来自下方 Quad、向北到 Bank111） |
| 选择编码 | `CPLLREFCLKSEL/QPLLREFCLKSEL = 3'b011` |

实现时 Vivado 路由器报告将两个逻辑 `GTNORTHREFCLK0` 端交换到物理 `GTNORTHREFCLK1`：这是器件专用 north/south 引脚交换，不是设计错误，后续主工程也必须保留逻辑端口和选择编码，不能硬编码物理交换结果。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| 主工程 GT 参考时钟 | Bank111 本地 125 MHz `GTREFCLK0` | 未修改 | 主工程功能不变 |
| OUT0 到 SFP GTX 路径 | 仅原理图候选，未由实现验证 | 独立实现已验证专用相邻 Quad 路由 | 提供后续架构依据 |
| Bank110 GTX 数据通道 | 不适用 | 未实例化 | 不占用 Bank110 channel |
| CPLL/QPLL 参考选择 | 当前 wrapper 固定本地路径 | 隔离测试使用 `GTNORTHREFCLK0` / `3'b011` | 仅验证，不接入主工程 |
| AD9528 寄存器 | 未改 | 未改 | 未改变时钟输出 |

## 5. 功能等价性说明

Expected system behavior unchanged。隔离 Tcl 不读取或保存 `laser_tx.xpr`，不改 RTL、BD、XDC、Vitis、GT/MMCM DRP、profile table、supported rate list 或任何现有端口。结论仅来自原理图/器件位置与独立 Vivado 路由结果；它证明 FPGA 内部的专用资源可路由，不证明 AD9528 OUT0 当前有时钟、频率正确或锁定。

## 6. 测试与验证

执行：

```text
vivado -mode batch -source scripts/verify_bank110_bank111_refclk_routing.tcl
```

隔离实现完成：

- `route_design completed successfully`；
- `report_route_status`：7 个可路由 net、7 个 fully routed、0 errors；
- `report_drc`：无 GT 参考时钟、UCIO、NSTD 或 REQP 错误；唯一 `ZPS7-1` warning 是内存测试工程未实例化 Zynq PS 的预期提示；
- 隔离时钟约束为 125 MHz 路由探测，WNS = 2.286 ns、TNS = 0。

该 WNS/TNS 只属于没有主工程业务逻辑的 topology probe，不能用于评价主工程 QoR。

## 7. QoR / timing 对比

| Metric | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| 隔离路由状态 | 未验证 | fully routed | 专用路径存在 |
| 隔离 setup WNS | 不适用 | 2.286 ns | 仅 125 MHz route probe |
| 隔离 setup TNS | 不适用 | 0 | 仅 125 MHz route probe |
| 主工程 WNS/TNS | 未重新运行 | 未重新运行 | 主工程未改动 |

Timing/QoR result not confirmed yet; rerun synthesis/implementation is required。该要求仅在未来把路径接入主工程时生效。

## 8. 风险与后续建议

1. 该结论是方向和 FPGA 专用路由能力确认，**不是** AD9528 OUT0 频率、抖动、锁定或板级 SI 验证。
2. 当前 `laser_tx` 中没有可追溯的 OUT0 寄存器镜像；后续必须先读取或确认真实 AD9528 PLL1/PLL2、M1、R1、N2、OUT0 divider、source 和 IO_UPDATE/SYNC 状态。
3. 后续主工程若接入此路径，CPLL 与 QPLL 都应在 Bank111 消费 `GTNORTHREFCLK0`，并以 `3'b011` 选择；无需占用 Bank110 GTX 数据通道。
4. 主工程接入属于 GT wrapper/XDC/clocking 改动，必须单独分支、重新实现、做 timing/CDC/ILA 与硬件验证；本阶段不执行。


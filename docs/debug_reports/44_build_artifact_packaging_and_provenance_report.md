# 构建产物整理、溯源与归档报告

## 1. 修改摘要

本阶段建立了两套路径显式、可校验且互不混用的本地构建产物包：

- `current_ad9528_measurement`：当前 AD9528 OUT0 Bank110 频率测量与 PS/UDP 回读版本；
- `rollback_fixed_refclk_baseline`：measurement 接入前的固定参考时钟回退版本。

新增了拒绝自动猜测“最新文件”、拒绝静默覆盖的 Python 打包脚本，以及只以顶层 `system.bd` 为 BD 生成入口的 rollback Vivado 重建脚本。二进制、Vivado/Vitis workspace、报告副本和 ZIP 均保留在本地且由 `.gitignore` 排除；Git 只跟踪脚本、README/manifest、状态索引和本报告。

本阶段未修改 RTL 功能、BD 功能结构、XDC、GT Wizard、CPLL/QPLL/MMCM profile、RATE_ID、supported rate、AD9528 PLL2 寄存器或 UDP 功能行为。

## 2. 网络中断后的恢复点与修改前问题

恢复时分支为 `feature/build-artifact-provenance-packaging`，HEAD 为 `8f38b71`，工作区已有 `.gitignore`、打包脚本、bundle README 模板和 `artifacts/` 未提交内容。按要求保留了这些修改，没有 clone、reset、checkout 覆盖或整体推倒重写。

中断前已完成 current measurement 的 clean managed Vitis build。rollback 第一次 Vivado 尝试在 synthesis 前失败，首个阻塞为 `BUILD_SCRIPT_NESTED_BD_TARGET_ERROR`：旧临时脚本同时把顶层 `system.bd` 和 BD 内部 nested XCI 作为独立 `generate_target` 对象。该错误属于构建脚本对象选择错误，不是 RTL、timing、DRC、routing 或器件实现失败。

另一个实际兼容性问题是：当前 measurement 应用源码在旧 rollback XSA 上会由 `laser_hw.h` 明确报错，因为旧 XSA 不含 AD9528 measurement AXI GPIO。最终没有隐藏该错误，也没有手工补 object；rollback ELF 改用与 rollback 硬件相同的历史源码快照 `12d3b71` 完成 managed build。

## 3. 修改后结构

### 3.1 显式打包流程

`scripts/package_current_build_artifacts.py` 要求调用方逐项提供 bit、LTX、XSA、ELF、timing、DRC、route、debug core、utilization 和 README 路径。脚本执行以下检查：

1. 输入必须存在且非空；
2. bundle、ZIP 或 ZIP 校验文件已存在时立即拒绝覆盖；
3. 逐文件复制并记录原始路径、bundle 路径、大小、时间和 SHA-256；
4. 记录 source/hardware/software commit、dirty 状态和 dirty 文件；
5. 生成 `manifest.json`、ZIP 和独立 `.zip.sha256`。

脚本不搜索时间最新的产物，也不对两个 bundle 复用同一文件后伪造独立来源。

### 3.2 rollback Vivado 构建

`scripts/build_rollback_fixed_refclk_baseline.tcl` 接收显式 baseline root 和全新 report output directory。它只对顶层 `system.bd` 执行 `validate_bd_design` 与 `generate_target all`；BD 内部 XCI 由 Vivado 管理。仅 standalone `gtwizard_0.xci` 独立生成。随后重新运行 `synth_1`、`impl_1 -to_step write_bitstream`、LTX、XSA 及报告生成。

rollback 隔离 worktree 在 Vivado 生成后出现 XPR/BD/XCI metadata dirty；这些是生成副作用，已记录到 manifest，未提交，也未用来改写主工程功能。

### 3.3 Vitis managed build

- Measurement：由 measurement XSA 建立空 workspace、platform、standalone/lwIP domain、BSP 和 application；`laser_ad9528_measure.c` 出现在 managed `C_SRCS/OBJS`，`USER_OBJS` 为空。
- Rollback：由 rollback XSA 建立/使用对应 platform 和 `bringup_baseline` application，源码来自 `12d3b71`；managed makefile clean/build 通过，`USER_OBJS` 为空。该应用不包含 `laser_ad9528_measure.c` 或 measurement 命令。

两套应用均未通过手工增加额外 object 完成最终链接。

## 4. 修改前后差异表

| 项目 | 修改前 | 修改后 | 影响 |
| --- | --- | --- | --- |
| 产物选择 | 临时路径与人工判断 | 所有路径必须显式传入 | 避免选错“最新”产物 |
| 覆盖策略 | 未形成统一 gate | 目标存在即拒绝 | 避免静默替换已知包 |
| rollback BD 生成 | 顶层 BD 与 nested XCI 重复作为 target | 仅顶层 BD 为生成入口 | 关闭 nested target 脚本错误 |
| measurement ELF | clean managed build 已完成 | 纳入可追溯 bundle | measurement 源正常进入 object list |
| rollback ELF | 尚未闭合 | 历史同源 application + rollback XSA managed build | 与旧硬件接口匹配 |
| 二进制版本控制 | 缺少专用 bundle 排除项 | ELF/ZIP/校验文件及既有 bit/LTX/XSA 均忽略 | 二进制不进入 Git |
| 功能行为 | 当前 measurement 与旧 fixed-refclk baseline | 两者功能均未修改，只做重建和归档 | Expected system/software behavior unchanged |
| pipeline/latency | 未涉及 | 未涉及 | 无变化 |

## 5. 两套 bundle 与校验值

### 5.1 Current measurement

本地目录：`artifacts/builds/current_ad9528_measurement/`

ZIP：`artifacts/builds/current_ad9528_measurement_8f38b71.zip`

| 类型 | 原始路径 | SHA-256 |
| --- | --- | --- |
| bit | `laser_tx.runs/impl_1/laser_tx_board_top.bit` | `9662E677F4922B551F1885C14B978600EA80A30DAD2E3CB97139D80F7960AF72` |
| LTX | `laser_tx.runs/impl_1/laser_tx_board_top.ltx` | `83502C959A01A5EFE79EDF3920A11547EE890C305A706942F123337630C345F0` |
| XSA | `reports/ad9528_out0_software_readback/laser_tx_board_top_ad9528_measure.xsa` | `3AECFA2D0C735623019C20129362D9552E1D5BFCE5D2B82402612055F2D365F8` |
| ELF | `reports/artifact_packaging_vitis_clean_workspace/bringup/Debug/bringup.elf` | `D330B6AC9A8CE69E9EFB2A324A6D007197500554EC0BC46459A0003F53A5DA85` |
| ZIP | `artifacts/builds/current_ad9528_measurement_8f38b71.zip` | `D681AFD13B6DCDE93ABCC204C0349D0232FA6D590846871D039389A512F31165` |

### 5.2 Rollback fixed-refclk baseline

本地目录：`artifacts/builds/rollback_fixed_refclk_baseline/`

ZIP：`artifacts/builds/rollback_fixed_refclk_baseline_12d3b71.zip`

| 类型 | 原始路径 | SHA-256 |
| --- | --- | --- |
| bit | `reports/rollback_fixed_refclk_source_12d3b71/laser_tx.runs/impl_1/laser_tx_board_top.bit` | `74243B9241E71A43DCA2174F5F0DDAFA3E677238BAACCB61E4D066EC178B5267` |
| LTX | `reports/rollback_fixed_refclk_source_12d3b71/laser_tx.runs/impl_1/laser_tx_board_top.ltx` | `7EF40409EA0EECAE8F9C7BE86E3BC1B3778465F581AC9E5EFCA5EEC88610011E` |
| XSA | `reports/rollback_fixed_refclk_baseline_rebuild/laser_tx_board_top_fixed_125m_baseline.xsa` | `72623D1C82150C23299307ECD5F7AF5F0E0F5DC1C9828099C40D1C49074053EA` |
| ELF | `reports/rollback_fixed_refclk_vitis_clean_workspace/bringup_baseline/Debug/bringup_baseline.elf` | `43BC1992A6A9434ECD51DAC3EA663169CB4403C07BD96B2C875E0E20EC643B78` |
| ZIP | `artifacts/builds/rollback_fixed_refclk_baseline_12d3b71.zip` | `FE0990161ABA065BDCF0B100C0798D48CDEC94F63615B9FC39600D0961345147` |

逐项重算 bundle 哈希和 ZIP 内容检查均无失败。两套 bit、LTX、XSA、ELF 的 SHA-256 均不同，不是同一文件的重复包装。

## 6. 同源与对应证明

- Measurement bit/LTX 均来自当前 `impl_1`；measurement XSA 内嵌 bit 的 SHA-256 与该 bit 完全一致。
- Rollback bit/LTX 均来自隔离 `12d3b71` worktree 的同一 `impl_1`；rollback XSA 内嵌 bit 的 SHA-256 与该 bit 完全一致。
- Measurement platform 使用 measurement XSA，managed application 自动编译 measurement 源。
- Rollback platform 使用新生成的 rollback XSA，managed application 使用相同历史快照的软件源。

因此 measurement bit 不得与 rollback LTX/ELF 混用，rollback bit 也不得与 measurement LTX/ELF 混用。

## 7. 构建与测试验证

### 7.1 Vivado

| 项目 | Measurement | Rollback baseline |
| --- | ---: | ---: |
| synth | 已完成 | 已完成 |
| impl/write_bitstream | 已完成 | 已完成 |
| top/run | `laser_tx_board_top` / `impl_1` | `laser_tx_board_top` / `impl_1` |
| Setup WNS | 7.029ns | 7.029ns |
| TNS | 0ns | 0ns |
| Hold WHS | 0.023ns | 0.020ns |
| THS | 0ns | 0ns |
| DRC Error | 0 | 0 |
| Routing Error | 0 | 0 |
| debug hub/ILA | implemented | implemented；debug hub clock 为 `gt_ctrl_clk` |

Rollback 顶层 BD `validate_bd_design` 通过。第一次 nested target 失败没有被当作硬件设计失败；修复脚本后使用全新输出目录完成了正式重建。

### 7.2 Vitis

| 项目 | Measurement | Rollback baseline |
| --- | --- | --- |
| build | clean managed build PASS | managed makefile clean/build PASS |
| processor/domain | `ps7_cortexa9_0` / standalone+lwiP | `ps7_cortexa9_0` / standalone+lwiP |
| USER_OBJS | 空 | 空 |
| ELF text/data/bss | 175871 / 3448 / 3201088 | 151095 / 3432 / 3201088 |
| measurement source | 正常进入 C_SRCS/OBJS | 旧 XSA 无对应硬件，按同历史源码构建且不包含该源 |

Current source + rollback XSA 的尝试按预期在硬件能力检查处失败，这证明软件没有在旧平台上伪造 measurement 能力。最终 rollback ELF 的 platform/XSA 和 application 源语义一致。

## 8. QoR / timing / utilization 对比

| Metric | Measurement | Rollback | 解释 |
| --- | ---: | ---: | --- |
| Setup WNS | 7.029ns | 7.029ns | 两套实现 setup 均满足约束 |
| Setup TNS | 0ns | 0ns | 无 setup 负 slack |
| Hold WHS | 0.023ns | 0.020ns | 两套实现 hold 均满足约束 |
| Hold THS | 0ns | 0ns | 无 hold 负 slack |
| LUT | 24699 | 22843 | measurement 增量包含测量/回读逻辑 |
| FF | 24565 | 21661 | 同上 |
| BRAM tile | 63.5 | 61 | 同上 |
| DSP | 0 | 0 | 无变化 |
| BUFG | 7 | 6 | measurement 增加 OUT0 ODIV2 测量时钟 |
| MMCM | 1 | 1 | 无变化 |
| GTXE2_COMMON / CHANNEL | 1 / 1 | 1 / 1 | GT 主结构保持 |

Timing 通过只证明两套实现满足当前已约束时序，不等价于外部光口质量、BER、眼图或长期稳定性验证。

## 9. 接口、时钟复位、AXI 与功能等价性

本任务没有修改硬件或软件功能源码，因此没有新增/删除/重命名顶层端口，没有改变 MIO/EMIO、SPI chip-select、AXI address map、GPIO bitfield、clock/reset topology、状态机、pipeline latency 或 supported rate。

```text
Clock/reset behavior unchanged
AXI address map unchanged
Expected system behavior unchanged
Expected software behavior unchanged
XSA / Platform / BSP dependency unchanged（对各自 bundle 内部而言）
```

两套 bundle 之间本来就有已知硬件能力差异：measurement XSA 含测量 AXI GPIO，rollback XSA 不含；因此二者 platform/ELF 不可交叉使用。这是既有版本差异，不是本任务新增的接口变化。

## 10. 硬件验证边界

- Measurement：AD9528 OUT0 candidate 已有 FPGA 内部计数和 UDP 软件回读证据，约 122.872～122.874MHz；外部示波器/频率计尚未验证。
- Rollback：历史 `12d3b71` 文档包含固定 125MHz profile 的阶段性上板证据；本次重建后的 bit/LTX/XSA/ELF 尚未重新执行板级冒烟或全档循环。
- 两套产物均不能证明外部光口 BER、眼图或长期稳定性。

## 11. 回退烧写顺序

1. Program `rollback_fixed_refclk_baseline/hardware/laser_tx_fixed_refclk_baseline.bit`；
2. 加载同目录 `laser_tx_fixed_refclk_baseline.ltx`；
3. 执行 `rst -processor`；
4. 下载并运行同 bundle 的 `software/laser_tx_udp_bringup.elf`；
5. 通过 UART/UDP 执行 `PING`、`rate list`、`rate status` 和必要档位冒烟。

不得只替换 bit 而沿用 measurement LTX/ELF。

## 12. 内存与启动风险

Linker script、heap、stack 和 memory region 未修改。两套 `.bss` 均为 3,201,088 bytes；measurement ELF 比 rollback ELF 增加软件功能和代码体积，但 managed link 已通过。仍建议烧写后观察 UART `main`/lwIP 初始化，避免把 platform/ELF 误配造成的启动失败误判为 PL 故障。

## 13. 修改文件列表

| 文件 | 修改内容 |
| --- | --- |
| `.gitignore` | 排除 bundle 内 ELF、ZIP 和 ZIP 校验文件 |
| `scripts/package_current_build_artifacts.py` | 显式路径、拒绝覆盖、SHA-256、manifest/ZIP 生成 |
| `scripts/build_rollback_fixed_refclk_baseline.tcl` | 顶层 BD 单入口的 rollback 可重复重建 |
| `scripts/artifact_bundle_readmes/*.md` | 两套 bundle 用途、烧写顺序和边界模板 |
| `artifacts/builds/*/manifest.json` | 可提交的来源、哈希与构建状态元数据 |
| `artifacts/builds/*/README.md` | 可提交的包内使用说明 |
| `docs/debug_reports/44_build_artifact_packaging_and_provenance_report.md` | 本报告 |
| `docs/debug_reports/00_current_validation_status.md` | 当前产物入口与状态 |
| `docs/debug_reports/README_validation_report_reading_order.md` | 报告阅读入口 |

bit/LTX/XSA/ELF/ZIP、Vivado/Vitis workspace 和生成报告未提交 Git。

## 14. 风险与后续建议

1. 使用 rollback bundle 前应做一次板级 `PING`、`rate list/status` 和代表性 CPLL/QPLL 档位冒烟；
2. current measurement 包仍需外部仪器确认 OUT0；
3. rollback 隔离 worktree 的 XPR/BD/XCI metadata dirty 是生成副作用，不应合并回主工程；
4. 后续若任何功能源码、XSA 或 implementation 改变，必须生成新 bundle 名称/commit 后缀，不得覆盖本包；
5. 本任务没有推进 PLL2 TEST0、AD9528→GTNORTHREFCLK、3000M 或新速率。

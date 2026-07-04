# 从 500M/1000M 双速率切换到宽范围动态速率控制的路线图

> 本文档是后续设计路线图，不修改 RTL、BD、XDC、Vitis、GT Wizard、AD9528、bit/LTX 或现有 build 脚本。  
> 目标是回答：当前已经完成 500M/1000M 双速率动态切换后，如何逐步走向“UDP 控制下的较宽范围动态速率调整”。

## 1. 当前成果的真实意义

当前工程已经完成并验证了 500M/1000M 双速率动态切换基线：

- 500M -> 1000M 动态切换已通过；
- 1000M -> 500M 反向切换已通过；
- 500M <-> 1000M 循环切换在当前测试次数内通过；
- reset sequence 互锁问题已经定位并修复；
- 当前 rate controller 已经具备 GT DRP + MMCM DRP + reset/lock/ready 闭环的基本能力。

这个成果的价值很大。它证明当前系统不是停留在“软件写个状态寄存器”的 dry-run，而是已经跑通了最小真实链路：

```text
UDP command
-> Vitis command parser
-> rate request / status register
-> rate controller
-> GT TXOUT_DIV DRP
-> MMCM DRP
-> reset sequence
-> MMCM lock
-> GT txresetdone / gt_ready
-> current_rate 更新
-> UDP rate status 回读
```

具体来说，500M/1000M 成功证明了：

- UDP 控制链路可用；
- `rate set` / `rate status` 机制可用；
- GT DRP 写 `TXOUT_DIV` 的链路可用；
- MMCM DRP 写入链路可用；
- reset sequence 可以被正确组织；
- `MMCM locked` / `GT ready` 可以恢复；
- `current_rate` 可以在硬件 ready 后更新，而不是提前假装成功。

但 500M/1000M 成功仍然只是“宽范围动态速率控制”的基础，不等于宽范围完成。它还不能证明：

- 任意速率可调；
- 宽范围速率连续可调；
- 新速率参数能够自动生成；
- CPLL/QPLL 切换已经完成；
- 外部 AD9528 动态时钟树已经打通；
- 每个新速率的 `txusrclk2`、MMCM VCO、GT line rate 都合法；
- 光口质量、误码率、眼图或长期稳定性已经验证。

所以当前结论应写成：

```text
500M/1000M 双速率动态切换链路已经跑通；
它证明了动态切换框架可行；
它不等价于宽范围任意速率控制已经完成。
```

## 2. 宽范围动态速率控制要拆成四个层级

“宽范围动态速率控制”不能一口吃成“任意连续速率”。在这个工程里，它应该拆成四个技术层级，每一层解决不同问题。

### Level 1：双速率切换

当前已完成：

```text
500M / 1000M
```

这个层级的核心意义是证明动态切换闭环存在：

```text
UDP 请求
-> 硬件状态机执行 DRP
-> reset/lock/ready 恢复
-> current_rate 更新
-> UDP 状态回读
```

当前的 rate controller、debug probe、UDP 命令、ILA 验证方法，都是后续扩展的基线资产。

### Level 2：有限多档离散速率

Level 2 是功能目标：从当前 500M/1000M 双速率扩展到有限多档离散速率。它回答的是“系统支持几个速率”，而不是“这些速率在 RTL 里如何组织”。

例如：

```text
250M / 500M / 750M / 1000M
```

每档速率都有固定 profile。UDP 不直接传入任意 line rate 后让硬件现场计算，而是选择一个已知 profile：

```text
rate set 250
rate set 500
rate set 750
rate set 1000
```

这一层要解决的问题是：

- 新增 profile 是否能 static build；
- 新增速率的 GT/MMCM 参数是否正确；
- 当前 reset sequence 是否适用于新速率；
- 新速率与 500M/1000M 的切换路径是否稳定。

Level 2 的重点是新增速率是否真的能完成：

```text
static build
-> static bring-up
-> dynamic switch
-> UDP status 回读
-> ILA 证据确认
```

### Level 3：表驱动多速率

Level 3 是实现架构：把多个离散速率组织成 profile table，并抽象出统一的 Rate Switch Executor。它回答的是“这些速率如何被组织、维护和执行”。

Level 2 和 Level 3 不是互斥关系：

```text
Level 2 解决“支持几个速率”；
Level 3 解决“这些速率如何被组织和维护”。
```

可以先用简单 case 做 Level 2，验证第三速率是否可行；也可以先把 500M/1000M 功能等价重构成 Level 3 表驱动结构，再新增第三速率。对当前工程，更推荐后者：先把已经成功的 500M/1000M 整理成 profile table，再扩展第三速率。

需要特别说明：表驱动并不意味着硬件里没有比较器。RTL 综合后，profile table 可能变成比较器、mux、ROM/LUT 或 case 逻辑。问题不在于是否比较 `target_rate`，而在于不能把每个速率的 GT/MMCM DRP 参数、timeout、reset sequence 和状态跳转逻辑分散混写在多个速率专用分支中。

profile table 至少应包含：

- `rate_id`；
- `line_rate`；
- GT `TXOUT_DIV` / CPLL 或 QPLL 参数；
- MMCM DRP 表；
- 预期 `txusrclk2`；
- lock timeout；
- reset sequence 参数；
- 验证状态或 build-time enable 标志。

Level 3 的核心产物不是“表项本身”，而是通用 Rate Switch Executor。它负责执行统一的底层切换流程：

```text
PROGRAM_GT_DRP
PROGRAM_MMCM_DRP
RELEASE_RESET
WAIT_MMCM_LOCK
WAIT_GT_READY
VERIFY_TXUSRCLK2_FREQ
UPDATE_CURRENT_RATE
ERROR / TIMEOUT / ROLLBACK hooks
```

此时 UDP 层看到的是“合法速率列表”，硬件层看到的是“目标 profile_id”。Executor 根据 `profile_id` 读取 profile table，并执行同一套 DRP、reset、lock、ready、verify、update 流程。这样扩展新速率时，新增的是 profile 数据和路径验证，而不是复制一份状态机。

### Level 4：接近连续或宽范围控制

Level 4 是长期目标：接近连续或更宽范围速率控制。它不应被理解为“继续往 Level 3 的 RTL 固定表里加更多 profile”。如果要做到更细粒度、更宽范围，架构一定还会变化。

Level 3 的 profile table 可以是 RTL 固定 ROM 表；Level 4 中 profile 的来源可能升级为：

- 软件生成；
- 离线工具生成；
- BRAM 加载；
- 固化参数库选择；
- 与 AD9528/refclk 配置联动。

Level 4 会新增或强化以下模块：

- Rate Planner；
- Profile Provider；
- Profile Generator；
- Profile Validator；
- CPLL/QPLL 选择；
- AD9528 / 外部时钟规划；
- 合法性检查；
- 失败回退；
- 链路质量验证；
- 误码率、示波器、眼图等验证闭环。

推荐理解是：

> Level 3 的 profile table 不应被理解为最终宽范围架构，而应被理解为 Level 4 的执行接口雏形。Level 4 会改变 profile 的来源、规划和校验方式，但应尽量复用 Level 3 形成的通用切换执行流程。这样后续即使从固定离散速率扩展到更宽范围控制，也不需要重新编写 GT/MMCM DRP、reset release、lock wait、ready wait 和 current_rate 更新这条底层执行链路。

这一层才接近用户直觉里的“宽范围动态调速”。但它涉及较大架构升级，当前不能直接承诺实现。当前工程最现实的下一步仍然是 Level 2 / Level 3：先把有限多档跑稳，再把参数管理从 500M/1000M 特例重构为 profile-driven 执行器。

## 3. 当前架构哪些可以沿用

当前 500M/1000M 成功后，有不少东西可以直接保留，没必要推倒重来。

### 3.1 UDP 命令框架

可以沿用：

- UDP server；
- `PING`；
- `READ_STATUS`；
- `READ_GT_STATUS`；
- `rate plan`；
- `rate set`；
- `rate status`；
- 命令返回字符串中的 `current_rate`、`target_rate`、`rate_state`、`error_code`。

后续需要增强的是命令内容，而不是换掉 UDP 框架。例如新增：

```text
rate list
rate profile <id>
rate path <from> <to>
```

### 3.2 rate request / status 思路

当前已有的状态可继续沿用：

- `target_rate`；
- `current_rate`；
- `rate_state`；
- `rate_error`；
- `rate_error_code`；
- `gt_ready`；
- `gt_drp_done/error`；
- `mmcm_drp_done/error`。

这套机制已经证明能支撑“请求-执行-确认-回读”的闭环。

### 3.3 GT DRP 写入框架

当前 GT DRP 写 `TXOUT_DIV` 的链路可用。后续可以沿用：

- DRP request；
- DRP busy/done/error；
- DRP timeout；
- DRP readback；
- 失败进入 error 而不是假装成功。

需要扩展的是参数来源：从 500/1000 case 分支，迁移到 profile table。

### 3.4 MMCM DRP 写入框架

当前 MMCM DRP 写入链路可用，且 reset sequence 互锁已经修复。可沿用：

- MMCM DRP address/data sequence；
- MMCM DRP busy/done/error；
- MMCM lock timeout；
- MMCM locked raw/sync debug；
- `txoutclk_alive_axi` 与 `txusrclk2_freq_counter_axi` 观察方法。

后续要做的是把不同速率的 MMCM 参数表格化，并明确每档速率的输入频率、VCO 范围和输出频率。

### 3.5 debug-only probe 体系

当前 AXI/FCLK ILA 非常重要，必须保留：

- `dbg_hub/clk = gt_ctrl_clk / clk_fpga_0`；
- AXI/FCLK ILA 作为 primary bring-up/debug 窗口；
- txusrclk2 ILA 作为 GT/MMCM 稳定后的二级观察窗口；
- `txoutclk_alive_axi`；
- `txusrclk2_alive_axi`；
- `txusrclk2_freq_counter_axi`；
- `tx_mmcm_reset_wizard/rate/final`；
- `tx_mmcm_locked_raw/sync`；
- `rate_state/target/current/error_code`。

后续多速率扩展时，debug probe 不应变成功能控制路径，但必须继续作为定位问题的主证据。

### 3.6 reset sequence 修复后的基本流程

当前可沿用的基本流程是：

```text
QUIESCE_TX
-> ASSERT_RESET
-> PROGRAM_GT_DRP
-> PROGRAM_MMCM_DRP
-> RELEASE GT soft reset / release MMCM reset
-> keep TXUSERRDY blocked
-> wait MMCM reset release
-> wait MMCM lock
-> release TXUSERRDY
-> wait txresetdone / gt_ready
-> verify rate
-> update current_rate
```

这条链路是后续 profile 扩展的骨架。

## 4. 当前架构哪些必须重构

500M/1000M 能跑，不代表当前架构适合直接扩展到更多速率。要走向宽范围，必须先做结构性重构。

### 4.1 rate controller 不能把速率参数和状态机流程混写

当前 500M/1000M 的逻辑是工程验证阶段合理的最小实现，但多速率后需要把“速率请求译码”和“切换执行流程”拆开。

rate controller 可以保留请求速率到 `profile_id` 的译码比较。例如，硬件仍然可以比较：

```text
requested_rate == 500
requested_rate == 1000
requested_rate == 750
```

这些比较最终可能综合成比较器、mux、ROM/LUT 或 case 逻辑。问题不在于是否比较 `target_rate`，而在于不能把每个速率的 GT/MMCM DRP 参数、timeout、reset sequence 和状态跳转逻辑分散写在多个速率专用 if/case 分支中。

不推荐的结构是：

```verilog
case (target_rate)
    500: begin
        // 写一套 500M 专用 DRP / reset / timeout / wait lock 流程
    end
    1000: begin
        // 写一套 1000M 专用 DRP / reset / timeout / wait lock 流程
    end
    750: begin
        // 写一套 750M 专用 DRP / reset / timeout / wait lock 流程
    end
endcase
```

这种写法会让状态机混入大量速率专用流程，导致：

- 参数难审查；
- timeout 难统一；
- readback 难管理；
- 错误码难定位；
- 新速率容易误改旧速率。

推荐的结构是：

```text
requested_rate
-> profile_id 译码
-> profile_table 取参数
-> 通用状态机执行：
   PROGRAM_GT_DRP
   PROGRAM_MMCM_DRP
   RELEASE_RESET
   WAIT_LOCK
   VERIFY_RATE
   UPDATE_CURRENT_RATE
```

也就是说，允许存在译码比较；不允许把“某个速率需要写哪些 DRP、等多久、如何 reset、何时更新 current_rate”散落在多个速率专用状态机分支里。

### 4.2 GT/MMCM DRP 参数不能散落在 case 分支中

DRP 参数应该成为 profile 的数据，而不是状态机的控制逻辑。

建议结构：

```text
rate_profile_table
    profile[0] = 500M
    profile[1] = 1000M
    profile[2] = 750M
    ...
```

每个 profile 内部包含：

```text
GT DRP sequence
MMCM DRP sequence
expected txusrclk2 count window
timeout
reset parameters
readback mask/value
```

状态机只做“按表执行”，不关心具体速率的 magic number。

### 4.3 current_rate 只能在 lock/ready 成功后更新

这是当前 500/1000 成功经验里最重要的一条：不能因为 UDP 收到命令就更新 `current_rate`。

必须保持：

```text
DRP done
MMCM locked
txresetdone
gt_ready
txusrclk2 frequency verified
```

全部通过后，才更新 `current_rate`。否则软件会读到“看起来成功”的假状态。

### 4.4 每个 profile 应带有预期 txusrclk2 频率

多速率后不能只看 `gt_ready=1`。

每个 profile 应有：

```text
expected_txusrclk2_hz
expected_counter_min
expected_counter_max
measurement_window_cycles
```

这样 rate controller 或软件才能判断：

```text
GT ready 是真的，但 txusrclk2 是否是目标速率？
```

### 4.5 每个 profile 应带 reset/timeout 参数

不同速率可能需要不同等待预算：

- MMCM lock timeout；
- GT resetdone timeout；
- CPLL lock timeout；
- DRP timeout；
- reset hold cycles；
- txusrclk2 frequency measurement window。

这些参数也应进入 profile table，而不是全局写死。

### 4.6 UDP 应增加 profile 查询能力

为了让上位机/调试人员知道当前 bit 支持哪些速率，UDP 不应只支持盲目 `rate set`。

建议新增：

```text
rate list
rate profile <id>
rate path
rate status verbose
```

示例返回：

```text
OK RATE_LIST count=3 rates=500,750,1000
OK RATE_PROFILE id=2 rate=750 txout_div=... txusrclk2=...
```

### 4.7 错误处理应支持回退到 last_good_rate

宽范围动态控制必须有失败回退设计。

需要明确：

- `last_good_rate`；
- `target_rate`；
- `current_rate`；
- `rollback_state`；
- `rollback_error_code`。

如果切换到新速率失败，应尽量回退到 `last_good_rate`。如果回退也失败，必须报告 `ROLLBACK_FAILED`，不能把 `current_rate` 更新成目标速率。

## 5. 推荐下一阶段不要直接做“任意速率”

不建议下一步直接做“10M~1000M 任意连续调速”，原因不是保守，而是工程上会把多个未知问题绑在一起。

### 5.1 GT 合法 line rate 不是任意数

GT line rate 受这些因素限制：

- 参考时钟频率；
- CPLL/QPLL 选择；
- CPLL/QPLL feedback divider；
- `TXOUT_DIV`；
- 内部数据宽度；
- encoding；
- GT Wizard/GTXE2 支持范围；
- jitter 和 lock 条件。

因此不能把 UDP 输入的任意 Mbps 简单换算成一个 `TXOUT_DIV`。

### 5.2 MMCM 也不是任意可配

MMCM 受：

- 输入频率；
- `DIVCLK_DIVIDE`；
- `CLKFBOUT_MULT`；
- `CLKOUTx_DIVIDE`；
- VCO 范围；
- duty/phase；
- lock/filter 参数；
- DRP 写入顺序。

即使 GT line rate 合法，MMCM 也可能不 lock。

### 5.3 不同速率可能需要不同 reset sequence

500/1000 的 reset sequence 成功，不代表所有速率都完全相同。

例如：

- CPLL 参数变化更大时可能需要更长 reset；
- QPLL/CPLL 切换可能需要完全不同流程；
- MMCM 输入频率变化可能要求不同 lock timeout；
- 某些速率可能需要先切外部 refclk。

### 5.4 没有链路质量验证时，不能只凭 ready 判断质量

`gt_ready=1` 只能说明 GT/时钟/reset 状态恢复，不等于：

- 光口 BER 为 0；
- 眼图质量足够；
- 抖动满足系统要求；
- 外部接收端能稳定恢复数据；
- 长时间循环切换稳定。

### 5.5 直接做宽范围会混淆根因

如果下一步直接做任意速率，一旦失败，可能同时有这些原因：

- GT 参数不合法；
- MMCM 参数不合法；
- reset sequence 不适用；
- UDP 命令解析错误；
- profile table 错误；
- AD9528/refclk 不匹配；
- ILA clock/debug hub 不稳定；
- 光口链路质量不足。

这种失败很难定位。更好的路线是先在有限多档离散速率里把架构打磨成表驱动。

## 6. 推荐实际路线

### Step 0：冻结 500/1000 成功基线

先把当前已经成功的双速率成果固化下来，作为后续回退点。

建议固化：

- 500M->1000M ILA 截图；
- 1000M->500M ILA/UDP 证据；
- 循环切换 UDP log；
- bit/LTX；
- timing report；
- debug core report；
- reset sequence 修复报告；
- 当前 Vitis ELF；
- 当前 UDP 命令版本；
- git tag 或至少归档压缩包。

建议 tag 名：

```text
baseline_dynamic_500m_1000m_pass
```

### Step 1：把 500/1000 改成 profile table

这一阶段不新增速率，只做结构重构。

目标：

```text
功能等价；
仍然只支持 500M/1000M；
但是内部从双速率 if/case 变成 profile table。
```

本阶段 profile table 可以预留 `refclk_id`、`refclk_freq_hz`、`pll_type`、`flags` 等字段，但当前两个 profile 均固定使用现有 125MHz refclk：

```text
profile_500M:
    rate_mbps = 500
    refclk_id = REFCLK_125M
    refclk_freq_hz = 125000000
    ad9528_dynamic_required = 0

profile_1000M:
    rate_mbps = 1000
    refclk_id = REFCLK_125M
    refclk_freq_hz = 125000000
    ad9528_dynamic_required = 0
```

也就是说，Step 1 只整理 profile 参数组织方式，不实现 AD9528 动态输出、不切换 125MHz/156.25MHz refclk、不新增 156.25MHz 相关 profile。AD9528/refclk 切换属于后续 Level 4 或更高复杂度阶段，不能混入本阶段 profile table 功能等价重构。

本阶段还需要明确软件/硬件分工：这里的 profile table 不是由 Vitis 在运行时计算并下发 GT/MMCM DRP 地址和值。当前阶段应保持为 RTL 固化 profile table，Vitis/UDP 只发送目标速率或 `profile_id`，例如 `rate set 500` / `rate set 1000`。PL 内部根据请求译码到已验证 profile，然后由 rate controller 执行统一流程：GT DRP、MMCM DRP、reset release、MMCM lock wait、GT ready wait、txusrclk2 frequency verify 和 current_rate update。Vitis 只负责命令下发和状态回读，不直接写 GT/MMCM DRP addr/data。

Profile 参数来源可以按阶段分层：

- 当前阶段：profile 参数固化在 RTL table/accessor 中，软件只传 rate/profile_id；
- 下一阶段：新增第三速率时仍建议保持 RTL 固化 table，先验证 static profile 和 dynamic path，不引入软件参数下载；
- 长期 Level 4：可以考虑由 PC/Vitis/离线工具生成 profile，再通过 AXI BRAM 或 AXI-Lite 写入 PL，但必须同步增加 profile validator、版本校验、CRC/合法性检查、rollback 和更完整的错误处理。

因此，Step 1 主要修改 Verilog/profile accessor 是合理的：它没有改变 Vitis/UDP 协议、AXI 地址、BD 或 XSA。只有当后续切换到“软件下载 profile 参数”模式时，才需要修改 Vitis、AXI register/BRAM 接口、BD/XSA/BSP，并重新做软硬件联合验证。

验收标准：

- `rate set 500` 行为不变；
- `rate set 1000` 行为不变；
- `rate status` 行为不变或只增加字段；
- current_rate 仍只在 ready 后更新；
- ILA probe 仍可观察 rate_state / target / current / error；
- 500->1000->500 循环仍通过。

这一步的意义是把当前成功经验从“两个特殊分支”变成“可扩展框架”。

### Step 2：新增一个第三速率

第三速率建议先选 250M 或 750M，但选择原则比具体数字更重要。

选择原则：

- 尽量只改 `TXOUT_DIV`；
- 尽量不改 CPLL/QPLL；
- MMCM 参数容易从静态 profile 或官方计算结果确认；
- `txusrclk2` 在合理范围；
- 不需要先动 AD9528；
- static profile 先能独立跑；
- 与 500M/1000M 的切换路径有代表性。

如果 250M 能通过只增大分频实现，它更适合作为低速扩展验证；如果 750M 的参数更接近后续目标应用，也可以选 750M，但必须先确认 GT/MMCM 合法性。

### Step 3：第三速率 static build

不要把新速率直接塞进 dynamic。

先做 static：

- 独立 250M/750M GT/MMCM 配置；
- timing 通过；
- bit/LTX 匹配；
- `txusrclk2_alive`；
- `txusrclk2_freq_counter` 符合预期；
- MMCM lock；
- GT ready；
- APPLY/ENABLE；
- basic `txdata/valid_mask`。

只有 static profile 通过，才允许进入 dynamic profile table。

### Step 4：500M -> 第三速率 dynamic

选择第一条最小动态路径：

```text
500M -> X
```

验证重点：

- GT DRP；
- MMCM DRP；
- reset release；
- `txoutclk_alive_axi`；
- MMCM raw/sync lock；
- `txusrclk2_freq_counter_axi`；
- `txresetdone/gt_ready`；
- `current_rate=X`；
- UDP `rate status`；
- ILA evidence。

### Step 5：第三速率 -> 500M / 1000M

第三速率单向成功后，再验证反向与常用路径：

```text
X -> 500M
X -> 1000M
1000M -> X
```

这样可以判断新 profile 是真正进入多速率网络，还是只对某一条路径偶然有效。

### Step 6：多档循环

最终做 UDP 循环：

```text
500 -> X -> 1000 -> X -> 500
```

循环验证要记录：

- 每次切换目标；
- 每次 `rate_state`；
- 每次 `error_code`；
- `current_rate`；
- `gt_ready`；
- 失败次数；
- 是否出现 ILA upload/debug hub 异常；
- 是否需要 power cycle 才恢复。

## 7. 对“动态范围”的合理定义

建议不要把“宽范围”定义成“任意连续速率”。工程阶段可以这样定义：

### 短期目标

支持 3~4 个离散速率 profile 的 UDP 动态切换。

示例：

```text
250M / 500M / 750M / 1000M
```

短期目标重点是：

- 多 profile 架构；
- profile table；
- 多路径验证；
- 失败回退；
- 状态可观测。

### 中期目标

rate controller 完全表驱动，支持：

- 合法速率列表查询；
- `rate plan`；
- `rate set`；
- `rate status`；
- profile 查询；
- path 查询；
- `last_good_rate`；
- 失败回退；
- readback 校验；
- `txusrclk2` 频率窗口验证。

### 长期目标

结合参数生成工具和外部时钟树，支持更宽范围、更细粒度速率控制。

长期目标可能包括：

- GT/MMCM 参数离线生成；
- CPLL/QPLL profile 自动选择；
- AD9528/refclk 动态配置；
- 速率合法性自动判断；
- BER/眼图/示波器验证；
- 多 profile 长时间循环测试；
- 失败自动回退和诊断日志。

## 8. 需要新增的文档和表格

### 8.1 rate profile 表

| rate_id | rate_mbps | TXOUT_DIV | CPLL/QPLL 参数 | MMCM input | MMCM mult/div | txusrclk2 expected | timeout | 验证状态 |
|---:|---:|---:|---|---|---|---|---|---|
| 0 | 500 | 8 | CPLL fixed / TBD | TXOUTCLK | TBD | 7.8125 MHz | TBD | dynamic pass |
| 1 | 1000 | 4 | CPLL fixed / TBD | TXOUTCLK | TBD | 15.625 MHz | TBD | dynamic pass |
| 2 | TBD | TBD | TBD | TBD | TBD | TBD | TBD | not implemented |

建议额外字段：

- GT DRP write sequence id；
- MMCM DRP sequence id；
- expected frequency counter min/max；
- reset hold cycles；
- lock timeout cycles；
- readback mask/value；
- static bit/LTX path；
- dynamic validation report path。

### 8.2 path 验证表

| from_rate | to_rate | GT DRP | MMCM DRP | MMCM lock | GT ready | UDP status | ILA evidence | 结论 |
|---:|---:|---|---|---|---|---|---|---|
| 500 | 1000 | pass | pass | pass | pass | pass | yes | pass |
| 1000 | 500 | pass | pass | pass | pass | pass | yes | pass |
| 500 | X | TBD | TBD | TBD | TBD | TBD | TBD | not started |
| X | 500 | TBD | TBD | TBD | TBD | TBD | TBD | not started |
| X | 1000 | TBD | TBD | TBD | TBD | TBD | TBD | not started |

### 8.3 error code 表

| error_code | 含义 | 触发条件 | 推荐动作 |
|---|---|---|---|
| `UNSUPPORTED_RATE` | 非法速率 | UDP 请求不在 profile table | 返回错误，不启动切换 |
| `GT_DRP_TIMEOUT` | GT DRP timeout | GT DRP 未返回 ready/done | 停止切换，保持 current_rate |
| `MMCM_DRP_TIMEOUT` | MMCM DRP timeout | MMCM DRP 未返回 ready/done | 停止切换，保持 current_rate |
| `MMCM_LOCK_TIMEOUT` | MMCM lock timeout | DRP 后 MMCM 未 lock | 尝试 rollback |
| `GT_READY_TIMEOUT` | GT ready timeout | MMCM lock 后 GT 未 ready | 尝试 rollback |
| `READBACK_MISMATCH` | DRP readback 不匹配 | readback mask/value 不符合预期 | 停止并报告参数错误 |
| `TXUSRCLK2_FREQ_MISMATCH` | 输出时钟频率不对 | freq counter 不在窗口内 | 不更新 current_rate |
| `ROLLBACK_FAILED` | 回退失败 | 切回 last_good_rate 也失败 | 进入硬错误，要求人工处理 |

## 9. 当前不要做的事

当前不要立刻做：

- 任意 10M~1000M 连续可调；
- 自动计算所有 GT/MMCM 参数；
- 动 AD9528；
- 重构 `laser_tx_core`；
- 引入 FIFO / 任意 pattern 长度；
- 把 debug probe 变成功能路径；
- 未经 static 验证就把新速率加入 dynamic；
- 在没有 BER/示波器/接收端验证前声明“宽范围光口链路已通过”。

这些事情不是永远不能做，而是不应该压在下一步。下一步最需要的是把已经证明可行的 500/1000 框架改造成可扩展结构。

## 10. 最终建议

推荐路线非常明确：

```text
先冻结 500/1000 成功基线；
然后把 rate controller 重构成 profile table；
再新增一个第三速率做 static + dynamic 验证。
```

不要直接冲“宽范围任意速率”。那样会把 GT 参数、MMCM 参数、reset sequence、外部时钟、UDP 软件、ILA debug、链路质量全部混在一起，一旦失败很难定位。

更稳的工程路线是：

```text
500/1000 双速率成功
-> profile table 化
-> 第三速率 static
-> 第三速率 dynamic
-> 多档循环
-> profile/query/rollback 完整化
-> 更宽范围参数生成与外部时钟树
```

这条路线不是保守退缩，而是把已经打通的一条路拓宽成可维护、可验证、可回退的工程道路。对这个项目来说，下一步最合适的实施任务不是“任意速率”，而是：

```text
Phase next:
1. 冻结并归档 500M/1000M pass 基线；
2. 将 500M/1000M rate controller 重构为 profile table；
3. 在不新增速率的情况下验证功能等价；
4. 再选择 250M 或 750M 作为第三速率，先 static 后 dynamic。
```

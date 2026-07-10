# XC7Z100-2 GTX 新增支持速率候选搜索

## 1. 目标与边界

本阶段只建立只读 candidate rate enumerator，针对 `XC7Z100-2` GTX 在
125MHz 与 156.25MHz MGT REFCLK 下枚举 CPLL/QPLL 的可行参数元组。

未修改：

- PL RTL、GT/CPLL/QPLL/MMCM DRP、profile table 或 `RATE_ID`；
- Vitis rate table、UDP supported list、GPIO bitfield 或 AXI 地址；
- GT Wizard 主工程、BD、XDC、ILA、bit/LTX。

脚本 `scripts/enumerate_gtx_rate_candidates.py` 的输出是候选清单，不会
生成 XCI、DRP magic number 或可执行 profile。`LEGAL_CANDIDATE` 只表示
通过本文件列出的器件参数约束；它仍需要 GT Wizard 参数包、MMCM 静态
参数/DRP sequence、synthesis/implementation/timing 与 UDP+ILA 上板验证。

## 2. 公式与约束来源

当前工程为 `TXDATA=64`、内部数据宽度 32、无 8b/10b 编码。现有九档
profile 已证明当前 clocking 关系为：

```text
TXUSRCLK  = line_rate / 32
TXUSRCLK2 = line_rate / 64
```

枚举器不再输出 `TXOUTCLK`。其频率还取决于 `TXOUTCLKSEL` 和 GT Wizard
生成的 user-clock 网络，不能仅由 PLL 分频候选作通用推导。

枚举器使用：

```text
CPLL VCO       = REFCLK × N1 × N2 / M
CPLL line rate = 2 × CPLL VCO / TXOUT_DIV

QPLL VCO       = REFCLK × N / M
QPLL line rate = QPLL VCO / TXOUT_DIV
```

约束来自 UG476 v1.12.1 与 DS191 v1.18.1：

| 项目 | 使用的限制 |
|---|---|
| CPLL divider | `M={1,2}`、`N1={4,5}`、`N2={1..5}`、`D={1,2,4,8}` |
| CPLL VCO | 1.6–3.3GHz |
| XC7Z100-2 CPLL line range | D=1: 3.2–6.6G；D=2: 1.6–3.3G；D=4: 0.8–1.65G；D=8: 0.5–0.825G |
| QPLL divider | `M={1,2,3,4}`、`N={16,20,32,40,64,66,80,100}`、`D={1,2,4,8,16}` |
| QPLL VCO bands | lower 5.93–8.0GHz；upper 9.8–10.3125GHz（`XC7Z100-2`） |
| GTX silicon line-rate coverage | 0.500–8.000Gbps，以及 9.800–10.3125Gbps；严格位于 8.000–9.800Gbps 的速率不可用 |

`0.500–10.3125Gbps` 只表示绝对端点，不能视为连续区间。QPLL upper band
的 10.3125GHz 上限是 `XC7Z100-2` 的上限；严格位于 8.000–9.800Gbps 的
速率会由枚举器标记为 `GTX_LINE_RATE_IN_UNAVAILABLE_8000_TO_9800MBPS_GAP`。
不能把 `-3` speed grade 的 12.5GHz 能力带入本工程。

## 3. 状态定义

| 状态 | 含义 |
|---|---|
| `RATE_VALUE_ALREADY_PRESENT` | line rate 数值已在当前九档正式 profile 中；表中其它 PLL/参数解不代表该替代解已经验证。 |
| `LEGAL_CANDIDATE` | 文档约束下存在合法参数元组，但未进入 supported list。 |
| `BLOCKED` | 该参数元组违反 VCO、divider 分档 line-rate 或当前器件速率限制；CSV 为每一项给出原因。 |

脚本还在 `reason_or_gate` 输出项目门槛。156.25MHz 行会标记
`BOARD_156P25_REFCLK_PATH_UNCONFIRMED`：此前隔离 Wizard 包没有在当前
单参考时钟 XCI 配置中得到可信 156.25MHz 参数包，且主工程没有完成
该 MGTREFCLK/IBUFDS_GTE2/QPLLREFCLKSEL/XDC 路径确认。这不是把一个
硅级合法组合伪称为板级已可用。

## 4. 运行方法与完整输出

```powershell
python scripts/enumerate_gtx_rate_candidates.py `
  --output-dir $env:TEMP\laser_tx_gtx_rate_candidates
```

输出文件：

- `gtx_rate_candidates_legal.csv`：所有通过筛选的参数元组；
- `gtx_rate_candidates_blocked.csv`：所有被拒绝的参数元组及明确原因；
- `gtx_rate_candidates_summary.md`：按 125MHz/156.25MHz × CPLL/QPLL 分组的表。

输出目录必须是临时目录或未追踪报告目录，不能作为正式 profile source
加入工程或 Git。

## 5. 四类候选的去重结果

下表是枚举器按 **line rate** 去重后的关键结果。相同速率可存在多个
合法参数元组；选择哪一个只能在后续独立 profile 任务中由 GT Wizard
生成文件确认，不能在本阶段凭公式选择。

| REFCLK | PLL | line-rate 已被当前正式 profile 覆盖（Mbps） | 未支持但满足硅级筛选的代表速率（Mbps） |
|---:|---|---|---|
| 125MHz | CPLL | 500、1000、1250、2000、2500、3125、5000、6250 | 625、781.25、1562.5、4000 |
| 125MHz | QPLL | 1000、1250、2000、3125、5000、6250、10000 | 625、781.25、1562.5、4000、8000 |
| 156.25MHz | CPLL | 1250、2500、3125、5000、6250 | 585.9375、625、781.25、937.5、976.5625、1171.875、1562.5、1875、1953.125、2343.75、3750、3906.25、4687.5 |
| 156.25MHz | QPLL | 1250、3125、5000、6250、10000 | 625、644.53125、781.25、976.5625、1289.0625、1562.5、1953.125、2578.125、3906.25、5156.25、7812.5、10312.5 |

说明：左列只表示 **line-rate 数值** 已经在另一条、当前已验证的 profile
中出现；不表示该行所示 REFCLK/PLL 参数元组已经被现有 profile 验证。例如
125MHz/QPLL 的 1000Mbps 仅是硅级替代解，当前 1000M 正式 profile 仍使用
CPLL。当前正式 supported 集合仍只有 `500, 1000, 1250, 2000, 2500, 3125,
5000, 6250, 10000 Mbps`；表中任何其它值都不是可执行 `rate set` 目标。
156.25MHz 的行是芯片参数候选，不表示当前板级参考时钟路径可用。

## 6. 3.000G 结论

`3000M / 125MHz CPLL` 继续保持 `BLOCKED`。直接数学候选
`M=1, N1=4, N2=3, D=1` 的 CPLL VCO 仅为 1.5GHz，低于 `XC7Z100-2`
的 1.6GHz CPLL 下限；其它允许 divider 组合不能在 125MHz 下形成一个
满足 CPLL VCO 与 D 分档 line-rate 限制的 3.000Gbps 解。

本阶段没有 GT Wizard/官方新证据推翻该结论，因此不会把 3000M 放进
candidate-to-profile 队列，也不会进入 supported list。

## 7. 推荐的下一档：625Mbps / 125MHz / CPLL

推荐下一独立 profile 任务只评估 **625Mbps**，而非同时增加多档。候选
参数为：

```text
REFCLK = 125MHz
PLL    = CPLL
M/N1/N2 = 1/4/5
TXOUT_DIV = 8
line rate = 625Mbps
TXUSRCLK = 19.53125MHz
TXUSRCLK2 = 9.765625MHz
```

推荐理由：

1. 保持现有 125MHz MGT REFCLK，不涉及 AD9528、156.25MHz refclk 或 QPLL；
2. `M/N1/N2=1/4/5` 已由当前 1250/2500/5000M CPLL profile 使用并完成
   动态切换验证；
3. `TXOUT_DIV=8` 已由 500M 使用并验证其 channel DRP/readback 路径；
4. 仅组合两个已验证 GT 子参数组，新增部分集中在 625M 的 GT Wizard
   参数确认、MMCM DRP 表、frequency window 及一次独立 build/bring-up；
5. `TXUSRCLK2=9.765625MHz` 低于当前所有已验证高速 user-clock 档，
   不会引入更高的 `laser_tx_core` 时序频率压力。

这不是“625M 已安全可加”的结论：必须先生成隔离 GT Wizard 参数包，并
确认该 64-bit/no-encoding 配置的 MMCM user-clock helper、DRP encoding 与
实际 D=8/CPLL group 的 readback；随后才可开始单独的硬件 profile 任务。

## 8. 暂不推荐的方向

| 方向 | 不推荐原因 |
|---|---|
| 3000M / 125MHz CPLL | 已被 CPLL 1.6GHz VCO 下限阻塞。 |
| 781.25M、1562.5M 等分数 Mbps | 当前 UDP 目标速率接口以整数 Mbps 为中心；引入它们会额外涉及协议/显示语义，收益低于 625M。 |
| 4000M / 125MHz CPLL 或 QPLL | 虽为硅级候选，但会引入一组尚未确认的 CPLL/QPLL选择、MMCM参数与 higher-rate bring-up，风险高于625M。 |
| 8000M / 125MHz QPLL | 需要第二个 QPLL profile/COMMON 参数策略，不能复用当前固定 10G QPLL 配置即视为安全。 |
| 所有 156.25MHz 候选 | 当前板级 156.25MHz MGTREFCLK 路径和 GT Wizard 输入配置尚未确认，不能只改 PLL divider。 |
| 10312.5M | 虽处于该 speed grade QPLL 上限，但超过当前 10G/156.25MHz TXUSRCLK2 基线，需要新的时序与时钟架构评估。 |

## 9. 后续新增 profile 的固定流程

任何 `LEGAL_CANDIDATE` 要成为正式 supported rate，仍需依次完成：

```text
GT Wizard/XCI 参数确认
-> generated HDL / user clock helper 提取
-> GT 与 MMCM DRP sequence（可追溯生成，非手写 magic number）
-> RTL/Vitis profile ID 同步
-> synthesis / implementation / timing
-> bit/LTX
-> UDP + ILA 上板验证
-> 标记 board_verified
-> 才能进入正式 rate list
```

本阶段没有执行以上任何 profile 集成步骤。

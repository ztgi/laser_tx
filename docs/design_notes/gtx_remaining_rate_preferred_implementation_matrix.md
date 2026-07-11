# GTX 剩余候选速率：去重与推荐实现矩阵

## 1. 目标与边界

本文件只整理 `XC7Z100-2`、125MHz / 156.25MHz MGT REFCLK、CPLL / QPLL 的硅级合法候选。它不增加 RTL/Vitis profile、RATE_ID、GT/MMCM DRP、UDP 命令、BD/XDC、IBUFDS_GTE2、REFCLKSEL 或 supported list，也不生成 bit/LTX。

所有“推荐”均是后续独立 profile 任务的优先级建议，不是 GT Wizard 已确认、工程已实现或板级已验证的结论。

## 2. 数据源与精确去重方法

数据源是本轮重新运行 `scripts/enumerate_gtx_rate_candidates.py` 得到的完整 `gtx_rate_candidates_legal.csv`。分类器 `scripts/classify_remaining_gtx_rate_candidates.py`：

1. 从当前 `gt_rate_plan.c` 的 `board_verified=1` profile table 提取正式速率；当前集合为 `500, 625, 1000, 1250, 2000, 2500, 3125, 4000, 5000, 6250, 10000 Mbps`。
2. 将 CSV 的 `line_rate_mbps` 解析为 `Fraction`，再转换为精确整数 `line_rate_bps` 作为全局主键；不使用 binary float 或近似小数字符串。
3. 每个 bps 值仅保留一个 preferred implementation；其他合法元组写入该行的 `alternative_implementations` JSON 字段。
4. 按线速率数值整体删除已实现速率；即使同速率在另一 REFCLK/PLL 下仍有合法替代元组，也不回到待新增主列表。

| 统计项 | 精确结果 |
| --- | ---: |
| legal 参数元组总数 | 76 |
| 125MHz CPLL / QPLL 元组 | 19 / 13 |
| 156.25MHz CPLL / QPLL 元组 | 22 / 22 |
| 全局去重后线速率数 | 30 |
| 当前正式 supported 线速率数 | 11 |
| 删除已实现速率后剩余数 | 19 |
| 剩余非整数 Mbps 速率数 | 16 |

精简决策 CSV：`reports/gtx_rate_candidate_classification/gtx_remaining_rates_classified.csv`。

## 3. 156.25MHz 板级与工程状态

| 状态项 | 结论 | 依据 / 说明 |
| --- | --- | --- |
| `board_clock_source_present` | `true` | 板卡原理图已确认 Bank111 同时具有独立的 125MHz 与 156.25MHz MGT 差分参考时钟源。 |
| `project_ibufds_path_integrated` | `false` | 当前主 top 和 active wrapper 只有 `gt_refclk125_p/n` 端口与 `u_refclk125_ibuf`；未见 156.25MHz IBUFDS_GTE2 接入。 |
| `project_refclksel_control_integrated` | `false` | 当前 QPLLREFCLKSEL 为固定 `3'b001`，未见 125/156.25MHz 运行时选择控制。 |
| `wizard_profile_confirmed` | `false`（全部剩余候选） | 本轮没有为任何剩余速率生成/确认隔离 GT Wizard profile。 |
| `board_verified` | `false`（全部剩余候选） | 本轮未进行新 profile 的 bit/LTX 或上板验证。 |

因此，旧报告的“板上 156.25MHz 路径不存在”表述不准确；正确边界是：**板级时钟源存在，但工程接入与 refclk 选择控制尚未集成。**

## 4. 剩余去重速率与 preferred implementation

每行完整字段、所有替代元组、TXUSRCLK/TXUSRCLK2、复杂度和推荐批次均在 CSV 中。本表保留实现决策所需的摘要。

| Mbps | 推荐类别 | 推荐参数 | D | 复用现有 CPLL 组 | 小数协议迁移 | 复杂度 |
| ---: | --- | --- | ---: | --- | --- | --- |
| 585.9375 | 156.25 CPLL | M/N1/N2=1/5/3 | 8 | 否 | 是 | High |
| 644.53125 | 156.25 QPLL | N/M=66/1 | 16 | - | 是 | Very high |
| 781.25 | 125 CPLL | M/N1/N2=1/5/5 | 8 | 是 | 是 | Medium |
| 937.5 | 125 CPLL | M/N1/N2=1/5/3 | 4 | 否 | 是 | Medium |
| 976.5625 | 156.25 CPLL | M/N1/N2=2/5/5 | 4 | 否 | 是 | High |
| 1171.875 | 156.25 CPLL | M/N1/N2=1/5/3 | 4 | 否 | 是 | High |
| 1289.0625 | 156.25 QPLL | N/M=66/1 | 8 | - | 是 | Very high |
| 1562.5 | 125 CPLL | M/N1/N2=1/5/5 | 4 | 是 | 是 | Medium |
| 1875 | 125 CPLL | M/N1/N2=1/5/3 | 2 | 否 | 否 | Medium |
| 1953.125 | 156.25 CPLL | M/N1/N2=2/5/5 | 2 | 否 | 是 | High |
| 2343.75 | 156.25 CPLL | M/N1/N2=1/5/3 | 2 | 否 | 是 | High |
| 2578.125 | 156.25 QPLL | N/M=66/1 | 4 | - | 是 | Very high |
| 3750 | 125 CPLL | M/N1/N2=1/5/3 | 1 | 否 | 否 | Medium |
| 3906.25 | 156.25 CPLL | M/N1/N2=2/5/5 | 1 | 否 | 是 | High |
| 4687.5 | 156.25 CPLL | M/N1/N2=1/5/3 | 1 | 否 | 是 | High |
| 5156.25 | 156.25 QPLL | N/M=66/1 | 2 | - | 是 | Very high |
| 7812.5 | 156.25 QPLL | N/M=100/2 | 1 | - | 是 | Very high |
| 8000 | 125 QPLL | N/M=64/1 | 1 | - | 否 | High |
| 10312.5 | 156.25 QPLL | N/M=66/1 | 1 | - | 是 | Very high |

## 5. 四类推荐统计与完整列表

| 类别 | 数量 | 去重后完整列表（Mbps） | 首要候选 |
| --- | ---: | --- | --- |
| `RECOMMENDED_125M_CPLL` | 5 | 781.25, 937.5, 1562.5, 1875, 3750 | 781.25（复用 CPLL 1/5/5 与 D=8，但先需 bps 协议） |
| `RECOMMENDED_125M_QPLL` | 1 | 8000 | 8000（整数 Mbps，但需新 QPLL profile） |
| `RECOMMENDED_156P25M_CPLL` | 7 | 585.9375, 976.5625, 1171.875, 1953.125, 2343.75, 3906.25, 4687.5 | 585.9375（但必须先接入第二 REFCLK） |
| `RECOMMENDED_156P25M_QPLL` | 6 | 644.53125, 1289.0625, 2578.125, 5156.25, 7812.5, 10312.5 | 644.53125（风险最高类别） |

QPLL 行的 `requires_qpll_drp` 在 CSV 中标记为 `TBD_WIZARD_CONFIRMATION`，而非假定为 true/false；当前任务不生成 QPLL DRP 数据。

## 6. 与旧 Markdown 人工摘要的差异

旧代表值摘要去重后为 21 个；以当时九档 supported 集合删除后为 19 个。完整 legal CSV 得到 30 个全局速率、删除当前 11 档后同样留下 19 个待新增速率。

分类差异在于完整 legal CSV 发现以下速率存在更高优先级的 125MHz CPLL 解：

- 937.5Mbps：125MHz CPLL `1/5/3, D=4`；
- 1875Mbps：125MHz CPLL `1/5/3, D=2`；
- 3750Mbps：125MHz CPLL `1/5/3, D=1`。

因此这三项从人工摘要预期的 156.25MHz CPLL 类移入 125MHz CPLL 类。其余 16 项与代表值并集的剩余候选一致。

## 7. 小数 Mbps 的协议影响

16/19 个剩余候选是非整数 Mbps。当前 UDP/planner 以整数 Mbps 表示目标，不能把 781.25 写成 781，也不能把 10312.5 四舍五入为 10312 或 10313。

后续若要实现这些 profile，应先单独完成接口迁移：用 `uint64_t rate_bps` 作为 profile 唯一线速率字段，并更新 UDP 解析、显示、status、planner、测试和兼容策略。本任务不改变现有协议。

## 8. 推荐实施批次

每个子批最多三个速率；任何子批均须逐档完成 Wizard 参数确认、MMCM DRP 生成、implementation/timing 和 UDP+ILA 上板验证后才能进入 supported list。

| 批次 | 候选（Mbps） | 复用 / 新增 | 前置任务与风险 |
| --- | --- | --- | --- |
| A1：125M CPLL + bps 协议 | 781.25、1562.5 | 复用 CPLL 1/5/5、已有 D=8/D=4 | 先做 `rate_bps` 接口迁移；Medium |
| A2：125M CPLL + bps 协议 | 937.5 | 新 CPLL 1/5/3、已有 D=4 | 同上；Medium |
| B1：125M CPLL 新参数组 | 1875、3750 | 新 CPLL 1/5/3、已有 D=2/D=1 | 无小数协议迁移，但仍需完整参数/DRP/上板；Medium |
| C1：156.25M CPLL | 585.9375、976.5625、1171.875 | 新第二 REFCLK 与 CPLL 组 | 先集成 156.25MHz IBUFDS/REFCLKSEL，再做 bps 协议；High |
| C2/C3：156.25M CPLL | 1953.125、2343.75、3906.25 / 4687.5 | 同类后续批 | 不应与 C1 并行直接加入；High |
| D1：125M QPLL | 8000 | 新 QPLL 静态 profile | 当前唯一整数 125M QPLL 候选；需 QPLL 参数包与双向恢复；High |
| E1/E2：156.25M QPLL | 644.53125、1289.0625、2578.125 / 5156.25、7812.5、10312.5 | 第二 REFCLK + 新 QPLL profile | 最后处理；10312.5 还超过当前 10G user-clock baseline；Very high |

当前最不应直接实现的是所有 156.25MHz / QPLL 候选，以及所有小数候选中尚未先完成 `rate_bps` 接口迁移的项。3000Mbps 仍为 blocked / unsupported，不属于 legal CSV 的待新增列表。

## 9. 后续新增 profile 的固定门槛

```text
合法参数搜索
-> GT Wizard/XCI 逐档确认
-> generated HDL/user clock helper 提取
-> GT/MMCM DRP sequence（可追溯生成）
-> RTL/Vitis profile ID 同步
-> synthesis/implementation/timing
-> UDP + ILA 上板验证
-> board_verified
-> 正式 rate list
```

本阶段只完成该流程之前的候选去重与优先级决策。

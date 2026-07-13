# AD9528 运行时速率规划与 mailbox 实施报告

## 1. 目标与边界

本阶段按冻结架构实现“PS 运行时规划 + 独立 descriptor mailbox”基础设施。现有 legacy `rate_id=0..11`、固定 profile、GT/MMCM 执行链路和 UDP `rate set` 行为未修改；动态路径不占用 `rate_id=12..15`。截至本文当前版本，动态 GT/MMCM executor、AD9528 事务协调器、GTNORTHREFCLK 接入和上板验证尚未完成。

## 2. Stage 1：PS 运行时规划器

离线生成器输出器件合法集合，而不是目标速率 profile。当前生成规模为：AD9528 配置 1319 项、GT tuple 240 项（CPLL 80、QPLL 160）、MMCM recipe 63 项。运行时规划器遍历有限 GT tuple，反推所需参考时钟，并在排序后的 AD9528 表中进行邻近搜索；合法性和误差门限均使用整数/有理数运算。

十进制解析支持整数或最多三位小数的 Mbps。`rate plan` 为只读命令，不写 AD9528、mailbox 或 GT。legacy `rate set` 未改变。

验证结果：Python 表测试、native C planner 测试、ARM `-Werror` 编译和隔离 Vitis managed makefile build 均通过。隔离 build ELF 为 `reports/vitis_managed_build_workspace/bringup/Debug/bringup.elf`，该路径属于本地生成物，不提交仓库。

## 3. Stage 2：descriptor 与 mailbox

descriptor 固定为 version 1、64 个有效 words、最多 16 项 MMCM 写操作。magic 为 `0x31505452`。CRC 使用 CRC-32/ISO-HDLC：反射多项式 `0xEDB88320`、初值和 final xor 均为 `0xFFFFFFFF`；覆盖 word 0..63，排除 CRC word 3，每个 word 按 little-endian 四字节输入。C/Verilog 常量由同一 Python 脚本生成。

PL 在 PREPARE 时顺序复制完整 64-word shadow descriptor，再检查 magic、version、word count、MMCM count 和 CRC。active 副本形成后不再读取 shadow 区。四个 request toggle 始终被采样，忙时事件不会在事务结束后重放。PL status region 的 `0x60..0x63` 由 BRAM Port B 写回。

## 4. BD 结构与地址

当前工程真实旧地址图经 `system.bd` 核对为：

| 外设 | 地址 | 范围 |
|---|---:|---:|
| pattern/config BRAM | `0x40000000` | 8 KiB |
| 主控制/状态 AXI GPIO | `0x41200000` | 64 KiB |
| GT status AXI GPIO | `0x40020000` | 64 KiB |
| AD9528 measurement AXI GPIO | `0x40030000` | 64 KiB |
| dynamic mailbox AXI GPIO | `0x40040000` | 64 KiB |
| dynamic descriptor BRAM | `0x42000000` | 4 KiB |

冻结文档中旧 pattern BRAM 与主 GPIO 的文字对应关系与当前 BD 相反；实施以当前 BD Address Editor 数据为准。新增 AXI GPIO channel 1 为 4-bit PS→PL toggle，channel 2 为 32-bit PL→PS status。新增 Block Memory Generator 为 true dual-port：Port A 连接 AXI BRAM Controller/PS，Port B 连接 board top 中的 mailbox reader。SmartConnect master 数由 4 增至 6。

外部板级端口、MIO/EMIO、SPI chip-select、AXI 旧地址、时钟频率和复位极性均未改变。新增外设继续使用 PS FCLK0/`gt_ctrl_clk`（50 MHz）和 `rst_ps7_0_50M/peripheral_aresetn`。

## 5. 验证状态

| 项目 | 结果 |
|---|---|
| descriptor 生成一致性 | 通过 |
| C CRC golden vector | 通过，`0x3C66E160` |
| RTL simulation | 通过 |
| `validate_bd_design` | 通过；存在 AXI BRAM Controller 未使用第二 controller port 的非功能 warning |
| RTL-only elaboration | mailbox RTL 已成功综合；完整 elaboration 因新增 BD IP OOC stub 尚未生成而停止 |
| synthesis / implementation / timing | 尚未完成 |
| bit/LTX/XSA | 未生成 |
| Vitis 对新 XSA 的 clean build | 尚未执行 |
| Hardware test | 未执行 |

RTL testbench 已覆盖合法 descriptor、错误 magic/version/word count/CRC、MMCM count 超限、提前 REFCLK_READY、忙时重复 PREPARE、ABORT、active/shadow 隔离和 status region sequence 写回。

## 6. 当前边界与后续

当前只建立了规划和 mailbox 传输边界，mailbox event 尚未驱动 GT/MMCM/reset 功能资源。`current_rate`、legacy 状态机、GPIO rate bitfield 和 supported list 均保持原语义。下一阶段必须新增唯一资源 arbiter、动态 executor、previous-plan rollback，并在完整 synthesis/implementation/timing 后才能生成可上板 bit/LTX。

`dynamic_runtime_rate_switch_board_verified=0`

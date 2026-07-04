# AGENTS.md

## 0. Mandatory project policy

Before doing any work, read this `AGENTS.md` and treat it as mandatory project policy.

This file is not a suggestion. It is a required project rule.

If the final response violates this `AGENTS.md`, the task is incomplete.

For every task, first identify the task scope:

* RTL / Verilog / SystemVerilog changes: follow Section 1.
* Vivado Block Design / XDC / wrapper / XSA changes: follow Section 2.
* Vitis / BSP / driver / bare-metal software changes: follow Section 3.

If a task touches multiple scopes, follow all relevant sections.

Do not modify unrelated files.

Do not silently change interfaces, clocks, resets, address maps, pipeline latency, chip-select mapping, or software-visible behavior.

If a conclusion is based only on code or structure inspection, say so clearly.

Do not claim timing, resource, functional, build, or hardware-test success unless the corresponding report or test result proves it.

---

# 1. RTL / Code Change Policy

## 1.1 Scope

This section applies to:

* Verilog / SystemVerilog / VHDL;
* RTL modules;
* testbenches;
* simulation scripts;
* timing-related RTL refactoring;
* pipeline changes;
* FSM changes;
* valid/data path changes;
* CDC-related logic;
* reset or trigger logic.

---

## 1.2 RTL modification rules

For every RTL/code modification, do not only provide a patch.

Every modification must include a structured Chinese engineering change report.

The report must explain:

1. What was changed;
2. Why it was changed;
3. Which original problem it fixes;
4. Whether functionality changed;
5. Whether pipeline latency changed;
6. Which files were modified;
7. Which tests were run;
8. Whether timing/resource/QoR reports improved or need to be rerun;
9. Remaining risks and recommended next steps.

Do not describe changes vaguely as:

* "optimized logic";
* "improved structure";
* "cleaned up code";
* "refactored implementation".

Always identify the concrete RTL/code structure before and after the change.

---

## 1.3 RTL timing-related requirements

For RTL timing-related changes, the report must include:

* Critical path before the change;
* New critical path after the change, if report data is available;
* WNS/TNS/failing endpoints before and after, if report data is available;
* Utilization before and after, if report data is available;
* Whether the improvement comes from:

  * reducing logic depth;
  * reducing fanout;
  * removing serial dependency;
  * adding pipeline;
  * simplifying arithmetic;
  * improving register boundaries;
* Whether any of the following behavior changed:

  * interface timing;
  * valid/data alignment;
  * trigger pulse behavior;
  * reset behavior;
  * state-machine behavior.

If timing/utilization reports are not available, explicitly write:

```text
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

Do not claim timing improvement unless timing reports prove it.

---

## 1.4 Required final response format for RTL/code changes

Every final answer after modifying RTL/code must contain the following sections.

### 1. 修改摘要

Briefly state what files were changed and the main purpose of the change.

### 2. 修改前问题

Explain the original problem.

For RTL, describe the original logic structure, such as:

* serial dependency;
* long combinational path;
* wide mux;
* dynamic modulo/divider;
* high fanout;
* CDC risk;
* state-machine issue;
* reset or enable issue;
* data/valid alignment risk.

### 3. 修改后结构

Explain the new structure.

Do not only say the code was cleaned up or optimized.

Explain the actual architecture or data-path change, for example:

* how state is advanced;
* how addresses are generated;
* how masks/data are generated;
* how registers are placed;
* whether arithmetic was simplified;
* whether pipeline stages were added;
* whether fanout was reduced;
* whether CDC handling changed.

### 4. 修改前后差异表

Provide a table like this:

| 项目            | 修改前 | 修改后 | 影响 |
| ------------- | --- | --- | -- |
| 状态推进方式        |     |     |    |
| 数据路径结构        |     |     |    |
| 组合逻辑深度        |     |     |    |
| 是否新增 pipeline |     |     |    |
| 功能行为          |     |     |    |
| 时序影响          |     |     |    |
| 资源影响          |     |     |    |
| 测试覆盖          |     |     |    |

### 5. 功能等价性说明

State clearly whether the intended behavior is unchanged.

For RTL, explicitly check:

* data/valid alignment;
* start/end behavior;
* reset behavior;
* trigger pulse width;
* state-machine transition;
* loop/non-loop behavior, if applicable;
* gap/invalid/partial-word behavior, if applicable;
* CDC behavior, if applicable;
* external interface behavior.

If any behavior changes, mark it as:

```text
Functional behavior changed intentionally
```

Then explain why the behavior change is intentional.

Do not claim functional equivalence unless simulation, testbench comparison, waveform inspection, or clear code reasoning supports it.

If the conclusion is based only on code inspection, explicitly write that.

### 6. 测试与验证

List all commands/tests run.

If tests were not run, explicitly state:

```text
Tests were not run
```

and explain why.

For RTL, if applicable, include:

* simulation result;
* synthesis result;
* implementation/timing result;
* lint result;
* waveform inspection result;
* self-checking testbench coverage;
* before/after comparison result.

### 7. QoR / timing 对比

If reports are available, provide a before/after table:

| Metric            | Before | After | Interpretation |
| ----------------- | -----: | ----: | -------------- |
| Setup WNS         |        |       |                |
| Setup TNS         |        |       |                |
| Failing endpoints |        |       |                |
| LUT               |        |       |                |
| FF                |        |       |                |
| BRAM              |        |       |                |
| DSP               |        |       |                |
| Worst path        |        |       |                |

If reports are not available, explicitly state:

```text
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

For timing-related RTL changes, always state whether the current clock constraint is final or temporary.

### 8. 风险与后续建议

List any remaining risks, assumptions, and next actions.

For RTL timing-related changes, include:

* whether timing needs to be rerun;
* whether implementation needs to be rerun;
* whether waveform needs to be checked;
* whether testbench needs to be expanded;
* whether interface timing needs additional confirmation;
* whether current clock constraint is final or temporary.

---

# 2. Vivado BD / XDC / Wrapper / XSA Policy

## 2.1 Scope

This section applies to:

* `.bd` file changes;
* Tcl BD script changes;
* IP Integrator connection changes;
* PS configuration changes;
* AXI interconnect or SmartConnect changes;
* clock/reset topology changes;
* external interface creation or deletion;
* address map changes;
* module reference changes;
* IP parameter changes;
* HDL wrapper regeneration;
* output product regeneration;
* XDC changes caused by BD port changes;
* XSA export.

---

## 2.2 BD modification rules

For every Block Design modification, do not only provide a patch, Tcl command, screenshot description, or casual summary.

Every BD modification must include a structured Chinese engineering change report.

The report must explain:

1. What was changed in the BD;
2. Why it was changed;
3. Which original problem it fixes;
4. Whether any external interface changed;
5. Whether any clock/reset topology changed;
6. Whether any AXI address map changed;
7. Whether any IP parameter changed;
8. Whether the HDL wrapper needs to be regenerated;
9. Whether output products need to be regenerated;
10. Whether synthesis/implementation need to be rerun;
11. Which files were modified;
12. Which validation steps were run;
13. Remaining risks and recommended next steps.

Do not describe changes vaguely as:

* "updated BD";
* "fixed connection";
* "optimized block design";
* "refreshed IP";
* "adjusted configuration".

Always identify the concrete BD structure before and after the change.

---

## 2.3 BD modification restrictions

The following restrictions must always be obeyed:

* Do not silently change external ports.
* Do not silently rename BD ports.
* Do not silently delete existing interfaces.
* Do not silently add unused external interfaces.
* Do not silently change PS MIO/EMIO configuration.
* Do not silently change SPI/I2C/UART/GPIO/AXI peripheral configuration.
* Do not silently change clock frequency.
* Do not silently change reset polarity.
* Do not silently change AXI address mapping.
* Do not silently change interrupt connections.
* Do not silently change board-level pin constraints.
* Do not silently regenerate wrapper if the wrapper structure changes.
* Do not modify unrelated IP blocks.
* Do not modify generated vendor IP files unless explicitly requested.
* Do not claim the BD is correct unless validation has been run or the conclusion is clearly marked as code/structure inspection only.

---

## 2.4 Required final response format for BD changes

Every final answer after modifying a Vivado Block Design must contain the following sections.

### 1. 修改摘要

Briefly state:

* Which BD was changed;
* Which IP blocks or connections were changed;
* Which files were modified;
* The main purpose of the change.

### 2. 修改前问题

Explain the original BD problem.

For BD changes, explicitly describe the original structure, such as:

* PS peripheral was not enabled;
* MIO/EMIO selection was wrong;
* SPI chip-select number did not match schematic;
* unused EMIO signal was externalized;
* AXI peripheral was not connected;
* AXI address was not assigned;
* clock domain was unclear;
* reset polarity was inconsistent;
* BD port existed but XDC constraint was missing;
* external port existed but schematic had no corresponding pin;
* IP parameter did not match board hardware;
* HDL wrapper was stale;
* output products were not regenerated.

Do not only write "BD connection was wrong".

### 3. 修改后结构

Explain the new BD structure.

For BD changes, explicitly describe:

* Which IP block was added, removed, or reconfigured;
* Which interface was connected to which block;
* Which signal became external;
* Which signal stayed internal;
* Which clock drives each IP;
* Which reset drives each IP;
* Whether AXI interconnect or SmartConnect changed;
* Whether address assignment changed;
* Whether interrupt connection changed;
* Whether wrapper regeneration is required;
* Whether XDC constraints need to be updated.

### 4. 修改前后差异表

Provide a table like this:

| 项目             | 修改前 | 修改后 | 影响 |
| -------------- | --- | --- | -- |
| BD 文件          |     |     |    |
| 涉及 IP          |     |     |    |
| 外部端口           |     |     |    |
| PS MIO/EMIO 配置 |     |     |    |
| AXI 连接         |     |     |    |
| AXI 地址映射       |     |     |    |
| 时钟连接           |     |     |    |
| 复位连接           |     |     |    |
| 中断连接           |     |     |    |
| HDL wrapper    |     |     |    |
| XDC 约束         |     |     |    |
| 软件/Vitis 影响    |     |     |    |
| 综合/实现影响        |     |     |    |
| 测试覆盖           |     |     |    |

### 5. 接口与板级一致性说明

For every BD change, explicitly check external interface consistency.

Must include:

* Whether any top-level port was added;
* Whether any top-level port was removed;
* Whether any top-level port was renamed;
* Whether port direction changed;
* Whether port width changed;
* Whether externalized signals match the schematic;
* Whether corresponding XDC constraints exist;
* Whether unused external signals are intentionally tied off, left internal, or constrained;
* Whether IO standard and bank voltage are consistent with the schematic.

For SPI-related BD changes, explicitly check:

* SPI instance: SPI0 or SPI1;
* MIO or EMIO mode;
* SCLK connection;
* MOSI connection;
* MISO connection;
* SS/CS number;
* Whether CS0/CS1/CS2 matches actual schematic chip-selects;
* Whether unused CS signals are removed, tied off, or clearly documented;
* Whether software slave-select index matches hardware connection.

For GPIO-related BD changes, explicitly check:

* AXI GPIO or PS GPIO;
* GPIO channel width;
* GPIO direction;
* Whether GPIO is MIO, EMIO, or AXI GPIO;
* Whether external pins match schematic;
* Whether software-visible GPIO mapping changed.

### 6. 时钟与复位说明

For every BD change, explicitly check clock and reset behavior.

Must include:

* Which clock drives each modified IP;
* Whether clock frequency changed;
* Whether clock source changed;
* Whether any new clock domain was introduced;
* Whether reset polarity changed;
* Whether reset source changed;
* Whether reset is synchronous or asynchronous if known;
* Whether `proc_sys_reset` or equivalent reset block was changed;
* Whether CDC risk was introduced.

If clock or reset behavior changed, explicitly mark:

```text
Clock/reset behavior changed intentionally
```

If clock or reset behavior did not change, explicitly write:

```text
Clock/reset behavior unchanged
```

### 7. AXI 地址与软件影响

For every BD change involving AXI, PS peripherals, or memory-mapped IP, explicitly check software impact.

Must include:

* Whether AXI address map changed;
* Whether base address changed;
* Whether address range changed;
* Whether peripheral instance name changed;
* Whether `xparameters.h` may change;
* Whether Vitis platform needs to be regenerated;
* Whether BSP needs to be regenerated;
* Whether existing software driver code needs modification.

If address map changed, explicitly mark:

```text
AXI/software-visible behavior changed intentionally
```

If address map did not change, explicitly write:

```text
AXI address map unchanged
```

### 8. Validate Design / 生成文件 / 综合实现

List all Vivado validation and generation steps that were run.

If applicable, include:

* `validate_bd_design`;
* `save_bd_design`;
* `make_wrapper`;
* wrapper regeneration result;
* output product generation result;
* synthesis result;
* implementation result;
* timing result;
* bitstream generation result;
* exported hardware/XSA result.

If validation was not run, explicitly state:

```text
Validate Design was not run
```

If synthesis/implementation was not run, explicitly state:

```text
Synthesis/implementation was not run
```

If timing/QoR reports are not available, explicitly write:

```text
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

### 9. QoR / timing / utilization 对比

If reports are available, provide a before/after table:

| Metric            | Before | After | Interpretation |
| ----------------- | -----: | ----: | -------------- |
| Setup WNS         |        |       |                |
| Setup TNS         |        |       |                |
| Failing endpoints |        |       |                |
| LUT               |        |       |                |
| FF                |        |       |                |
| BRAM              |        |       |                |
| DSP               |        |       |                |
| BUFG/MMCM/PLL     |        |       |                |
| Worst path        |        |       |                |

If reports are not available, explicitly state:

```text
Timing/QoR result not confirmed yet; rerun synthesis/implementation is required.
```

### 10. 功能等价性说明

State clearly whether intended system behavior is unchanged.

For BD changes, explicitly check:

* external interface behavior;
* PS peripheral behavior;
* AXI access behavior;
* clock/reset behavior;
* interrupt behavior;
* HDL wrapper behavior;
* Vitis/software-visible behavior;
* XDC/board-level behavior.

If behavior is unchanged, write:

```text
Expected system behavior unchanged
```

If any behavior changes, mark it as:

```text
Functional behavior changed intentionally
```

Do not claim functional equivalence unless validation, simulation, hardware test, or clear structural reasoning supports it.

### 11. 修改文件列表

List all modified files.

For Vivado BD changes, possible files include:

* `.bd`;
* `.xci`;
* `.tcl`;
* HDL wrapper;
* `.xdc`;
* project `.xpr`;
* block design generated files;
* XSA/exported hardware files.

### 12. 风险与后续建议

List remaining risks, assumptions, and next actions.

For BD changes, include:

* whether `validate_bd_design` still needs to be run;
* whether output products need regeneration;
* whether HDL wrapper needs regeneration;
* whether synthesis/implementation need rerun;
* whether XDC needs review;
* whether schematic/pinout needs confirmation;
* whether Vitis platform/XSA needs export;
* whether software `xparameters.h` needs update;
* whether board-level hardware test is required.

---

## 2.5 Special BD rules

For SPI BD modifications, always report:

* Which SPI controller is used;
* Whether it is PS SPI or AXI Quad SPI;
* Whether it uses MIO or EMIO;
* Number of slave-select signals configured;
* Which physical devices each CS connects to;
* Whether the schematic actually contains those chip-selects;
* Whether unused CS signals remain internal, are tied off, or are constrained;
* Whether software must avoid selecting unused CS index;
* Whether SPI clock polarity/phase requirements are handled in software or IP configuration;
* Whether IO voltage and IO standard match the target bank.

Do not assign unused SPI chip-select signals to random GPIO pins unless explicitly requested and justified by the schematic.

If a BD exposes more chip-selects than the schematic supports, this must be reported as a risk.

For GPIO BD modifications, always report:

* Whether GPIO is PS GPIO MIO, PS GPIO EMIO, or AXI GPIO;
* GPIO width;
* GPIO direction;
* Whether it is software-controlled or PL-controlled;
* Whether it is connected to external pins or internal logic;
* Whether XDC constraints exist for external GPIO;
* Whether the schematic confirms the selected pins;
* Whether software-visible GPIO numbering changed.

Do not use external GPIO pins as a workaround for unrelated unused signals unless explicitly requested and documented.

---

# 3. Vitis / BSP / Bare-metal Software Policy

## 3.1 Scope

This section applies to:

* `main.c` / `main.cpp`;
* device driver source files;
* board support package related files;
* linker scripts;
* platform configuration;
* `xparameters.h` dependent code;
* SPI/I2C/UART/GPIO/DMA/interrupt initialization code;
* ADI / Xilinx driver integration code;
* peripheral register access code;
* startup/debug/test code;
* build scripts or workspace scripts.

---

## 3.2 Vitis/software modification rules

For every Vitis/software code modification, do not only provide a patch or short summary.

Every software modification must include a structured Chinese engineering change report.

The report must explain:

1. What was changed;
2. Why it was changed;
3. Which original problem it fixes;
4. Whether software behavior changed;
5. Whether hardware interface assumptions changed;
6. Whether Vitis platform / BSP / XSA dependency changed;
7. Which files were modified;
8. Which build or run tests were executed;
9. Whether remaining hardware validation is required;
10. Remaining risks and recommended next steps.

Do not describe changes vaguely as:

* "fixed initialization";
* "cleaned code";
* "improved driver";
* "optimized software";
* "updated Vitis code".

Always identify the concrete software structure before and after the change.

---

## 3.3 Vitis/software modification restrictions

The following restrictions must always be obeyed:

* Do not silently change peripheral instance selection.
* Do not silently change SPI/I2C/UART/GPIO device IDs.
* Do not silently change chip-select index.
* Do not silently change AXI base address.
* Do not silently change register offset definitions.
* Do not silently change interrupt ID or interrupt controller instance.
* Do not silently change clock assumptions.
* Do not silently change delay timing.
* Do not silently change reset or power-up sequence.
* Do not silently remove error checks.
* Do not silently remove existing debug prints.
* Do not silently change linker script memory regions.
* Do not silently increase `.bss`, heap, or stack usage without reporting it.
* Do not modify generated BSP files unless explicitly requested.
* Do not modify unrelated application files.
* Do not claim hardware works unless it was tested on hardware.
* Do not claim software is compatible with the BD unless XSA/platform assumptions were checked.

If a conclusion is based only on code inspection, say so clearly.

---

## 3.4 Required final response format for Vitis/software changes

Every final answer after modifying Vitis/software code must contain the following sections.

### 1. 修改摘要

Briefly state:

* Which software files were changed;
* Which driver or peripheral was affected;
* The main purpose of the change.

### 2. 修改前问题

Explain the original software problem.

For Vitis/software changes, explicitly describe the original structure, such as:

* peripheral device ID selection was ambiguous;
* SPI slave-select did not match hardware;
* initialization sequence was incomplete;
* reset sequence was missing;
* register write/readback was not checked;
* error return value was ignored;
* driver instance was global but not initialized safely;
* startup code did not print because program may fail before `main`;
* `.bss` or heap/stack usage may be too large;
* linker script memory placement may be wrong;
* software still used stale `xparameters.h`;
* BD/XSA was changed but Vitis platform was not regenerated.

Do not only write "software initialization was wrong".

### 3. 修改后结构

Explain the new software structure.

For Vitis/software changes, explicitly describe:

* Which initialization function was added or changed;
* Which peripheral instance is used;
* Which device ID or base address is used;
* Which chip-select or GPIO index is used;
* Which register sequence changed;
* Which error checks were added;
* Which debug prints were added or preserved;
* Whether the code depends on `xparameters.h`;
* Whether the code depends on regenerated XSA/platform/BSP;
* Whether linker script, heap, stack, or memory section placement changed.

### 4. 修改前后差异表

Provide a table like this:

| 项目                       | 修改前 | 修改后 | 影响 |
| ------------------------ | --- | --- | -- |
| 修改文件                     |     |     |    |
| 外设实例                     |     |     |    |
| Device ID / Base Address |     |     |    |
| SPI/I2C/UART/GPIO 配置     |     |     |    |
| 初始化流程                    |     |     |    |
| 错误处理                     |     |     |    |
| 调试输出                     |     |     |    |
| XSA / Platform 依赖        |     |     |    |
| BSP 影响                   |     |     |    |
| Linker Script 影响         |     |     |    |
| 软件行为                     |     |     |    |
| 硬件接口假设                   |     |     |    |
| 测试覆盖                     |     |     |    |

### 5. 硬件接口一致性说明

For every Vitis/software change that touches hardware access, explicitly check hardware consistency.

Must include:

* Whether the software peripheral instance matches the BD;
* Whether the device ID or base address matches `xparameters.h`;
* Whether the selected SPI/I2C/UART/GPIO instance matches the schematic and BD;
* Whether chip-select index matches the actual hardware connection;
* Whether register offsets match the RTL/IP register map;
* Whether AXI address map changed;
* Whether XSA/platform/BSP must be regenerated;
* Whether the software assumes a specific clock frequency;
* Whether the software assumes a specific reset or power-up sequence.

For SPI-related software changes, explicitly check:

* PS SPI or AXI Quad SPI;
* SPI0 or SPI1;
* MIO or EMIO;
* selected slave-select index;
* SCLK/MOSI/MISO/CS hardware mapping;
* whether unused CS indexes must be avoided;
* SPI mode: CPOL/CPHA;
* SPI clock frequency;
* whether manual or automatic slave-select is used;
* whether readback verification is performed.

### 6. 功能等价性说明

State clearly whether intended software behavior is unchanged.

For Vitis/software, explicitly check:

* initialization order;
* peripheral selection;
* register write sequence;
* register readback behavior;
* delay behavior;
* error handling behavior;
* debug output behavior;
* interrupt behavior, if applicable;
* DMA/cache behavior, if applicable;
* loop behavior, if applicable;
* startup behavior before `main`, if applicable;
* hardware-visible behavior.

If behavior is unchanged, write:

```text
Expected software behavior unchanged
```

If any behavior changes, mark it as:

```text
Functional behavior changed intentionally
```

Do not claim functional equivalence unless build test, runtime test, hardware test, or clear code reasoning supports it.

If the conclusion is based only on code inspection, explicitly write that.

### 7. 构建与测试验证

List all build or test commands that were run.

If applicable, include:

* Vitis build result;
* compiler warnings;
* linker result;
* ELF size result;
* serial console output;
* hardware run result;
* register readback result;
* peripheral communication result;
* SPI/I2C/UART/GPIO transaction result;
* interrupt test result;
* DMA/cache coherency test result.

If build was not run, explicitly state:

```text
Build was not run
```

If hardware test was not run, explicitly state:

```text
Hardware test was not run
```

Do not claim hardware success without board-level test evidence.

### 8. XSA / Platform / BSP 影响

For every Vitis/software change, explicitly check whether hardware platform dependencies changed.

Must include:

* Whether XSA changed;
* Whether Vitis platform must be regenerated;
* Whether BSP must be regenerated;
* Whether `xparameters.h` may change;
* Whether driver configuration tables may change;
* Whether linker script memory regions may change;
* Whether software needs to be rebuilt after platform regeneration.

If no hardware platform dependency changed, explicitly write:

```text
XSA / Platform / BSP dependency unchanged
```

If dependency changed, explicitly write:

```text
XSA / Platform / BSP dependency changed intentionally
```

Then explain the required update steps.

### 9. 内存与启动风险说明

For Vitis bare-metal projects, check memory/startup risks when applicable.

Must include:

* Whether `.text`, `.data`, `.bss`, heap, or stack usage changed;
* Whether linker script changed;
* Whether large global/static buffers were added;
* Whether startup may fail before entering `main`;
* Whether cache/MMU settings are relevant;
* Whether stack overflow or heap exhaustion is possible.

If memory usage was not checked, explicitly write:

```text
Memory usage not confirmed; check ELF/map file is recommended.
```

### 10. 修改文件列表

List all modified files.

Example:

| File                | Change              |
| ------------------- | ------------------- |
| `src/main.c`        | 修改 AD9528 SPI 初始化流程 |
| `src/ad9528_init.c` | 增加寄存器写入返回值检查        |
| `lscript.ld`        | 未修改                 |

If generated files were modified or regenerated, mark them clearly.

### 11. 风险与后续建议

List remaining risks, assumptions, and next actions.

For Vitis/software changes, include:

* whether Vitis build still needs to be run;
* whether hardware run still needs to be performed;
* whether serial console output needs to be checked;
* whether register readback needs to be added;
* whether XSA/platform/BSP needs regeneration;
* whether linker map file needs review;
* whether SPI/I2C/UART/GPIO waveform needs measurement;
* whether logic analyzer/ILA verification is recommended.

---

## 3.5 Special Vitis rules

For AD9528, ADRV9009, or SPI initialization code, always report:

* which SPI controller is used;
* selected slave-select index;
* expected chip ID or readback value;
* SPI mode and clock frequency if known;
* initialization order;
* whether reset pin is controlled by GPIO or external circuit;
* whether IO update or calibration trigger is required;
* whether readback verification is implemented;
* whether failure returns are propagated;
* whether software matches the board schematic and BD.

Do not hard-code a slave-select index unless it is justified by BD and schematic.

Do not assume unused SPI chip-selects are safe.

For AXI memory-mapped register access, always report:

* base address source;
* register offset;
* register width;
* read/write direction;
* whether write-one-to-clear behavior exists;
* whether status register is volatile;
* whether memory barriers are needed;
* whether cache coherency is relevant;
* whether hardware register map changed.

Use `volatile` or Xilinx MMIO accessors where appropriate.

Do not assume register layout unless RTL/IP documentation confirms it.

For interrupt-related software changes, always report:

* interrupt controller type;
* interrupt ID;
* handler function;
* priority/trigger type if applicable;
* whether interrupt is connected in BD;
* whether exception handling is initialized;
* whether interrupt is enabled at peripheral level and controller level;
* whether interrupt clear/ack sequence is correct.

For DMA or cached-memory changes, always report:

* buffer address;
* buffer alignment;
* cache flush/invalidate behavior;
* DMA direction;
* transfer length;
* completion mechanism;
* timeout handling;
* error handling;
* whether memory region is cacheable;
* whether hardware and software share the same address map.

Do not remove cache maintenance without explaining why it is safe.

---

# 4. Final completeness rule

After any modification, the final response must include the required report sections for the relevant scope.

If any required section is missing, the task is incomplete.

The final answer must not be a casual summary. It must be a structured Chinese engineering change report.

The engineering change report must be written in Chinese.

Code comments may remain in the original project language unless the task explicitly asks to translate or rewrite comments.

Technical terms such as RTL, pipeline, QoR, WNS, TNS, CDC, BD, IP Integrator, AXI, EMIO, MIO, XDC, HDL wrapper, XSA, Vitis, BSP, SPI, GPIO, linker script, ELF, DMA, cache, interrupt, CPOL, CPHA, and register readback may remain in English.

以后每次修改工程代码前，必须先使用 Git 工作流。

规则如下：

1. 修改前先执行：
   git status
   git branch

2. 如果当前工作区已有未提交修改，不要直接覆盖。
   先报告当前 dirty 文件列表，让我确认。

3. 每个功能改动必须创建独立分支，例如：
   feature/profile-table-refactor-500m-1000m
   feature/add-third-rate-static
   fix/rate-switch-timeout
   docs/dynamic-rate-summary

4. 不允许直接在 main/master 上修改并提交。

5. 每次修改后必须输出：
   - 修改文件列表；
   - git diff 摘要；
   - build/test 结果；
   - 是否生成 bit/LTX；
   - 是否完成 hardware test；
   - 仍未验证的边界。

6. 提交前必须确认不要加入 Vivado 生成目录和临时文件：
   .Xil/
   *.runs/
   *.cache/
   *.gen/
   *.jou
   *.log
   *.str
   *.dcp

7. 除非我明确要求，不要提交 bit/LTX。
   如需保存 bit/LTX，只在报告中记录本地路径，或提示我是否要放到 GitHub Release。

8. 提交命名格式：
   git commit -m "简短英文说明"

9. 推送格式：
   git push -u origin <branch_name>

10. 不允许 force push。
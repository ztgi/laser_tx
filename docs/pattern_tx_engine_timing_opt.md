# pattern_tx_engine timing optimization report

## 1. Symptom and original critical structure

The original `pattern_tx_engine` advanced all serial state with blocking
assignments inside one 64-iteration combinational loop.  Lane `n+1` depended
on the complete result of lane `n`, including:

- `running` and phase-end decisions;
- `patterns_done` and pattern-bit rollover;
- gap insertion/removal;
- phase-offset rollover;
- `txdata[n]` and `valid_mask[n]` generation.

Synthesis therefore built a long carry/mux chain rather than 64 parallel bit
decisions.  Physical optimization repeatedly transformed and re-placed pieces
of this chain but could not remove the underlying dependency.

## 2. Diagnostic evidence

The initial implementation log reported estimated timing around:

```text
WNS ~= -228.5 ns
TNS ~= -46925 ns
```

The completed pre-change synthesis checkpoint, reported by
`scripts/report_impl_timing_debug.tcl`, gave:

```text
Clock period: 20.000 ns (50 MHz temporary TX clock)
WNS:  -176.773 ns
TNS:  -35096.727 ns
Failing setup endpoints: 256
Worst source:      u_pattern_tx_engine/patterns_done_reg[4]
Worst destination: u_pattern_tx_engine/txdata_reg[63]
Data path delay:   196.362 ns
```

The worst-path report contains repeated `t_running`, `txdata`, `valid_mask`
and carry-chain nodes produced by the serially unrolled loop.  This confirms
that TX word generation—not a generic Vivado phys-opt issue—was the primary
bottleneck.

## 3. Was valid_mask/txdata generation the cause?

Yes.  `patterns_done` state propagated through many lane decisions before
reaching `txdata_reg[63]`.  The same dependency affected `valid_mask` and the
next-state registers.  The failing path was almost ten complete 50 MHz clock
periods long, so placement directives or extra phys-opt iterations could not
make the old structure converge.

## 4. ILA/debug impact

No RTL source contains `MARK_DEBUG`.  Before optimization, hierarchy usage was:

```text
u_pattern_tx_engine : 25,701 LUT
ila_laser_tx        :  3,468 LUT
```

ILA does add placement, BRAM and fanout pressure.  Its internal debug nets had
fanout around 400, but they were not the setup critical path.  Removing probes
alone could not repair a 176 ns setup violation.  The existing two-clock ILA
split was retained; no AXI-domain `gpio_status` is sampled by the TX ILA.

## 5. RTL changes

Only `pattern_tx_engine.v` was functionally restructured:

1. Replaced the 64-step serial state chain with a word-level phase position.
2. Captured active phase length, gap start/end and mode configuration at start.
3. Calculated pattern totals with shift/subtract (`x*63`, `x*127`), with no
   divider or modulo operator.
4. Used the fact that a phase is at least 63 bits, so a 64-bit word crosses at
   most one phase boundary.
5. Reduced the absolute gap interval to two 7-bit positions in the range
   0..64 once per word.
6. Generated all mask/data lanes in parallel from those relative bounds.
7. Replaced repeated dynamic pattern-address calculation with a periodic
   127-bit pattern cursor.  The cursor advances only by the number of valid
   bits, so gap bits never consume pattern data.
8. Kept `txdata`, `valid_mask`, phase status and phase-start pulse registered
   across the same clock boundary.

No change was made to `pattern_source`, `config_loader`, PRBS rules, direct
pattern assembly, GPIO/BRAM formats or synchronization-signal derivation.

## 6. Functional behavior

Functional behavior is unchanged:

- 63/127-bit periods and phase ranges are unchanged;
- repeat and gap insertion semantics are unchanged;
- gap lanes still produce `txdata=0`, `valid_mask=0`;
- `eom_out` remains `|valid_mask`;
- SOA/ACQ gates remain high across a phase, including gap;
- ACQ trigger remains one word-clock pulse at each phase start;
- loop and non-loop completion behavior is unchanged.

## 7. Pipeline latency

No additional pipeline stage was introduced.  Start-to-first-word latency and
the alignment among `txdata`, `valid_mask`, EOM, SOA and ACQ are unchanged.
The outputs remain registered exactly once in `pattern_tx_engine`.

## 8. Testbench result

`tb_laser_tx_core.sv` passed all self-checking scenarios after the change:

```text
Scenario 1: PRBS6, including phase/gap lane checks
Scenario 2: direct 127-bit pattern
Scenario 3: invalid configuration
PASS: all laser_tx_core scenarios passed
```

The reference model checks every TX lane, mask lane, EOM relationship, phase
gate, trigger and final phase range; no scenario was removed.

## 9. QoR comparison

### Synthesis

| Metric | Before | After |
|---|---:|---:|
| Setup WNS | -176.773 ns | +11.046 ns |
| Setup TNS | -35096.727 ns | 0 ns |
| Failing setup endpoints | 256 | 0 |
| Engine LUT | 25,701 | 7,170 |
| Core LUT | 26,081 | 7,236 |

### Routed implementation

```text
Setup WNS: +5.594 ns
Setup TNS: 0 ns
Hold WHS:  +0.040 ns
Hold THS:  0 ns
Failed/unrouted nets: 0
phys_opt_design elapsed: 6 s
route_design elapsed:   3 min 15 s
```

The final worst setup path is still inside the engine, from `phase_pos` to the
registered pattern cursor, but its 13.847 ns data delay meets the current
20 ns clock requirement with substantial margin.  QoR Suggestions reports
that the fully routed design easily meets setup timing.

## 10. Next actions if timing later fails

The measured result is for the temporary 50 MHz FCLK-based `txusrclk2`.  A
future GT user clock may be substantially faster; timing must be rerun after
the real GT clock constraint is installed.  If that frequency does not meet:

1. add one aligned pipeline stage around cursor rotation and word output;
2. reduce TX ILA depth/probes for the final production build;
3. register or duplicate remaining high-fanout word-control terms;
4. consider a fixed-width GT-specific pattern window once the final TX user
   clock/data-width relationship is known.

Do not return to per-lane serial next-state propagation or attempt to solve
that structure by increasing phys-opt directives.

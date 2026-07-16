# Debug warning acceptance

## PDCN-1569

- Count: 3.
- Objects: LUTs under `dbg_hub/inst/BSCANID.u_xsdbm_id/SWITCH_N_EXT_BSCAN`.
- Original diagnostic: a placed physical LUT input pin is connected although that input is not present in the implemented LUT equation.
- Root cause: the Vivado-generated debug hub/BSCAN identification logic retains physical input connectivity that is optimized out of the LUT equation.
- Functional assessment: all three objects are under `dbg_hub`; none is in the GT, TX user-clock, MMCM, runtime-rate executor, mailbox, or pattern data path.
- Evidence: routed design has zero DRC errors and zero unrouted nets; setup and hold both pass; `report_debug_core -full_path` completed and matching LTX was generated from this implemented design.
- Acceptance: retained as a Vivado 2022.2 generated-debug warning. No high-speed functional RTL is changed merely to remove it.
- Residual risk: Hardware Manager attachment and ILA operation still require first-board validation with the matching bit/LTX pair.

## RTSTAT-10

- Count: 1 summary violation covering 36 nets.
- Objects: the report begins with unused/no-routable-load nets inside `dbg_hub`; the complete authoritative object list remains in `drc.rpt`.
- Original diagnostic: one or more implemented nets have no routable loads.
- Root cause: debug-hub/ILA command and status logic, plus optimized or intentionally unused debug/status branches, leave driver-only nets after implementation optimization.
- Functional assessment: Vivado reports zero unrouted nets in `report_route_status`; therefore this warning is not an incomplete routed connection. No cited object is a functional clock or GT serial data path.
- Evidence: timing gate passes, DRC error count is zero, route status reports zero unrouted nets, debug cores are implemented, and bit/LTX generation succeeds from the same routed design.
- Acceptance: retained as a non-fatal debug/optimized-load warning.
- Residual risk: matching bit/LTX must be used and ILA enumeration/capture must be checked on hardware; no BER, eye, or long-duration test has been performed.

## Acceptance boundary

This acceptance does not downgrade or suppress the warnings. It only records why the current candidate may proceed to artifact generation. It does not prove board operation or physical-link quality.

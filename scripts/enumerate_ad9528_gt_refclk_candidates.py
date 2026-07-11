#!/usr/bin/env python3
"""Enumerate exact, non-executable AD9528 OUT0 -> GTX refclk candidates.

This planning tool does not open Vivado, program AD9528, edit an XCI, or add
any supported rate.  It intentionally separates two facts:

* The current laser_tx repository has no captured AD9528 OUT0 register image.
* A legacy reference program uses a 122.88 MHz VCXO, PLL1 bypass, PLL2 and
  OUT0 sourced from the PLL2 VCO distribution path.

The latter is useful only as a *reference assumption* for exact arithmetic.
Every generated row is therefore marked REGISTER_IMAGE_REQUIRED and is not a
board-verified clock plan.  Fractions are used end-to-end; no float rounding
participates in legality decisions.

Sources encoded by this read-only planner:
  * AD9528 data sheet Rev. G: PLL2 VCO 3450..4025 MHz, maximum PFD 275 MHz,
    high-speed output maximum 1.25 GHz, and output-divider architecture.
  * Existing reference source at project_gtx/software_src/laser_tx_rate/
    ad9528_rate.c: direct 122.88 MHz VCXO/PLL1-bypass assumptions, M1=3..5,
    R1/N2/OUT divider field use and OUT divider <= 256.
  * UG476 and DS191 constraints already encoded in
    enumerate_gtx_rate_candidates.py for XC7Z100-2 GTX.
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from dataclasses import asdict, dataclass
from fractions import Fraction
from pathlib import Path
from typing import Iterable, Optional

from enumerate_gtx_rate_candidates import (
    CPLL_FBDIVS,
    CPLL_FBDIV_45S,
    CPLL_REFCLK_DIVS,
    CPLL_TXOUT_DIVS,
    QPLL_FBDIVS,
    QPLL_REFCLK_DIVS,
    QPLL_TXOUT_DIVS,
    SUPPORTED_RATES_MBPS,
    cpll_line_range_ok,
    fmt,
    gtx_line_rate_coverage_reason,
    qpll_band,
    qpll_fbdiv_ratio,
    qpll_line_range_ok,
)


# Reference-only AD9528 assumptions.  These are not a current-board image.
REFERENCE_VCXO_HZ = Fraction(122_880_000)
PLL2_PFD_MAX_HZ = Fraction(275_000_000)
PLL2_VCO_MIN_HZ = Fraction(3_450_000_000)
PLL2_VCO_MAX_HZ = Fraction(4_025_000_000)
PLL2_M1_VALUES = (3, 4, 5)
PLL2_R1_VALUES = tuple(range(1, 32))
PLL2_N2_VALUES = tuple(range(1, 257))
PLL2_DOUBLER_VALUES = (1, 2)
OUT0_DIV_VALUES = tuple(range(1, 257))
OUT0_MAX_HZ = Fraction(1_250_000_000)


def mhz(value_hz: Fraction) -> Fraction:
    return value_hz / 1_000_000


def fmt_hz(value_hz: Fraction) -> str:
    return fmt(value_hz, places=9)


def ceil_fraction(value: Fraction) -> int:
    return -(-value.numerator // value.denominator)


def floor_fraction(value: Fraction) -> int:
    return value.numerator // value.denominator


@dataclass(frozen=True)
class Ad9528Out0Config:
    vcxo_hz: Fraction
    pll1_mode: str
    doubler: int
    r1: int
    n2: int
    m1: int
    out0_div: int
    pfd_hz: Fraction
    vco_hz: Fraction
    out0_hz: Fraction


@dataclass(frozen=True)
class CandidateRow:
    out0_hz: str
    out0_mhz: str
    ad9528_vcxo_hz: str
    ad9528_pll1_mode: str
    ad9528_doubler: int
    ad9528_r1: int
    ad9528_n2: int
    ad9528_m1: int
    ad9528_out0_div: int
    ad9528_pfd_hz: str
    ad9528_vco_hz: str
    equivalent_ad9528_config_count: int
    gtx_pll: str
    gtx_refclk_div: int
    gtx_n1: str
    gtx_n2_or_n: int
    gtx_txout_div: int
    gtx_vco_hz: str
    line_rate_mbps: str
    txusrclk_hz: str
    txusrclk2_hz: str
    status: str
    reason_or_gate: str


def canonical_key(config: Ad9528Out0Config) -> tuple[int, int, int, int, int]:
    """Stable representative when many legal PLL2 settings yield one OUT0."""
    return (config.doubler, config.r1, config.n2, config.m1, config.out0_div)


def enumerate_ad9528_out0(
    min_refclk_hz: Fraction,
    max_refclk_hz: Fraction,
) -> dict[Fraction, tuple[Ad9528Out0Config, int]]:
    """Return each exact OUT0 frequency with one canonical config and alias count."""
    candidates: dict[Fraction, tuple[Ad9528Out0Config, int]] = {}
    for doubler in PLL2_DOUBLER_VALUES:
        for r1 in PLL2_R1_VALUES:
            pfd_hz = REFERENCE_VCXO_HZ * doubler / r1
            if pfd_hz > PLL2_PFD_MAX_HZ:
                continue
            for n2 in PLL2_N2_VALUES:
                for m1 in PLL2_M1_VALUES:
                    vco_hz = pfd_hz * n2 * m1
                    if not PLL2_VCO_MIN_HZ <= vco_hz <= PLL2_VCO_MAX_HZ:
                        continue
                    base_hz = vco_hz / m1
                    # OUT0 must be <= 1.25 GHz and inside the refclk scope.
                    first_div = max(1, ceil_fraction(base_hz / max_refclk_hz))
                    last_div = min(256, floor_fraction(base_hz / min_refclk_hz))
                    for out0_div in range(first_div, last_div + 1):
                        out0_hz = base_hz / out0_div
                        if out0_hz > OUT0_MAX_HZ:
                            continue
                        config = Ad9528Out0Config(
                            vcxo_hz=REFERENCE_VCXO_HZ,
                            pll1_mode="BYPASS_REFERENCE_ASSUMPTION",
                            doubler=doubler,
                            r1=r1,
                            n2=n2,
                            m1=m1,
                            out0_div=out0_div,
                            pfd_hz=pfd_hz,
                            vco_hz=vco_hz,
                            out0_hz=out0_hz,
                        )
                        old = candidates.get(out0_hz)
                        if old is None:
                            candidates[out0_hz] = (config, 1)
                        else:
                            old_config, count = old
                            candidates[out0_hz] = (
                                config if canonical_key(config) < canonical_key(old_config) else old_config,
                                count + 1,
                            )
    return candidates


def gtx_candidates_for_refclk(refclk_hz: Fraction) -> Iterable[tuple[str, int, Optional[int], int, int, Fraction, Fraction]]:
    """Yield legal CPLL/QPLL tuples for an exact external reference frequency."""
    refclk_mhz = mhz(refclk_hz)
    for m in CPLL_REFCLK_DIVS:
        for n1 in CPLL_FBDIV_45S:
            for n2 in CPLL_FBDIVS:
                vco_mhz = refclk_mhz * n1 * n2 / m
                for divider in CPLL_TXOUT_DIVS:
                    line_mhz = 2 * vco_mhz / divider
                    if not Fraction(1600) <= vco_mhz <= Fraction(3300):
                        continue
                    if gtx_line_rate_coverage_reason(line_mhz) is not None:
                        continue
                    if not cpll_line_range_ok(line_mhz, divider):
                        continue
                    yield ("CPLL", m, n1, n2, divider, vco_mhz, line_mhz)
    for m in QPLL_REFCLK_DIVS:
        for n in QPLL_FBDIVS:
            vco_mhz = refclk_mhz * n / m
            band = qpll_band(vco_mhz)
            for divider in QPLL_TXOUT_DIVS:
                line_mhz = vco_mhz / divider
                if band is None:
                    continue
                if gtx_line_rate_coverage_reason(line_mhz) is not None:
                    continue
                if not qpll_line_range_ok(line_mhz, divider, band):
                    continue
                yield ("QPLL", m, None, n, divider, vco_mhz, line_mhz)


def status_for_line_rate(line_mhz: Fraction) -> tuple[str, str]:
    # The formal planner intentionally keeps 3000 Mbps blocked.  A possible
    # arithmetic tuple is not enough to overturn the documented 125 MHz CPLL
    # limitation or establish a new QPLL/MMCM profile; GT Wizard and board
    # evidence are required before this policy can be reconsidered.
    if line_mhz == Fraction(3000):
        return ("BLOCKED", "FORMAL_3000M_BLOCKED_PENDING_GT_WIZARD_AND_MMCM_PROFILE_EVIDENCE")
    if line_mhz.denominator == 1 and int(line_mhz) in SUPPORTED_RATES_MBPS:
        return ("ALREADY_SUPPORTED_RATE_VALUE", "EXISTING_PROFILE_PARAMETER_MATCH_REQUIRED")
    return ("LEGAL_CANDIDATE", "REGISTER_IMAGE_REQUIRED;GT_WIZARD_REQUIRED;MMCM_DRP_REQUIRED;TIMING_AND_BOARD_REQUIRED")


def to_row(
    config: Ad9528Out0Config,
    alias_count: int,
    gtx: tuple[str, int, Optional[int], int, int, Fraction, Fraction],
) -> CandidateRow:
    pll, refclk_div, n1, n2_or_n, divider, vco_mhz, line_mhz = gtx
    status, reason = status_for_line_rate(line_mhz)
    line_hz = line_mhz * 1_000_000
    return CandidateRow(
        out0_hz=fmt_hz(config.out0_hz),
        out0_mhz=fmt(mhz(config.out0_hz), places=9),
        ad9528_vcxo_hz=fmt_hz(config.vcxo_hz),
        ad9528_pll1_mode=config.pll1_mode,
        ad9528_doubler=config.doubler,
        ad9528_r1=config.r1,
        ad9528_n2=config.n2,
        ad9528_m1=config.m1,
        ad9528_out0_div=config.out0_div,
        ad9528_pfd_hz=fmt_hz(config.pfd_hz),
        ad9528_vco_hz=fmt_hz(config.vco_hz),
        equivalent_ad9528_config_count=alias_count,
        gtx_pll=pll,
        gtx_refclk_div=refclk_div,
        gtx_n1="-" if n1 is None else str(n1),
        gtx_n2_or_n=n2_or_n,
        gtx_txout_div=divider,
        gtx_vco_hz=fmt_hz(vco_mhz * 1_000_000),
        line_rate_mbps=fmt(line_mhz, places=9),
        txusrclk_hz=fmt_hz(line_hz / 32),
        txusrclk2_hz=fmt_hz(line_hz / 64),
        status=status,
        reason_or_gate=reason,
    )


def write_csv(rows: Iterable[CandidateRow], path: Path) -> None:
    rows = list(rows)
    fieldnames = list(asdict(rows[0]).keys()) if rows else list(CandidateRow.__annotations__.keys())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)


def write_summary(
    rows: list[CandidateRow],
    ad_frequencies: dict[Fraction, tuple[Ad9528Out0Config, int]],
    path: Path,
) -> None:
    by_pll: dict[str, set[str]] = defaultdict(set)
    by_status: dict[str, int] = defaultdict(int)
    for row in rows:
        by_pll[row.gtx_pll].add(row.line_rate_mbps)
        by_status[row.status] += 1
    supported = sorted({row.line_rate_mbps for row in rows if row.status == "ALREADY_SUPPORTED_RATE_VALUE"}, key=Fraction)
    novel = sorted({row.line_rate_mbps for row in rows if row.status == "LEGAL_CANDIDATE"}, key=Fraction)
    content = [
        "# AD9528 OUT0 -> GTX exact candidate output",
        "",
        "Generated by `scripts/enumerate_ad9528_gt_refclk_candidates.py`. It is a mathematical planning ledger, not an AD9528 register image and not an executable GT profile list.",
        "",
        f"- Exact unique AD9528 OUT0 frequencies in scope: {len(ad_frequencies)}.",
        f"- AD9528/GT combined legal tuples: {len(rows)}.",
        f"- Tuple classification: " + ", ".join(f"{key}={value}" for key, value in sorted(by_status.items())),
        "- Reference input assumption: 122.88 MHz VCXO, PLL1 bypass, PLL2 source; actual current OUT0 register image is not captured in `laser_tx`.",
        "- All `LEGAL_CANDIDATE` rows require a trusted board register image, AD9528 programming/readback, GT Wizard, MMCM DRP generation, implementation, and board verification before becoming a profile.",
        "",
        "## Formulas",
        "",
        "- `PFD = VCXO × doubler / R1`",
        "- `PLL2 VCO = PFD × N2 × M1`",
        "- `OUT0 = PLL2 VCO / (M1 × OUT0_DIV)`",
        "- CPLL: `line rate = 2 × OUT0 × N1 × N2 / (M × TXOUT_DIV)`",
        "- QPLL: `line rate = OUT0 × N / (M × TXOUT_DIV)`",
        "- Current 64-bit no-8b/10b interface: `TXUSRCLK2 = line rate / 64`",
        "",
        "## Rate-value de-duplication",
        "",
        "- Existing supported numeric values reached by one or more tuples: " + (", ".join(supported) if supported else "none"),
        "- New legal numeric values are in the CSV as `LEGAL_CANDIDATE`; no recommendation is made while the current AD9528 register image is unknown.",
        "- CPLL unique line-rate count: " + str(len(by_pll["CPLL"])),
        "- QPLL unique line-rate count: " + str(len(by_pll["QPLL"])),
        "",
        "## Scope limits",
        "",
        "- `3000 Mbps` remains BLOCKED / unsupported in the formal planner. A mathematical row here does not override the existing documented GT-Wizard and profile-validation gate.",
        "- This script does not enumerate a physical AD9528 register map, IO_UPDATE/SYNC sequence, or board-current PLL1 state.",
    ]
    path.write_text("\n".join(content) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--min-refclk-mhz", type=str, default="60")
    parser.add_argument("--max-refclk-mhz", type=str, default="200")
    args = parser.parse_args()
    min_refclk_hz = Fraction(args.min_refclk_mhz) * 1_000_000
    max_refclk_hz = Fraction(args.max_refclk_mhz) * 1_000_000
    if min_refclk_hz <= 0 or min_refclk_hz > max_refclk_hz:
        raise SystemExit("invalid --min-refclk-mhz/--max-refclk-mhz range")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    ad_frequencies = enumerate_ad9528_out0(min_refclk_hz, max_refclk_hz)
    rows: list[CandidateRow] = []
    for out0_hz, (config, aliases) in ad_frequencies.items():
        for gtx in gtx_candidates_for_refclk(out0_hz):
            rows.append(to_row(config, aliases, gtx))
    rows.sort(key=lambda row: (
        Fraction(row.out0_hz), row.gtx_pll, Fraction(row.line_rate_mbps),
        row.gtx_refclk_div, row.gtx_txout_div,
    ))
    write_csv(rows, args.output_dir / "ad9528_gt_refclk_candidates.csv")
    write_summary(rows, ad_frequencies, args.output_dir / "ad9528_gt_refclk_candidates_summary.md")

    unique_rates = sorted({Fraction(row.line_rate_mbps) for row in rows})
    print(f"PASS: exact OUT0 frequencies={len(ad_frequencies)} combined GTX tuples={len(rows)}")
    print(f"Unique GTX line-rate values={len(unique_rates)}")
    print(f"Output: {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

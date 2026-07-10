#!/usr/bin/env python3
"""Enumerate read-only GTX line-rate candidates for the laser_tx project.

The script deliberately does *not* open Vivado, edit an XCI, or create a
profile.  It applies the divider and rate-range constraints documented for
XC7Z100 -2 GTX, then writes a CSV ledger and a compact Markdown report to an
explicit output directory.  A passing row is a silicon-level candidate only;
GT Wizard, MMCM DRP, timing, and board validation remain separate gates.

Sources encoded here:
  * UG476 v1.12.1, Tables 2-12/2-13 and CPLL/QPLL equations.
  * DS191 v1.18.1, XC7Z100 -2 GTX performance table.

The current project has 64-bit TXDATA, 32-bit internal width, and no 8b/10b.
For that interface TXUSRCLK = line_rate / 32 and TXUSRCLK2 = line_rate / 64.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass, asdict
from fractions import Fraction
from pathlib import Path
from typing import Iterable, Optional


SUPPORTED_RATES_MBPS = {
    500, 1000, 1250, 2000, 2500, 3125, 5000, 6250, 10000,
}

# XC7Z100 -2 GTX (DS191): 0.500 to 10.3125 Gb/s overall.
MIN_LINE_RATE_MHZ = Fraction(500)
MAX_LINE_RATE_MHZ = Fraction(20625, 2)  # 10.3125 Gb/s
MAX_CURRENT_PROJECT_TXUSRCLK2_MHZ = Fraction(625, 4)  # 156.25 MHz at 10G

# UG476 divider domains.
CPLL_REFCLK_DIVS = (1, 2)
CPLL_FBDIV_45S = (4, 5)
CPLL_FBDIVS = (1, 2, 3, 4, 5)
CPLL_TXOUT_DIVS = (1, 2, 4, 8)  # D=16 is not supported for CPLL.
QPLL_REFCLK_DIVS = (1, 2, 3, 4)
QPLL_FBDIVS = (16, 20, 32, 40, 64, 66, 80, 100)
QPLL_TXOUT_DIVS = (1, 2, 4, 8, 16)


def fmt(value: Fraction, places: int = 6) -> str:
    """Return a stable decimal without a gratuitous trailing decimal point."""
    text = f"{float(value):.{places}f}".rstrip("0").rstrip(".")
    return text or "0"


def rate_status(line_rate_mhz: Fraction) -> str:
    """Classify only the line-rate, never an ungenerated hardware profile."""
    if line_rate_mhz.denominator == 1 and int(line_rate_mhz) in SUPPORTED_RATES_MBPS:
        return "ALREADY_SUPPORTED"
    return "LEGAL_CANDIDATE"


def project_gate(refclk_mhz: Fraction, txusrclk2_mhz: Fraction) -> str:
    gates = ["GT_WIZARD_XCI_REQUIRED", "MMCM_DRP_REQUIRED", "TIMING_AND_ILA_REQUIRED"]
    if refclk_mhz == Fraction(625, 4):
        gates.append("BOARD_156P25_REFCLK_PATH_UNCONFIRMED")
    if txusrclk2_mhz > MAX_CURRENT_PROJECT_TXUSRCLK2_MHZ:
        gates.append("ABOVE_CURRENT_156P25_TXUSRCLK2_BASELINE")
    return ";".join(gates)


@dataclass(frozen=True)
class Row:
    refclk_mhz: str
    pll: str
    m: str
    n1: str
    n2_or_n: str
    txout_div: str
    pll_vco_mhz: str
    line_rate_mbps: str
    txoutclk_mhz: str
    txusrclk_mhz: str
    txusrclk2_mhz: str
    status: str
    reason_or_gate: str


def cpll_line_range_ok(line_mhz: Fraction, divider: int) -> bool:
    # DS191 XC7Z100 -2 CPLL ranges by TXOUT_DIV.
    ranges = {
        1: (Fraction(3200), Fraction(6600)),
        2: (Fraction(1600), Fraction(3300)),
        4: (Fraction(800), Fraction(1650)),
        8: (Fraction(500), Fraction(825)),
    }
    lower, upper = ranges[divider]
    return lower <= line_mhz <= upper


def qpll_band(vco_mhz: Fraction) -> Optional[str]:
    # DS191 XC7Z100 -2: lower 5.93..8.0 GHz; upper 9.8..10.3125 GHz.
    if Fraction(5930) <= vco_mhz <= Fraction(8000):
        return "LOWER"
    if Fraction(9800) <= vco_mhz <= Fraction(20625, 2):
        return "UPPER"
    return None


def qpll_line_range_ok(line_mhz: Fraction, divider: int, band: str) -> bool:
    # DS191 XC7Z100 -2 QPLL ranges by VCO band and TXOUT_DIV.
    ranges = {
        "LOWER": {
            1: (Fraction(5930), Fraction(8000)),
            2: (Fraction(2965), Fraction(4000)),
            4: (Fraction(14825, 10), Fraction(2000)),
            8: (Fraction(74125, 100), Fraction(1000)),
        },
        "UPPER": {
            1: (Fraction(9800), Fraction(20625, 2)),
            2: (Fraction(4900), Fraction(103125, 20)),
            4: (Fraction(2450), Fraction(4125, 2)),
            8: (Fraction(1225), Fraction(103125, 80)),
            16: (Fraction(1225, 2), Fraction(103125, 160)),
        },
    }
    if divider not in ranges[band]:
        return False
    lower, upper = ranges[band][divider]
    return lower <= line_mhz <= upper


def row_for(refclk: Fraction, pll: str, m: int, n1: Optional[int], n2_or_n: int,
            divider: int, vco: Fraction, line: Fraction, status: str,
            reason: str) -> Row:
    txusrclk = line / 32
    txusrclk2 = line / 64
    return Row(
        refclk_mhz=fmt(refclk),
        pll=pll,
        m=str(m),
        n1="-" if n1 is None else str(n1),
        n2_or_n=str(n2_or_n),
        txout_div=str(divider),
        pll_vco_mhz=fmt(vco),
        line_rate_mbps=fmt(line),
        txoutclk_mhz=fmt(txusrclk),
        txusrclk_mhz=fmt(txusrclk),
        txusrclk2_mhz=fmt(txusrclk2),
        status=status,
        reason_or_gate=reason,
    )


def enumerate_cpll(refclk: Fraction) -> tuple[list[Row], list[Row]]:
    legal: list[Row] = []
    blocked: list[Row] = []
    for m in CPLL_REFCLK_DIVS:
        for n1 in CPLL_FBDIV_45S:
            for n2 in CPLL_FBDIVS:
                vco = refclk * n1 * n2 / m
                for divider in CPLL_TXOUT_DIVS:
                    line = 2 * vco / divider
                    if not Fraction(1600) <= vco <= Fraction(3300):
                        blocked.append(row_for(
                            refclk, "CPLL", m, n1, n2, divider, vco, line,
                            "BLOCKED", "CPLL_VCO_OUTSIDE_XC7Z100_2_RANGE_1600_TO_3300MHZ"))
                    elif not MIN_LINE_RATE_MHZ <= line <= MAX_LINE_RATE_MHZ:
                        blocked.append(row_for(
                            refclk, "CPLL", m, n1, n2, divider, vco, line,
                            "BLOCKED", "GTX_LINE_RATE_OUTSIDE_XC7Z100_2_500_TO_10312P5MBPS"))
                    elif not cpll_line_range_ok(line, divider):
                        blocked.append(row_for(
                            refclk, "CPLL", m, n1, n2, divider, vco, line,
                            "BLOCKED", "CPLL_TXOUT_DIV_LINE_RATE_RANGE_VIOLATION"))
                    else:
                        legal.append(row_for(
                            refclk, "CPLL", m, n1, n2, divider, vco, line,
                            rate_status(line), project_gate(refclk, line / 64)))
    return legal, blocked


def enumerate_qpll(refclk: Fraction) -> tuple[list[Row], list[Row]]:
    legal: list[Row] = []
    blocked: list[Row] = []
    for m in QPLL_REFCLK_DIVS:
        for n in QPLL_FBDIVS:
            vco = refclk * n / m
            band = qpll_band(vco)
            for divider in QPLL_TXOUT_DIVS:
                # UG476 QPLL relation: VCO / TXOUT_DIV.  The internal /2 and
                # DDR serializer factors cancel in the line-rate equation.
                line = vco / divider
                if band is None:
                    blocked.append(row_for(
                        refclk, "QPLL", m, None, n, divider, vco, line,
                        "BLOCKED", "QPLL_VCO_NOT_IN_XC7Z100_2_LOWER_OR_UPPER_BAND"))
                elif not MIN_LINE_RATE_MHZ <= line <= MAX_LINE_RATE_MHZ:
                    blocked.append(row_for(
                        refclk, "QPLL", m, None, n, divider, vco, line,
                        "BLOCKED", "GTX_LINE_RATE_OUTSIDE_XC7Z100_2_500_TO_10312P5MBPS"))
                elif not qpll_line_range_ok(line, divider, band):
                    blocked.append(row_for(
                        refclk, "QPLL", m, None, n, divider, vco, line,
                        "BLOCKED", "QPLL_TXOUT_DIV_LINE_RATE_RANGE_VIOLATION"))
                else:
                    legal.append(row_for(
                        refclk, "QPLL", m, None, n, divider, vco, line,
                        rate_status(line), project_gate(refclk, line / 64)))
    return legal, blocked


def write_csv(rows: Iterable[Row], path: Path) -> None:
    rows = list(rows)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)


def compact_table(rows: Iterable[Row], title: str) -> str:
    rows = list(rows)
    lines = [f"## {title}", "", "| M | N1 | N2/N | D | VCO MHz | line Mbps | TXUSRCLK2 MHz | status |", "|---:|---:|---:|---:|---:|---:|---:|---|"]
    for row in rows:
        lines.append(
            f"| {row.m} | {row.n1} | {row.n2_or_n} | {row.txout_div} | "
            f"{row.pll_vco_mhz} | {row.line_rate_mbps} | {row.txusrclk2_mhz} | {row.status} |")
    return "\n".join(lines)


def write_markdown(legal_rows: list[Row], blocked_rows: list[Row], path: Path) -> None:
    by_key = {}
    for row in legal_rows:
        by_key.setdefault((row.refclk_mhz, row.pll), []).append(row)
    content = [
        "# GTX candidate-rate enumerator output", "",
        "Generated by `scripts/enumerate_gtx_rate_candidates.py`; this output does not create a supported profile.",
        "",
        "- CPLL: `line = 2 × REFCLK × N1 × N2 / (M × D)`.",
        "- QPLL: `line = REFCLK × N / (M × D)`.",
        "- Current no-8b/10b 64-bit interface: `TXUSRCLK2 = line / 64`.",
        "- `LEGAL_CANDIDATE` means published silicon constraints pass; it still needs GT Wizard, MMCM DRP, timing, and board validation.",
        "",
    ]
    for refclk in ("125", "156.25"):
        for pll in ("CPLL", "QPLL"):
            rows = by_key.get((refclk, pll), [])
            content.append(compact_table(rows, f"{refclk} MHz {pll}"))
            content.append("")
    content.extend([
        "## BLOCKED combinations", "",
        "Every rejected tuple appears in `gtx_rate_candidates_blocked.csv`; the reason column is authoritative.",
        f"Rejected tuples: {len(blocked_rows)}.",
        "",
    ])
    path.write_text("\n".join(content), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True,
                        help="Directory for generated CSV and Markdown results; not a source directory.")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    legal_rows: list[Row] = []
    blocked_rows: list[Row] = []
    for refclk in (Fraction(125), Fraction(625, 4)):
        for enumerate_fn in (enumerate_cpll, enumerate_qpll):
            legal, blocked = enumerate_fn(refclk)
            legal_rows.extend(legal)
            blocked_rows.extend(blocked)

    legal_rows.sort(key=lambda row: (Fraction(row.refclk_mhz), row.pll,
                                     Fraction(row.line_rate_mbps), int(row.m), int(row.txout_div)))
    blocked_rows.sort(key=lambda row: (Fraction(row.refclk_mhz), row.pll,
                                       row.reason_or_gate, Fraction(row.line_rate_mbps)))
    write_csv(legal_rows, args.output_dir / "gtx_rate_candidates_legal.csv")
    write_csv(blocked_rows, args.output_dir / "gtx_rate_candidates_blocked.csv")
    write_markdown(legal_rows, blocked_rows, args.output_dir / "gtx_rate_candidates_summary.md")

    rates = sorted({Fraction(row.line_rate_mbps) for row in legal_rows})
    print(f"PASS: generated {len(legal_rows)} legal tuples and {len(blocked_rows)} blocked tuples")
    print("Unique legal line rates (Mbps): " + ", ".join(fmt(rate) for rate in rates))
    print(f"Output: {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Classify all legal GTX tuples into one preferred implementation per rate.

This is a planning-only tool.  It reads the full legal CSV produced by
enumerate_gtx_rate_candidates.py and derives the implemented-rate set from the
current Vitis profile table.  It never edits RTL, Vitis profiles, XCI, or DRP
data.  Fraction and integer-bps keys deliberately avoid float-based rate
deduplication.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from fractions import Fraction
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILE_TABLE = ROOT / "vitis_bringup/bringup/src/gt_rate_plan.c"

KNOWN_CPLL_GROUPS = {
    ("125", "1", "4", "4"),
    ("125", "1", "4", "5"),
    ("125", "1", "5", "5"),
}
KNOWN_TXOUT_DIVS = {"1", "2", "4", "8"}
CATEGORY_ORDER = {
    "RECOMMENDED_125M_CPLL": 0,
    "RECOMMENDED_125M_QPLL": 1,
    "RECOMMENDED_156P25M_CPLL": 2,
    "RECOMMENDED_156P25M_QPLL": 3,
}


def as_fraction(text: str) -> Fraction:
    return Fraction(text)


def fraction_to_bps(mbps: Fraction) -> int:
    bps = mbps * 1_000_000
    if bps.denominator != 1:
        raise ValueError(f"rate is not integral bps: {mbps}")
    return bps.numerator


def exact_decimal(value: Fraction) -> str:
    integer = value.numerator // value.denominator
    remainder = value.numerator % value.denominator
    if remainder == 0:
        return str(integer)
    digits: list[str] = []
    seen: set[int] = set()
    while remainder and remainder not in seen:
        seen.add(remainder)
        remainder *= 10
        digits.append(str(remainder // value.denominator))
        remainder %= value.denominator
    if remainder:
        raise ValueError(f"non-terminating decimal rate: {value}")
    return f"{integer}.{' '.join(digits).replace(' ', '')}".rstrip("0").rstrip(".")


def load_supported_bps(profile_table: Path) -> set[int]:
    text = profile_table.read_text(encoding="utf-8")
    table = text.split("static const GtRateProfile gt_rate_profile_table", 1)[1].split("};", 1)[0]
    entries = re.findall(
        r"\.rate_mbps\s*=\s*(\d+)U.*?\.board_verified\s*=\s*(\d+)U",
        table,
        flags=re.DOTALL,
    )
    supported = {int(rate) * 1_000_000 for rate, verified in entries if verified == "1"}
    if not supported:
        raise ValueError("no board_verified Vitis profiles found")
    return supported


def category(row: dict[str, str]) -> str:
    refclk = as_fraction(row["refclk_mhz"])
    if refclk == Fraction(125):
        return "RECOMMENDED_125M_CPLL" if row["pll"] == "CPLL" else "RECOMMENDED_125M_QPLL"
    if refclk == Fraction(625, 4):
        return "RECOMMENDED_156P25M_CPLL" if row["pll"] == "CPLL" else "RECOMMENDED_156P25M_QPLL"
    raise ValueError(f"unexpected refclk {row['refclk_mhz']}")


def reuses_cpll_group(row: dict[str, str]) -> bool:
    return row["pll"] == "CPLL" and (
        row["refclk_mhz"], row["m"], row["n1"], row["n2_or_n"]
    ) in KNOWN_CPLL_GROUPS


def preferred_sort_key(row: dict[str, str]) -> tuple[int, int, int, int, int]:
    cat = category(row)
    return (
        CATEGORY_ORDER[cat],
        0 if reuses_cpll_group(row) else 1,
        0 if row["txout_div"] in KNOWN_TXOUT_DIVS else 1,
        int(row["m"]),
        int(row["txout_div"]),
    )


def tuple_description(row: dict[str, str]) -> str:
    if row["pll"] == "CPLL":
        params = f"M={row['m']};N1={row['n1']};N2={row['n2_or_n']}"
    else:
        params = f"M={row['m']};QPLL_N={row['n2_or_n']};RATIO={row['qpll_fbdiv_ratio']}"
    return (
        f"refclk={row['refclk_mhz']}MHz;pll={row['pll']};{params};"
        f"D={row['txout_div']};VCO={row['pll_vco_mhz']}MHz"
    )


def complexity(row: dict[str, str], fractional_rate: bool) -> str:
    cat = category(row)
    if cat == "RECOMMENDED_125M_CPLL" and reuses_cpll_group(row) and not fractional_rate:
        return "LOW"
    if cat == "RECOMMENDED_125M_CPLL":
        return "MEDIUM"
    if cat in ("RECOMMENDED_125M_QPLL", "RECOMMENDED_156P25M_CPLL"):
        return "HIGH"
    return "VERY_HIGH"


def batch_name(row: dict[str, str], fractional_rate: bool) -> str:
    cat = category(row)
    if cat == "RECOMMENDED_125M_CPLL":
        return "A_FRACTIONAL_RATE_BPS_PREREQUISITE" if fractional_rate else (
            "A_125M_CPLL_REUSE" if reuses_cpll_group(row) else "B_125M_CPLL_NEW_GROUP"
        )
    if cat == "RECOMMENDED_125M_QPLL":
        return "D_125M_QPLL_NEW_PROFILE"
    if cat == "RECOMMENDED_156P25M_CPLL":
        return "C_156P25M_CPLL_REFCLK_PATH"
    return "E_156P25M_QPLL_REFCLK_AND_PROFILE"


def reason(row: dict[str, str], fractional_rate: bool) -> str:
    cat = category(row)
    parts = [
        "selected by global line-rate deduplication",
        "125MHz preferred over 156.25MHz" if row["refclk_mhz"] == "125" else "requires second 156.25MHz refclk path",
    ]
    if row["pll"] == "CPLL":
        parts.append("CPLL preferred over QPLL at the same refclk")
        if reuses_cpll_group(row):
            parts.append("reuses an existing 125MHz CPLL divider group")
    else:
        parts.append("no higher-priority legal CPLL implementation exists")
        parts.append("requires a new QPLL static profile review")
    if row["txout_div"] in KNOWN_TXOUT_DIVS:
        parts.append("uses an existing TXOUT_DIV encoding")
    if fractional_rate:
        parts.append("requires rate_bps protocol/display migration")
    return "; ".join(parts)


def decorate_row(rate_bps: int, rows: list[dict[str, str]]) -> dict[str, str]:
    preferred = sorted(rows, key=preferred_sort_key)[0]
    rate_mbps = as_fraction(preferred["line_rate_mbps"])
    fractional = rate_bps % 1_000_000 != 0
    alternatives = [tuple_description(row) for row in rows if row is not preferred]
    is_qpll = preferred["pll"] == "QPLL"
    return {
        "line_rate_bps": str(rate_bps),
        "display_rate_mbps": exact_decimal(rate_mbps),
        "preferred_refclk_hz": str(int(as_fraction(preferred["refclk_mhz"]) * 1_000_000)),
        "preferred_pll": preferred["pll"],
        "preferred_M_N1_N2_or_QPLL_N_M": (
            f"M={preferred['m']};N1={preferred['n1']};N2={preferred['n2_or_n']}"
            if not is_qpll else
            f"QPLL_N={preferred['n2_or_n']};M={preferred['m']};RATIO={preferred['qpll_fbdiv_ratio']}"
        ),
        "preferred_txout_div": preferred["txout_div"],
        "preferred_pll_vco_hz": str(int(as_fraction(preferred["pll_vco_mhz"]) * 1_000_000)),
        "expected_txusrclk_hz": str(int(as_fraction(preferred["txusrclk_mhz"]) * 1_000_000)),
        "expected_txusrclk2_hz": str(int(as_fraction(preferred["txusrclk2_mhz"]) * 1_000_000)),
        "preferred_category": category(preferred),
        "reuse_existing_pll_group": str(reuses_cpll_group(preferred)).lower(),
        "reuse_existing_txout_div": str(preferred["txout_div"] in KNOWN_TXOUT_DIVS).lower(),
        "requires_new_cpll_group": str(preferred["pll"] == "CPLL" and not reuses_cpll_group(preferred)).lower(),
        "requires_new_qpll_static_profile": str(is_qpll).lower(),
        "requires_qpll_drp": "TBD_WIZARD_CONFIRMATION" if is_qpll else "false",
        "requires_156p25_refclk_path": str(as_fraction(preferred["refclk_mhz"]) == Fraction(625, 4)).lower(),
        "requires_fractional_rate_protocol": str(fractional).lower(),
        "alternative_implementation_count": str(len(alternatives)),
        "alternative_implementations": json.dumps(alternatives, ensure_ascii=False, separators=(",", ",")),
        "recommendation_reason": reason(preferred, fractional),
        "estimated_complexity": complexity(preferred, fractional),
        "recommended_batch": batch_name(preferred, fractional),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legal-csv", type=Path, required=True)
    parser.add_argument("--output-csv", type=Path, required=True)
    parser.add_argument("--summary-json", type=Path, required=True)
    parser.add_argument("--profile-table", type=Path, default=DEFAULT_PROFILE_TABLE)
    args = parser.parse_args()

    with args.legal_csv.open(newline="", encoding="utf-8") as handle:
        legal_rows = list(csv.DictReader(handle))
    if not legal_rows:
        raise ValueError("legal CSV is empty")

    grouped: dict[int, list[dict[str, str]]] = defaultdict(list)
    by_class = Counter()
    for row in legal_rows:
        grouped[fraction_to_bps(as_fraction(row["line_rate_mbps"]))].append(row)
        by_class[f"{row['refclk_mhz']}MHz_{row['pll']}"] += 1

    supported_bps = load_supported_bps(args.profile_table)
    remaining = [decorate_row(rate, rows) for rate, rows in sorted(grouped.items())
                 if rate not in supported_bps]
    supported_alternatives = {
        str(rate): [tuple_description(row) for row in rows]
        for rate, rows in sorted(grouped.items()) if rate in supported_bps
    }
    category_counts = Counter(row["preferred_category"] for row in remaining)
    summary: dict[str, Any] = {
        "legal_tuple_count": len(legal_rows),
        "legal_tuple_counts_by_refclk_pll": dict(sorted(by_class.items())),
        "global_unique_line_rate_count": len(grouped),
        "supported_line_rate_count": len(supported_bps),
        "supported_line_rates_bps": sorted(supported_bps),
        "remaining_line_rate_count": len(remaining),
        "remaining_fractional_rate_count": sum(
            row["requires_fractional_rate_protocol"] == "true" for row in remaining),
        "preferred_category_counts": dict(sorted(category_counts.items())),
        "supported_rate_alternative_implementations": supported_alternatives,
    }

    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(remaining[0].keys()))
        writer.writeheader()
        writer.writerows(remaining)
    args.summary_json.parent.mkdir(parents=True, exist_ok=True)
    args.summary_json.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print("PASS: classified GTX legal tuples with exact integer-bps rate keys")
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

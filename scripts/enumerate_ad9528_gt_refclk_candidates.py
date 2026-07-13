#!/usr/bin/env python3
"""Plan AD9528 OUT0/GT implementation-path candidates without hardware writes.

All legality arithmetic uses Fraction.  This tool does not write AD9528,
invoke Vivado, modify supported rates, or generate DRP register values.
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import asdict, dataclass
from fractions import Fraction
from functools import lru_cache
from pathlib import Path
from typing import Iterable, Optional

from enumerate_gtx_rate_candidates import (
    CPLL_FBDIVS, CPLL_FBDIV_45S, CPLL_REFCLK_DIVS, CPLL_TXOUT_DIVS,
    QPLL_FBDIVS, QPLL_REFCLK_DIVS, QPLL_TXOUT_DIVS,
    SUPPORTED_RATES_MBPS, cpll_line_range_ok, gtx_line_rate_coverage_reason,
    qpll_band, qpll_line_range_ok,
)


SUPPORTED = "SUPPORTED"
CANDIDATE = "CANDIDATE"
BLOCKED = "BLOCKED"

FIXED_125M_CPLL = "FIXED_125M_CPLL"
FIXED_125M_QPLL = "FIXED_125M_QPLL"
FIXED_156P25M_CPLL = "FIXED_156P25M_CPLL"
FIXED_156P25M_QPLL = "FIXED_156P25M_QPLL"
AD9528_OUT0_CPLL_EXPERIMENTAL = "AD9528_OUT0_CPLL_EXPERIMENTAL"
AD9528_OUT0_QPLL_EXPERIMENTAL = "AD9528_OUT0_QPLL_EXPERIMENTAL"

NONE = "NONE"
LEGAL_NOT_IMPLEMENTED = "LEGAL_NOT_IMPLEMENTED"
IMPLEMENTED_NOT_BOARD_VERIFIED = "IMPLEMENTED_NOT_BOARD_VERIFIED"
REFERENCE_CLOCK_NOT_BOARD_CONNECTED = "REFERENCE_CLOCK_NOT_BOARD_CONNECTED"
AD9528_PROFILE_NOT_IMPLEMENTED = "AD9528_PROFILE_NOT_IMPLEMENTED"
GT_WIZARD_NOT_CONFIRMED = "GT_WIZARD_NOT_CONFIRMED"
MMCM_PROFILE_NOT_CONFIRMED = "MMCM_PROFILE_NOT_CONFIRMED"
NO_LEGAL_VERIFIED_125M_CPLL_PROFILE = "NO_LEGAL_VERIFIED_125M_CPLL_PROFILE"
NO_LEGAL_125M_QPLL_PROFILE = "NO_LEGAL_125M_QPLL_PROFILE"
NO_LEGAL_156P25M_PROFILE = "NO_LEGAL_156P25M_PROFILE"
NO_LEGAL_AD9528_OUT0_PROFILE = "NO_LEGAL_AD9528_OUT0_PROFILE"
SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED = "SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED"
AD9528_REGISTER_IMAGE_NOT_CONFIRMED = "AD9528_REGISTER_IMAGE_NOT_CONFIRMED"

VCXO_DIRECT = "VCXO_DIRECT"
PLL2_SYNTHESIZED = "PLL2_SYNTHESIZED"
UNKNOWN_OR_UNCONFIRMED = "UNKNOWN_OR_UNCONFIRMED"


def fstr(value: Fraction) -> str:
    return str(value.numerator) if value.denominator == 1 else f"{value.numerator}/{value.denominator}"


def decimal(value: Fraction, places: int = 6) -> str:
    return f"{float(value):.{places}f}".rstrip("0").rstrip(".")


@dataclass(frozen=True)
class Ad9528SourceModel:
    vcxo_hz: Fraction
    pll1_mode: str
    candidate_output: str
    vcxo_direct_board_measured: bool


@dataclass(frozen=True)
class Ad9528Pll2Limits:
    # Rev. G provides the encoded maximum PFD and VCO/output limits.  No
    # additional unproven minimum PFD is invented; positive frequency is the
    # explicit computational floor and is reported as such.
    pll2_pfd_min_hz: Fraction
    pll2_pfd_max_hz: Fraction
    pll2_vco_min_hz: Fraction
    pll2_vco_max_hz: Fraction
    allowed_r1: tuple[int, ...]
    allowed_n2: tuple[int, ...]
    allowed_m1: tuple[int, ...]
    allowed_doubler: tuple[int, ...]
    allowed_out0_dividers: tuple[int, ...]
    out0_max_hz: Fraction


@dataclass(frozen=True)
class GtImplementationPath:
    name: str
    pll_type: str
    experimental: bool


@dataclass(frozen=True)
class RatePolicy:
    supported_rates_mbps: frozenset[int]
    fixed_3000_path: str
    fixed_3000_state: str
    fixed_3000_reason: str


@dataclass(frozen=True)
class Pll2Config:
    source: str
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
class GtTuple:
    pll_type: str
    refclk_div: int
    fbdiv_45: Optional[int]
    fbdiv: int
    txout_div: int
    vco_hz: Fraction
    line_rate_bps: Fraction


@dataclass(frozen=True)
class Candidate:
    candidate_name: str
    purpose: str
    source: str
    target_rate_mbps: str
    rate_path: str
    rate_state: str
    reason: str
    additional_gates: str
    out0_hz: str
    out0_mhz: str
    vcxo_hz: str
    pll1_mode: str
    doubler: int
    r1: int
    n2: int
    m1: int
    out0_div: int
    pll2_pfd_hz: str
    pll2_vco_hz: str
    gt_pll_type: str
    gt_refclk_div: int
    gt_fbdiv_45: str
    gt_fbdiv: int
    gt_txout_div: int
    gt_vco_hz: str
    line_rate_bps: str
    txusrclk_hz: str
    txusrclk2_hz: str
    expected_odiv2_count_1ms: str
    exact_target_match: int
    refclk_error_ppm: str
    distance_from_125m_hz: str
    pll2_pfd_margin_hz: str
    pll2_vco_margin_hz: str
    gt_vco_margin_hz: str
    uses_verified_gt_parameter_family: int
    requires_qpll: int
    requires_new_mmcm_profile: int
    ad9528_common_register_change_count: int
    ad9528_out0_register_change_count: int
    shared_clock_tree_risk: str
    measurement_resolution_sufficient: int
    board_measured: int
    board_verified: int


SOURCE_MODEL = Ad9528SourceModel(
    vcxo_hz=Fraction(122_880_000),
    pll1_mode="BYPASS_CONFIRMED_FOR_VCXO_DIRECT;PLL2_INPUT_ASSUMPTION_FROM_ADI_REFERENCE",
    candidate_output="OUT0",
    vcxo_direct_board_measured=True,
)

PLL2_LIMITS = Ad9528Pll2Limits(
    pll2_pfd_min_hz=Fraction(1),
    pll2_pfd_max_hz=Fraction(275_000_000),
    pll2_vco_min_hz=Fraction(3_450_000_000),
    pll2_vco_max_hz=Fraction(4_025_000_000),
    allowed_r1=tuple(range(1, 32)),
    allowed_n2=tuple(range(1, 257)),
    allowed_m1=(3, 4, 5),
    allowed_doubler=(1, 2),
    allowed_out0_dividers=tuple(range(1, 257)),
    out0_max_hz=Fraction(1_250_000_000),
)

RATE_POLICY = RatePolicy(
    supported_rates_mbps=frozenset(SUPPORTED_RATES_MBPS),
    fixed_3000_path=FIXED_125M_CPLL,
    fixed_3000_state=BLOCKED,
    fixed_3000_reason=NO_LEGAL_VERIFIED_125M_CPLL_PROFILE,
)

PATHS = {
    "CPLL": GtImplementationPath(AD9528_OUT0_CPLL_EXPERIMENTAL, "CPLL", True),
    "QPLL": GtImplementationPath(AD9528_OUT0_QPLL_EXPERIMENTAL, "QPLL", True),
}


def enumerate_pll2_configs(min_out0_hz: Fraction = Fraction(60_000_000),
                           max_out0_hz: Fraction = Fraction(200_000_000),
                           limits: Ad9528Pll2Limits = PLL2_LIMITS,
                           source: Ad9528SourceModel = SOURCE_MODEL) -> dict[Fraction, Pll2Config]:
    result: dict[Fraction, Pll2Config] = {}
    for doubler in limits.allowed_doubler:
        for r1 in limits.allowed_r1:
            pfd = source.vcxo_hz * doubler / r1
            if not limits.pll2_pfd_min_hz <= pfd <= limits.pll2_pfd_max_hz:
                continue
            for n2 in limits.allowed_n2:
                for m1 in limits.allowed_m1:
                    vco = pfd * n2 * m1
                    if not limits.pll2_vco_min_hz <= vco <= limits.pll2_vco_max_hz:
                        continue
                    distribution = vco / m1
                    for outdiv in limits.allowed_out0_dividers:
                        out0 = distribution / outdiv
                        if out0 < min_out0_hz:
                            break
                        if out0 > max_out0_hz or out0 > limits.out0_max_hz:
                            continue
                        config = Pll2Config(PLL2_SYNTHESIZED, source.vcxo_hz,
                                            source.pll1_mode, doubler, r1, n2,
                                            m1, outdiv, pfd, vco, out0)
                        old = result.get(out0)
                        key = (doubler, r1, n2, m1, outdiv)
                        old_key = None if old is None else (old.doubler, old.r1, old.n2, old.m1, old.out0_div)
                        if old is None or key < old_key:
                            result[out0] = config
    return result


def gt_tuples(refclk_hz: Fraction) -> Iterable[GtTuple]:
    refclk_mhz = refclk_hz / 1_000_000
    for m in CPLL_REFCLK_DIVS:
        for n1 in CPLL_FBDIV_45S:
            for n2 in CPLL_FBDIVS:
                vco_mhz = refclk_mhz * n1 * n2 / m
                for div in CPLL_TXOUT_DIVS:
                    line_mhz = 2 * vco_mhz / div
                    if not Fraction(1600) <= vco_mhz <= Fraction(3300):
                        continue
                    if gtx_line_rate_coverage_reason(line_mhz) is not None:
                        continue
                    if cpll_line_range_ok(line_mhz, div):
                        yield GtTuple("CPLL", m, n1, n2, div,
                                      vco_mhz * 1_000_000,
                                      line_mhz * 1_000_000)
    for m in QPLL_REFCLK_DIVS:
        for n in QPLL_FBDIVS:
            vco_mhz = refclk_mhz * n / m
            band = qpll_band(vco_mhz)
            if band is None:
                continue
            for div in QPLL_TXOUT_DIVS:
                line_mhz = vco_mhz / div
                if gtx_line_rate_coverage_reason(line_mhz) is not None:
                    continue
                if qpll_line_range_ok(line_mhz, div, band):
                    yield GtTuple("QPLL", m, None, n, div,
                                  vco_mhz * 1_000_000,
                                  line_mhz * 1_000_000)


def gt_vco_margin(gt: GtTuple) -> Fraction:
    if gt.pll_type == "CPLL":
        return min(gt.vco_hz - 1_600_000_000, 3_300_000_000 - gt.vco_hz)
    low, high = ((Fraction(5_930_000_000), Fraction(8_000_000_000))
                 if gt.vco_hz <= 8_000_000_000 else
                 (Fraction(9_800_000_000), Fraction(10_312_500_000)))
    return min(gt.vco_hz - low, high - gt.vco_hz)


def make_candidate(config: Pll2Config, gt: GtTuple, purpose: str) -> Candidate:
    line_mbps = gt.line_rate_bps / 1_000_000
    exact_3000 = line_mbps == 3000
    path = PATHS[gt.pll_type].name
    gates = [AD9528_PROFILE_NOT_IMPLEMENTED, GT_WIZARD_NOT_CONFIRMED,
             MMCM_PROFILE_NOT_CONFIRMED, AD9528_REGISTER_IMAGE_NOT_CONFIRMED,
             SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED]
    verified_family = int(gt.pll_type == "CPLL" and gt.refclk_div == 1 and
                          gt.fbdiv_45 == 4 and gt.fbdiv == 4)
    count = config.out0_hz / 2 / 1000
    # A low-risk TEST0 must be visible in the current 1 ms counter and clearly
    # distinguishable from a nominal 125 MHz input (62500 ODIV2 edges).
    measurement_ok = int(count.denominator == 1 and 1000 <= count <= 1_000_000
                         and abs(count - 62_500) >= 50)
    name_rate = decimal(line_mbps, 6).replace(".", "P")
    name_ref = decimal(config.out0_hz / 1_000_000, 6).replace(".", "P")
    return Candidate(
        candidate_name=f"PLL2_OUT0_{name_ref}_{gt.pll_type}_{name_rate}",
        purpose=purpose,
        source=PLL2_SYNTHESIZED,
        target_rate_mbps=decimal(line_mbps, 9),
        rate_path=path,
        rate_state=CANDIDATE,
        reason=LEGAL_NOT_IMPLEMENTED,
        additional_gates=";".join(gates),
        out0_hz=fstr(config.out0_hz), out0_mhz=decimal(config.out0_hz / 1_000_000, 9),
        vcxo_hz=fstr(config.vcxo_hz), pll1_mode=config.pll1_mode,
        doubler=config.doubler, r1=config.r1, n2=config.n2, m1=config.m1,
        out0_div=config.out0_div, pll2_pfd_hz=fstr(config.pfd_hz),
        pll2_vco_hz=fstr(config.vco_hz), gt_pll_type=gt.pll_type,
        gt_refclk_div=gt.refclk_div,
        gt_fbdiv_45="-" if gt.fbdiv_45 is None else str(gt.fbdiv_45),
        gt_fbdiv=gt.fbdiv, gt_txout_div=gt.txout_div,
        gt_vco_hz=fstr(gt.vco_hz), line_rate_bps=fstr(gt.line_rate_bps),
        txusrclk_hz=fstr(gt.line_rate_bps / 32),
        txusrclk2_hz=fstr(gt.line_rate_bps / 64),
        expected_odiv2_count_1ms=fstr(count), exact_target_match=int(exact_3000),
        refclk_error_ppm=decimal((config.out0_hz - 125_000_000) * 1_000_000 / 125_000_000, 6),
        distance_from_125m_hz=fstr(abs(config.out0_hz - 125_000_000)),
        pll2_pfd_margin_hz=fstr(min(config.pfd_hz - PLL2_LIMITS.pll2_pfd_min_hz,
                                    PLL2_LIMITS.pll2_pfd_max_hz - config.pfd_hz)),
        pll2_vco_margin_hz=fstr(min(config.vco_hz - PLL2_LIMITS.pll2_vco_min_hz,
                                    PLL2_LIMITS.pll2_vco_max_hz - config.vco_hz)),
        gt_vco_margin_hz=fstr(gt_vco_margin(gt)),
        uses_verified_gt_parameter_family=verified_family,
        requires_qpll=int(gt.pll_type == "QPLL"), requires_new_mmcm_profile=1,
        ad9528_common_register_change_count=9,
        ad9528_out0_register_change_count=3,
        shared_clock_tree_risk="HIGH_UNACCEPTED_PLL2_COMMON_CHANGE",
        measurement_resolution_sufficient=measurement_ok,
        board_measured=0, board_verified=0,
    )


def fixed_3000_blocked_row() -> dict[str, object]:
    return {
        "target_rate_mbps": 3000,
        "rate_path": FIXED_125M_CPLL,
        "rate_state": BLOCKED,
        "reason": NO_LEGAL_VERIFIED_125M_CPLL_PROFILE,
        "source": UNKNOWN_OR_UNCONFIRMED,
        "board_verified": False,
    }


def vcxo_direct_row() -> dict[str, object]:
    return {
        "candidate_name": "VCXO_122P88",
        "source": VCXO_DIRECT,
        "out0_hz": 122_880_000,
        "board_measured": True,
        "pll2_fine_step_candidate": False,
        "rate_state": CANDIDATE,
        "reason": REFERENCE_CLOCK_NOT_BOARD_CONNECTED,
        "board_verified": False,
    }


def vcxo_direct_candidate() -> Candidate:
    return Candidate(
        candidate_name="VCXO_122P88", purpose="MEASURED_CHAIN_BASELINE",
        source=VCXO_DIRECT, target_rate_mbps="0",
        rate_path=AD9528_OUT0_CPLL_EXPERIMENTAL, rate_state=CANDIDATE,
        reason=REFERENCE_CLOCK_NOT_BOARD_CONNECTED, additional_gates=NONE,
        out0_hz="122880000", out0_mhz="122.88", vcxo_hz="122880000",
        pll1_mode="BYPASS_CONFIRMED", doubler=0, r1=0, n2=0, m1=0,
        out0_div=1, pll2_pfd_hz="0", pll2_vco_hz="0",
        gt_pll_type="NONE", gt_refclk_div=0, gt_fbdiv_45="-",
        gt_fbdiv=0, gt_txout_div=0, gt_vco_hz="0", line_rate_bps="0",
        txusrclk_hz="0", txusrclk2_hz="0",
        expected_odiv2_count_1ms="61440", exact_target_match=0,
        refclk_error_ppm="-16960", distance_from_125m_hz="2120000",
        pll2_pfd_margin_hz="0", pll2_vco_margin_hz="0",
        gt_vco_margin_hz="0", uses_verified_gt_parameter_family=0,
        requires_qpll=0, requires_new_mmcm_profile=0,
        ad9528_common_register_change_count=4,
        ad9528_out0_register_change_count=3,
        shared_clock_tree_risk="VCXO_DIRECT_SHARED_FIELDS_RESTORED",
        measurement_resolution_sufficient=1, board_measured=1,
        board_verified=0,
    )


@lru_cache(maxsize=1)
def generate_candidates() -> tuple[list[Candidate], list[Candidate], list[Candidate]]:
    configs = enumerate_pll2_configs()
    all_rows: list[Candidate] = []
    for out0, config in configs.items():
        near_125 = abs(out0 - 125_000_000) <= 5_000_000
        for gt in gt_tuples(out0):
            exact_3000 = gt.line_rate_bps == 3_000_000_000
            verified_family = (gt.pll_type == "CPLL" and gt.refclk_div == 1 and
                               gt.fbdiv_45 == 4 and gt.fbdiv == 4)
            if exact_3000:
                all_rows.append(make_candidate(config, gt, "EXACT_3000M_EXPERIMENT"))
            elif near_125 and verified_family:
                all_rows.append(make_candidate(config, gt, "OUT0_PLL2_MEASUREMENT_ONLY"))
    # De-duplicate implementation paths, keeping one canonical AD9528 image per
    # exact OUT0/GT tuple.
    unique: dict[tuple[object, ...], Candidate] = {}
    for row in all_rows:
        key = (row.out0_hz, row.rate_path, row.gt_refclk_div, row.gt_fbdiv_45,
               row.gt_fbdiv, row.gt_txout_div, row.target_rate_mbps)
        unique.setdefault(key, row)
    rows = sorted(unique.values(), key=lambda r: (
        Fraction(r.out0_hz), r.rate_path, Fraction(r.line_rate_bps),
        r.gt_refclk_div, r.gt_txout_div))
    low_all = [r for r in rows if r.purpose == "OUT0_PLL2_MEASUREMENT_ONLY"]
    low_all.sort(key=lambda r: (
        -r.measurement_resolution_sufficient,
        Fraction(r.distance_from_125m_hz), -r.uses_verified_gt_parameter_family,
        r.requires_qpll, -Fraction(r.pll2_vco_margin_hz), r.candidate_name))
    low = low_all[:20]
    preferred = next((r for r in low_all if r.out0_hz == "124800000" and
                      r.gt_pll_type == "CPLL" and r.gt_refclk_div == 1 and
                      r.gt_fbdiv_45 == "4" and r.gt_fbdiv == 4 and
                      r.gt_txout_div == 4), None)
    if preferred is not None and preferred not in low:
        low[-1] = preferred
        low.sort(key=lambda r: (
            -r.measurement_resolution_sufficient,
            Fraction(r.distance_from_125m_hz), -r.uses_verified_gt_parameter_family,
            r.requires_qpll, -Fraction(r.pll2_vco_margin_hz), r.candidate_name))
    exact = [r for r in rows if r.exact_target_match]
    exact.sort(key=lambda r: (
        r.requires_qpll, Fraction(r.distance_from_125m_hz),
        -Fraction(r.pll2_vco_margin_hz), r.candidate_name))
    return [vcxo_direct_candidate()] + rows, low, exact


def write_csv(path: Path, rows: list[Candidate]) -> None:
    fields = list(Candidate.__annotations__)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)


def recommendation(low: list[Candidate], exact: list[Candidate]) -> dict[str, object]:
    preferred = next((r for r in low if r.out0_hz == "124800000" and
                      r.gt_pll_type == "CPLL" and r.gt_refclk_div == 1 and
                      r.gt_fbdiv_45 == "4" and r.gt_fbdiv == 4 and
                      r.gt_txout_div == 4), low[0] if low else None)
    base = {
        "decision": "NO_SAFE_PLL2_TEST0_CANDIDATE",
        "reason_codes": [AD9528_REGISTER_IMAGE_NOT_CONFIRMED,
                         SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED],
        "candidate_name": "NO_SAFE_PLL2_TEST0_CANDIDATE",
        "purpose": "OUT0_PLL2_MEASUREMENT_ONLY",
        "target_out0_hz": 0,
        "target_line_rate_bps": 0,
        "rate_path": AD9528_OUT0_CPLL_EXPERIMENTAL,
        "rate_state": BLOCKED,
        "ad9528": {"vcxo_hz": 122_880_000, "r1": 0, "n2": 0,
                   "m1": 0, "out0_div": 0},
        "gt": {"pll_type": "CPLL", "refclk_div": 0, "fbdiv": 0,
               "fbdiv_45": 0, "txout_div": 0},
        "requires_new_mmcm_profile": True,
        "board_verified": False,
        "fixed_3000_policy": fixed_3000_blocked_row(),
        "low_risk_shortlist_count": len(low),
        "exact_3000_shortlist_count": len(exact),
    }
    if preferred is not None:
        base["preferred_candidate_pending_gates"] = {
            "candidate_name": "PLL2_TEST0_OUT0_124P8_CPLL_998P4",
            "target_out0_hz": int(Fraction(preferred.out0_hz)),
            "target_line_rate_bps": int(Fraction(preferred.line_rate_bps)),
            "rate_path": preferred.rate_path,
            "rate_state": CANDIDATE,
            "reason": preferred.reason,
            "additional_gates": preferred.additional_gates.split(";"),
            "ad9528": {"vcxo_hz": int(Fraction(preferred.vcxo_hz)),
                       "doubler": preferred.doubler, "r1": preferred.r1,
                       "n2": preferred.n2, "m1": preferred.m1,
                       "out0_div": preferred.out0_div},
            "gt": {"pll_type": preferred.gt_pll_type,
                   "refclk_div": preferred.gt_refclk_div,
                   "fbdiv": preferred.gt_fbdiv,
                   "fbdiv_45": int(preferred.gt_fbdiv_45),
                   "txout_div": preferred.gt_txout_div},
            "expected_odiv2_count_1ms": int(Fraction(preferred.expected_odiv2_count_1ms)),
            "requires_new_mmcm_profile": True,
            "board_verified": False,
        }
    return base


def generate(output_dir: Path) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)
    rows, low, exact = generate_candidates()
    write_csv(output_dir / "all_candidates.csv", rows)
    write_csv(output_dir / "low_risk_shortlist.csv", low)
    write_csv(output_dir / "exact_3000m_shortlist.csv", exact)
    result = recommendation(low, exact)
    (output_dir / "recommended_test0.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary = [
        "AD9528 PLL2 fine-step TEST0 planning summary",
        f"all_candidates={len(rows)}",
        f"low_risk_shortlist={len(low)}",
        f"exact_3000m_shortlist={len(exact)}",
        f"decision={result['decision']}",
        "fixed_3000_path=FIXED_125M_CPLL",
        "fixed_3000_state=BLOCKED",
        "fixed_3000_reason=NO_LEGAL_VERIFIED_125M_CPLL_PROFILE",
        "vcxo_122p88_source=VCXO_DIRECT",
        "vcxo_122p88_board_measured=1",
        "vcxo_122p88_pll2_fine_step_candidate=0",
    ]
    preferred = result.get("preferred_candidate_pending_gates")
    if preferred:
        summary += [
            f"preferred_pending={preferred['candidate_name']}",
            f"preferred_out0_hz={preferred['target_out0_hz']}",
            f"preferred_line_rate_bps={preferred['target_line_rate_bps']}",
        ]
    (output_dir / "generation_summary.txt").write_text(
        "\n".join(summary) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path,
                        default=Path("reports/ad9528_fine_step_test0"))
    args = parser.parse_args()
    result = generate(args.output_dir)
    print(f"PASS: decision={result['decision']} output={args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

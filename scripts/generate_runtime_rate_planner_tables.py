#!/usr/bin/env python3
"""Generate deterministic AD9528/GT/MMCM runtime-planner tables.

The generator reuses the repository's Fraction-based legality model.  It does
not create target-rate profiles and it does not modify Vivado/Vitis projects.
Unconfirmed GT DRP encodings remain present for diagnostics but are marked
non-executable.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from fractions import Fraction
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from enumerate_ad9528_gt_refclk_candidates import (  # noqa: E402
    PLL2_LIMITS,
    enumerate_pll2_configs,
)
from enumerate_gtx_rate_candidates import (  # noqa: E402
    CPLL_FBDIVS,
    CPLL_FBDIV_45S,
    CPLL_REFCLK_DIVS,
    CPLL_TXOUT_DIVS,
    QPLL_FBDIVS,
    QPLL_REFCLK_DIVS,
    QPLL_TXOUT_DIVS,
)
from generate_625m_4000m_mmcm_drp_candidates import (  # noqa: E402
    ADDRS,
    MmcmProfile,
    sequence,
)

GENERATOR_VERSION = 1
AD9528_MIN_OUT0_HZ = Fraction(60_000_000)
AD9528_MAX_OUT0_HZ = Fraction(200_000_000)
MMCM_VCO_MIN_HZ = 600_000_000
MMCM_VCO_MAX_HZ = 1_200_000_000
MMCM_MAX_MULT = 64


@dataclass(frozen=True)
class GtTupleRecord:
    pll_type: int
    refclk_div: int
    fbdiv_45: int
    fbdiv: int
    txout_div: int
    qpll_fbdiv_ratio: int
    cpll_refclk_div_encoding: int
    cpll_fbdiv_45_encoding: int
    cpll_fbdiv_encoding: int
    txout_div_encoding: int
    drp_encoding_confirmed: int


def cpll_refclk_encoding(divider: int) -> int:
    # Only divide-by-1 is traced to the active GTXE2 DRP implementation.
    return 0x10 if divider == 1 else 0


def cpll_fbdiv_encoding(divider: int) -> int:
    # Active hardware confirms N2=4 -> 2 and N2=5 -> 3.  Other legal
    # mathematical values deliberately remain non-executable.
    return {4: 0x02, 5: 0x03}.get(divider, 0)


def txout_div_encoding(divider: int) -> int:
    return {1: 0, 2: 1, 4: 2, 8: 3, 16: 4}[divider]


def gt_records() -> list[GtTupleRecord]:
    records: list[GtTupleRecord] = []
    for refdiv in CPLL_REFCLK_DIVS:
        for fb45 in CPLL_FBDIV_45S:
            for fbdiv in CPLL_FBDIVS:
                for outdiv in CPLL_TXOUT_DIVS:
                    confirmed = int(refdiv == 1 and fb45 in (4, 5) and fbdiv in (4, 5))
                    records.append(GtTupleRecord(
                        0, refdiv, fb45, fbdiv, outdiv, 0,
                        cpll_refclk_encoding(refdiv), int(fb45 == 5),
                        cpll_fbdiv_encoding(fbdiv), txout_div_encoding(outdiv),
                        confirmed))
    for refdiv in QPLL_REFCLK_DIVS:
        for fbdiv in QPLL_FBDIVS:
            for outdiv in QPLL_TXOUT_DIVS:
                confirmed = int(refdiv == 1 and fbdiv == 80)
                records.append(GtTupleRecord(
                    1, refdiv, 0, fbdiv, outdiv, int(fbdiv != 66),
                    0, 0, 0, txout_div_encoding(outdiv), confirmed))
    return records


def mmcm_profiles() -> list[tuple[int, list[dict[str, int]]]]:
    result: list[tuple[int, list[dict[str, int]]]] = []
    for mult in range(2, MMCM_MAX_MULT + 1):
        profile = MmcmProfile(
            label=f"runtime_mult_{mult}", line_rate_mbps=0,
            clkin_mhz=1.0, clkin_period_ns=1.0,
            divclk_divide=1, clkfbout_mult=mult,
            clkout0_divide=2 * mult, clkout1_divide=mult)
        result.append((mult, sequence(profile)))
    return result


def write_ad9528(output: Path) -> int:
    configs = sorted(enumerate_pll2_configs(
        AD9528_MIN_OUT0_HZ, AD9528_MAX_OUT0_HZ).values(),
        key=lambda c: (c.out0_hz, c.doubler, c.r1, c.n2, c.m1, c.out0_div))
    header = """#ifndef RUNTIME_AD9528_CONFIGS_H
#define RUNTIME_AD9528_CONFIGS_H
#include <stddef.h>
#include <stdint.h>
typedef struct {
    uint32_t out0_hz, pfd_hz, vco_hz, expected_odiv2_count_1ms;
    uint32_t vco_lower_margin_hz, vco_upper_margin_hz;
    uint16_t n2, out0_div, register_plan_id;
    uint8_t doubler, r1, m1, executable_register_encoding;
} RuntimeAd9528Config;
extern const RuntimeAd9528Config runtime_ad9528_configs[];
extern const size_t runtime_ad9528_config_count;
#endif
"""
    rows = []
    for plan_id, c in enumerate(configs):
        def rounded(value: Fraction) -> int:
            return (value.numerator + value.denominator // 2) // value.denominator

        # The current reference register plan confirms the non-doubled path.
        # Fractional-Hz mathematical results are still exactly recoverable in
        # C from VCXO*doubler*N2/(R1*OUT_DIV); rounded fields are display and
        # binary-search keys only.
        executable = int(c.doubler == 1)
        rows.append(
            "    {%uU,%uU,%uU,%uU,%uU,%uU,%uU,%uU,%uU,%uU,%uU,%uU,%uU}," % (
                rounded(c.out0_hz), rounded(c.pfd_hz), rounded(c.vco_hz),
                rounded(c.out0_hz / 2000),
                rounded(c.vco_hz - PLL2_LIMITS.pll2_vco_min_hz),
                rounded(PLL2_LIMITS.pll2_vco_max_hz - c.vco_hz),
                c.n2, c.out0_div, plan_id, c.doubler, c.r1, c.m1,
                executable))
    source = '#include "runtime_ad9528_configs.h"\nconst RuntimeAd9528Config runtime_ad9528_configs[] = {\n' + "\n".join(rows) + "\n};\nconst size_t runtime_ad9528_config_count = sizeof(runtime_ad9528_configs)/sizeof(runtime_ad9528_configs[0]);\n"
    (output / "runtime_ad9528_configs.h").write_text(header, encoding="utf-8")
    (output / "runtime_ad9528_configs.c").write_text(source, encoding="utf-8")
    return len(configs)


def write_gt(output: Path) -> tuple[int, int, int]:
    records = gt_records()
    header = """#ifndef RUNTIME_GT_TUPLES_H
#define RUNTIME_GT_TUPLES_H
#include <stddef.h>
#include <stdint.h>
enum { RUNTIME_PLL_CPLL=0, RUNTIME_PLL_QPLL=1 };
typedef struct {
    uint8_t pll_type, refclk_div, fbdiv_45, fbdiv, txout_div;
    uint8_t qpll_fbdiv_ratio, cpll_refclk_div_encoding;
    uint8_t cpll_fbdiv_45_encoding, cpll_fbdiv_encoding;
    uint8_t txout_div_encoding, drp_encoding_confirmed;
} RuntimeGtTuple;
extern const RuntimeGtTuple runtime_gt_tuples[];
extern const size_t runtime_gt_tuple_count;
#endif
"""
    rows = ["    {%dU,%dU,%dU,%dU,%dU,%dU,%dU,%dU,%dU,%dU,%dU}," % tuple(asdict(r).values()) for r in records]
    source = '#include "runtime_gt_tuples.h"\nconst RuntimeGtTuple runtime_gt_tuples[] = {\n' + "\n".join(rows) + "\n};\nconst size_t runtime_gt_tuple_count = sizeof(runtime_gt_tuples)/sizeof(runtime_gt_tuples[0]);\n"
    (output / "runtime_gt_tuples.h").write_text(header, encoding="utf-8")
    (output / "runtime_gt_tuples.c").write_text(source, encoding="utf-8")
    return len(records), sum(r.pll_type == 0 for r in records), sum(r.pll_type == 1 for r in records)


def write_mmcm(output: Path) -> int:
    profiles = mmcm_profiles()
    header = """#ifndef RUNTIME_MMCM_RECIPES_H
#define RUNTIME_MMCM_RECIPES_H
#include <stddef.h>
#include <stdint.h>
#define RUNTIME_MMCM_WRITE_COUNT 15U
typedef struct { uint8_t address; uint16_t value; } RuntimeMmcmWrite;
typedef struct { uint8_t mult; RuntimeMmcmWrite writes[RUNTIME_MMCM_WRITE_COUNT]; } RuntimeMmcmRecipe;
extern const RuntimeMmcmRecipe runtime_mmcm_recipes[];
extern const size_t runtime_mmcm_recipe_count;
#endif
"""
    rows = []
    for mult, writes in profiles:
        encoded = ",".join("{%uU,0x%04xU}" % (w["address"], w["value"]) for w in writes)
        rows.append("    {%uU,{%s}}," % (mult, encoded))
    source = '#include "runtime_mmcm_recipes.h"\nconst RuntimeMmcmRecipe runtime_mmcm_recipes[] = {\n' + "\n".join(rows) + "\n};\nconst size_t runtime_mmcm_recipe_count = sizeof(runtime_mmcm_recipes)/sizeof(runtime_mmcm_recipes[0]);\n"
    (output / "runtime_mmcm_recipes.h").write_text(header, encoding="utf-8")
    (output / "runtime_mmcm_recipes.c").write_text(source, encoding="utf-8")
    return len(profiles)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("generated"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    ad_count = write_ad9528(args.output_dir)
    gt_count, cpll_count, qpll_count = write_gt(args.output_dir)
    mmcm_count = write_mmcm(args.output_dir)
    manifest = {
        "generator_version": GENERATOR_VERSION,
        "source_models": [
            "enumerate_ad9528_gt_refclk_candidates.py",
            "enumerate_gtx_rate_candidates.py",
            "generate_625m_4000m_mmcm_drp_candidates.py",
            "Vitis 2022.2 xvphy_mmcme2.c/XAPP888 encoding"],
        "ad9528_config_count": ad_count,
        "gt_tuple_count": gt_count,
        "cpll_tuple_count": cpll_count,
        "qpll_tuple_count": qpll_count,
        "mmcm_recipe_count": mmcm_count,
        "mmcm_write_count": len(ADDRS),
        "ad9528_out0_min_hz": int(AD9528_MIN_OUT0_HZ),
        "ad9528_out0_max_hz": int(AD9528_MAX_OUT0_HZ),
        "fixed_3000m_cpll_state": "BLOCKED",
        "fixed_3000m_cpll_reason": "NO_LEGAL_VERIFIED_125M_CPLL_PROFILE",
        "target_profiles_generated": 0,
    }
    (args.output_dir / "runtime_rate_planner_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

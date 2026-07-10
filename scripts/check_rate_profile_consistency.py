#!/usr/bin/env python3
"""Read-only consistency check for the Vitis discrete profile table and RTL IDs."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
GPIO_H = ROOT / "vitis_bringup/bringup/src/laser_gpio.h"
PLAN_C = ROOT / "vitis_bringup/bringup/src/gt_rate_plan.c"
PLAN_H = ROOT / "vitis_bringup/bringup/src/gt_rate_plan.h"
RTL_V = ROOT / "laser_tx.srcs/sources_1/new/laser_gt_rate_switch_500m_1000m.v"

EXPECTED = [
    ("500M", 1, 500, "CPLL"),
    ("1000M", 2, 1000, "CPLL"),
    ("2000M", 3, 2000, "CPLL"),
    ("1250M", 4, 1250, "CPLL"),
    ("2500M", 5, 2500, "CPLL"),
    ("5000M", 6, 5000, "CPLL"),
    ("3125M", 7, 3125, "CPLL"),
    ("6250M", 8, 6250, "CPLL"),
    ("10000M", 9, 10000, "QPLL"),
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    gpio_h = read(GPIO_H)
    plan_c = read(PLAN_C)
    plan_h = read(PLAN_H)
    rtl_v = read(RTL_V)

    for suffix, rate_id, _, _ in EXPECTED:
        sw = re.search(rf"#define\s+LASER_RATE_ID_{suffix}\s+(\d+)U", gpio_h)
        hw = re.search(rf"localparam\s+\[3:0\]\s+RATE_ID_{suffix}\s*=\s*4'd(\d+)", rtl_v)
        require(sw is not None, f"missing software RATE_ID_{suffix}")
        require(hw is not None, f"missing RTL RATE_ID_{suffix}")
        require(int(sw.group(1)) == rate_id, f"software RATE_ID_{suffix} mismatch")
        require(int(hw.group(1)) == rate_id, f"RTL RATE_ID_{suffix} mismatch")

    table = plan_c.split("static const GtRateProfile gt_rate_profile_table", 1)[1].split("};", 1)[0]
    rows = re.findall(
        r"\{(\d+)U,\s*LASER_RATE_ID_(\d+M),\s*GT_RATE_PLL_(CPLL|QPLL).*?\}\s*,?",
        table,
        flags=re.DOTALL,
    )
    rates = [int(row[0]) for row in rows]
    require(rates == sorted(rates), "profile table is not ascending by rate_mbps")
    require(rates == [500, 1000, 1250, 2000, 2500, 3125, 5000, 6250, 10000],
            "profile table does not contain the nine supported rates")
    require(len(set(rates)) == len(rates), "duplicate profile rate")
    require(3000 not in rates, "blocked 3000M entered supported table")
    require(rows[-1][2] == "QPLL", "10000M must use QPLL")
    require(all(row[2] == "CPLL" for row in rows[:-1]), "non-10G profile must use CPLL")
    windows = re.findall(
        r"\{(\d+)U,\s*LASER_RATE_ID_\d+M,\s*GT_RATE_PLL_(?:CPLL|QPLL),\s*125000000U,\s*"
        r"(\d+)U,\s*(\d+)U,\s*(\d+)U,",
        table,
        flags=re.DOTALL,
    )
    require(len(windows) == len(rows), "could not parse every counter window")
    for rate, expected_hz, minimum, maximum in windows:
        expected_count = int(expected_hz) // 1000
        require(int(minimum) <= expected_count <= int(maximum),
                f"{rate}M expected counter is outside its window")
    require("freq_counter_min" in plan_h and "freq_counter_max" in plan_h,
            "counter window fields missing")
    print("PASS: rate profile consistency (RTL IDs, Vitis IDs, order, PLL type, 3000M exclusion)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, IndexError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

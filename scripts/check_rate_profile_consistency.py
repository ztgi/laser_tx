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
    ("500M", 1, 500, "CPLL", 1),
    ("1000M", 2, 1000, "CPLL", 1),
    ("2000M", 3, 2000, "CPLL", 1),
    ("1250M", 4, 1250, "CPLL", 1),
    ("2500M", 5, 2500, "CPLL", 1),
    ("5000M", 6, 5000, "CPLL", 1),
    ("3125M", 7, 3125, "CPLL", 1),
    ("6250M", 8, 6250, "CPLL", 1),
    ("10000M", 9, 10000, "QPLL", 1),
    ("625M", 10, 625, "CPLL", 0),
    ("4000M", 11, 4000, "CPLL", 0),
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

    for suffix, rate_id, _, _, _ in EXPECTED:
        sw = re.search(rf"#define\s+LASER_RATE_ID_{suffix}\s+(\d+)U", gpio_h)
        hw = re.search(rf"localparam\s+\[3:0\]\s+RATE_ID_{suffix}\s*=\s*4'd(\d+)", rtl_v)
        require(sw is not None, f"missing software RATE_ID_{suffix}")
        require(hw is not None, f"missing RTL RATE_ID_{suffix}")
        require(int(sw.group(1)) == rate_id, f"software RATE_ID_{suffix} mismatch")
        require(int(hw.group(1)) == rate_id, f"RTL RATE_ID_{suffix} mismatch")

    table = plan_c.split("static const GtRateProfile gt_rate_profile_table", 1)[1].split("};", 1)[0]
    rows = re.findall(
        r"\.rate_mbps\s*=\s*(\d+)U,\s*\.rate_id\s*=\s*LASER_RATE_ID_(\d+M),\s*"
        r"\.pll_source\s*=\s*GT_RATE_PLL_(CPLL|QPLL).*?"
        r"\.expected_txusrclk2_hz\s*=\s*(\d+)U,\s*"
        r"\.freq_counter_min\s*=\s*(\d+)U,\s*\.freq_counter_max\s*=\s*(\d+)U.*?"
        r"\.board_verified\s*=\s*(\d+)U",
        table,
        flags=re.DOTALL,
    )
    rates = [int(row[0]) for row in rows]
    require(rates == sorted(rates), "profile table is not ascending by rate_mbps")
    require(rates == [500, 625, 1000, 1250, 2000, 2500, 3125, 4000, 5000, 6250, 10000],
            "profile table does not contain the verified and candidate rates")
    require(len(set(rates)) == len(rates), "duplicate profile rate")
    require(3000 not in rates, "blocked 3000M entered supported table")
    require(rows[-1][2] == "QPLL", "10000M must use QPLL")
    require(all(row[2] == "CPLL" for row in rows[:-1]), "non-10G profile must use CPLL")
    candidate_rows = {int(row[0]): int(row[6]) for row in rows}
    require(candidate_rows[625] == 0 and candidate_rows[4000] == 0,
            "625M/4000M must remain board-unverified candidates")
    require(all(candidate_rows[rate] == 1 for rate in rates if rate not in (625, 4000)),
            "verified profile unexpectedly marked as candidate")
    for rate, _, _, expected_hz, minimum, maximum, _ in rows:
        expected_count = int(expected_hz) // 1000
        require(int(minimum) <= expected_count <= int(maximum),
                f"{rate}M expected counter is outside its window")
    require("freq_counter_min" in plan_h and "freq_counter_max" in plan_h,
            "counter window fields missing")
    require("sizeof(gt_rate_profile_table)" in plan_c,
            "profile count must be derived from the array")
    require("gt_blocked_rate_table" in plan_c and "{3000U," in plan_c,
            "3000M blocked reason table missing")
    require("fixed 125MHz CPLL profiles only" not in read(ROOT / "vitis_bringup/bringup/src/laser_udp_server.c"),
            "stale CPLL-only startup banner remains")
    udp_c = read(ROOT / "vitis_bringup/bringup/src/laser_udp_server.c")
    require("format_rate_list(response, response_size)" in udp_c,
            "rate list is not sourced from the profile table")
    require("if (profile->board_verified == 0U)" in udp_c,
            "rate list/startup output does not filter candidate profiles")
    require("rate candidate set <Mbps>" in udp_c and
            "ERROR RATE_SET_UNSUPPORTED" in udp_c,
            "candidate bring-up or ordinary rate-set gating is missing")
    print("PASS: rate profile consistency (RTL IDs, Vitis IDs, order, PLL type, candidate gating, 3000M exclusion)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, IndexError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

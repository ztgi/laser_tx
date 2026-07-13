#!/usr/bin/env python3
"""Static consistency and algorithm checks for AD9528 measurement readback."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RTL = (ROOT / "rtl/laser_tx_board_top.v").read_text(encoding="utf-8")
HDR = (ROOT / "vitis_bringup/bringup/src/laser_ad9528_measure.h").read_text(encoding="utf-8")


def rtl_int(name: str) -> int:
    match = re.search(rf"{name}\s*=\s*(?:\d+'d)?(\d+)", RTL)
    assert match, f"missing RTL constant {name}"
    return int(match.group(1))


def c_int(name: str) -> int:
    match = re.search(rf"#define\s+{name}\s+(\d+)U", HDR)
    assert match, f"missing C constant {name}"
    return int(match.group(1))


pairs = {
    "AD9528_MEASURE_GT_CTRL_CLK_HZ": "LASER_AD9528_MEASURE_GT_CTRL_CLK_HZ",
    "AD9528_MEASURE_WINDOW_US": "LASER_AD9528_MEASURE_WINDOW_US",
    "AD9528_MEASURE_CYCLES": "LASER_AD9528_MEASURE_WINDOW_CYCLES",
    "AD9528_ODIV2_DIVIDE_FACTOR": "LASER_AD9528_MEASURE_ODIV2_FACTOR",
    "AD9528_MEASURE_FORMAT_VERSION": "LASER_AD9528_MEASURE_FORMAT_VERSION",
    "AD9528_ODIV2_COUNT_MIN": "LASER_AD9528_MEASURE_COUNT_MIN",
    "AD9528_ODIV2_COUNT_MAX": "LASER_AD9528_MEASURE_COUNT_MAX",
}
for rtl_name, c_name in pairs.items():
    assert rtl_int(rtl_name) == c_int(c_name), (rtl_name, c_name)
assert rtl_int("AD9528_MEASURE_CYCLES") * 1_000_000 == \
       rtl_int("AD9528_MEASURE_GT_CTRL_CLK_HZ") * rtl_int("AD9528_MEASURE_WINDOW_US")


def status(sequence: int, valid: int, in_range: int, alive: int, version: int = 1) -> int:
    return ((sequence & 0xFFFF) << 16) | ((version & 0xF) << 4) | \
           ((alive & 1) << 2) | ((in_range & 1) << 1) | (valid & 1)


def coherent_read(samples):
    """Model status-before/count/status-after retry behavior."""
    for before, count, after in samples[:4]:
        if (before >> 16) != (after >> 16):
            continue
        if ((after >> 4) & 0xF) != 1:
            return "FORMAT_ERROR", None
        if not (after & 1):
            return "NOT_VALID", None
        return ("VALID_IN_RANGE" if after & 2 else "VALID_OUT_OF_RANGE"), count
    return "READ_ERROR", None

s7 = status(7, 1, 1, 1)
assert coherent_read([(s7, 61437, s7)]) == ("VALID_IN_RANGE", 61437)
s8 = status(8, 1, 1, 1)
assert coherent_read([(s7, 61437, s8), (s8, 61440, s8)]) == ("VALID_IN_RANGE", 61440)
assert coherent_read([(status(9, 0, 0, 1), 0, status(9, 0, 0, 1))]) == ("NOT_VALID", None)
assert coherent_read([(status(10, 1, 0, 1), 82883, status(10, 1, 0, 1))]) == ("VALID_OUT_OF_RANGE", 82883)
assert coherent_read([(status(11, 1, 1, 1, 2), 61440, status(11, 1, 1, 1, 2))]) == ("FORMAT_ERROR", None)
assert 61437 * 1000 == 61_437_000
assert 61437 * 1000 * 2 == 122_874_000
assert (0xFFFFFFFF * 1000 * 2) > 0xFFFFFFFF  # requires uint64_t
# Transition invalidation: the old sequence is rejected until a new window.
transition_sequence = 12
assert (status(transition_sequence, 1, 1, 1) >> 16) == transition_sequence
assert (status(transition_sequence + 1, 1, 1, 1) >> 16) != transition_sequence
print("PASS: AD9528 measurement constants and coherent-read scenarios")
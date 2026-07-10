#!/usr/bin/env python3
"""Generate isolated MMCM DRP candidate sequences using XVPHY MMCME2 encoding.

This is a direct, integer-only transcription of the divider, LOCK and FILTER
encoders in Vitis 2022.2 xvphy_mmcme2.c (XAPP888 method).  It emits candidate
files only; it never edits the main RTL MMCM sequence table.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path


ADDRS = (0x28, 0x14, 0x15, 0x16, 0x08, 0x09, 0x0A, 0x0B,
         0x0C, 0x0D, 0x18, 0x19, 0x1A, 0x4E, 0x4F)


@dataclass(frozen=True)
class MmcmProfile:
    label: str
    line_rate_mbps: int
    clkin_mhz: float
    clkin_period_ns: float
    divclk_divide: int
    clkfbout_mult: int
    clkout0_divide: int
    clkout1_divide: int
    clkout2_divide: int = 1


PROFILES = (
    # Extracted from the isolated 625M Wizard user-clock helper.  It chooses
    # the legal 605.46875MHz VCO solution rather than the initial 32/64/32
    # mathematical candidate.
    MmcmProfile("625m", 625, 19.53125, 51.2, 1, 31, 62, 31),
    # Extracted from the isolated 4000M Wizard user-clock helper.
    MmcmProfile("4000m", 4000, 125.0, 8.0, 1, 5, 10, 5),
)


def divider_encoding(div_type: str, div: int) -> tuple[int, int]:
    if div == 1:
        return 0x1041, 0x00C0
    high = div // 2
    low = div - high
    reg1 = (low & 0x3F) | ((high & 0x3F) << 6)
    if div_type != "divclk":
        reg1 |= 0x1000
    return reg1, 0x0080 if div % 2 else 0x0000


def lock_reg1(mult: int) -> int:
    if mult <= 10: return 0x01E8
    values = {11: 0x0184, 12: 0x0139, 13: 0x01EE, 14: 0x01BC, 15: 0x018A,
              16: 0x0171, 17: 0x013F, 18: 0x0126, 19: 0x010D, 20: 0x00F4,
              21: 0x00DB, 22: 0x00C2, 23: 0x00A9, 24: 0x0090, 25: 0x0090,
              26: 0x0077, 27: 0x005E, 28: 0x005E, 29: 0x0045, 30: 0x0045,
              31: 0x002C, 32: 0x002C, 33: 0x002C, 34: 0x0013, 35: 0x0013,
              36: 0x0013}
    return values.get(mult, 0x00FA)


def lock_reg2(mult: int) -> int:
    return {1: 0x1801, 2: 0x1801, 3: 0x2001, 4: 0x2C01, 5: 0x3801,
            6: 0x4401, 7: 0x4C01, 8: 0x5801, 9: 0x6401, 10: 0x7001}.get(mult, 0x7C01)


def lock_reg3(mult: int) -> int:
    return {1: 0x19E9, 2: 0x19E9, 3: 0x21E9, 4: 0x2DE9, 5: 0x39E9,
            6: 0x45E9, 7: 0x4DE9, 8: 0x59E9, 9: 0x65E9, 10: 0x71E9}.get(mult, 0x7DE9)


def filter_reg2(mult: int) -> int:
    # TxIsPlle2 is false for this GTX/MMCME2 user-clock path.
    if mult <= 2: return 0x9900
    if mult == 3: return 0x9900
    if mult == 4: return 0x9900
    if mult == 5: return 0x1900
    if mult == 6: return 0x8900
    if mult == 7: return 0x9100
    if mult == 8: return 0x0900
    if mult == 9: return 0x1100
    if mult == 10: return 0x1100
    if 11 <= mult <= 15: return 0x9800
    if 16 <= mult <= 18: return 0x0100
    if 19 <= mult <= 25: return 0x1800
    if 26 <= mult <= 30: return 0x8800
    if 31 <= mult <= 40: return 0x9000
    return 0x0800


def sequence(profile: MmcmProfile) -> list[dict[str, int]]:
    fb1, fb2 = divider_encoding("clkout", profile.clkfbout_mult)
    div1, _ = divider_encoding("divclk", profile.divclk_divide)
    out0_1, out0_2 = divider_encoding("clkout", profile.clkout0_divide)
    out1_1, out1_2 = divider_encoding("clkout", profile.clkout1_divide)
    out2_1, out2_2 = divider_encoding("clkout", profile.clkout2_divide)
    values = (0xFFFF, fb1, fb2, div1, out0_1, out0_2, out1_1, out1_2,
              out2_1, out2_2, lock_reg1(profile.clkfbout_mult),
              lock_reg2(profile.clkfbout_mult), lock_reg3(profile.clkfbout_mult),
              0x0800, filter_reg2(profile.clkfbout_mult))
    return [{"address": addr, "value": value} for addr, value in zip(ADDRS, values)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for profile in PROFILES:
        vco = profile.clkin_mhz * profile.clkfbout_mult / profile.divclk_divide
        payload = {
            "source": "Vitis 2022.2 xvphy_mmcme2.c / XAPP888 integer encoding",
            "profile": asdict(profile),
            "mmcm_vco_mhz": vco,
            "txusrclk_mhz": profile.clkin_mhz * profile.clkfbout_mult / profile.clkout1_divide,
            "txusrclk2_mhz": profile.clkin_mhz * profile.clkfbout_mult / profile.clkout0_divide,
            "sequence": sequence(profile),
        }
        path = args.output_dir / f"{profile.label}_mmcm_drp_candidate.json"
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"PASS: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

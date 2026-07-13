#!/usr/bin/env python3
"""Compare two non-executable AD9528 PLL2 TEST0 register plans.

The input is a UART ``ad9528 dump full`` capture.  This tool only parses the
captured bytes and emits review artifacts; it never accesses AD9528 hardware
and deliberately refuses to emit an executable C initializer while any
critical safety gate remains open.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import asdict, dataclass
from fractions import Fraction
from pathlib import Path
from typing import Iterable


VCXO_HZ = 122_880_000
VCO_MIN_HZ = 3_450_000_000
VCO_MAX_HZ = 4_025_000_000
DATASHEET_URL = "https://www.analog.com/media/en/technical-documentation/data-sheets/AD9528.pdf"
ADI_DRIVER_SOURCE = "D:/FPGA_Learn/project_gtx/vitis_clean/laser_tx_rate/src/ad9528.c+h"
FINAL_GATE = "NO_SAFE_PLL2_TEST0_CANDIDATE"

EXPECTED_RANGES = ((0x0000, 0x000F), (0x0100, 0x010A), (0x0200, 0x0208),
                   (0x0300, 0x032E), (0x0400, 0x0403), (0x0500, 0x0509))
EXPECTED_ADDRESSES = tuple(
    address for first, last in EXPECTED_RANGES for address in range(first, last + 1))

BOARD_DESTINATIONS = {
    0: "FPGA_REF0_CLK / Bank110",
    1: "FPGA_REF1_CLK / Bank109",
    3: "FPGA_SYSREF",
    12: "ADRV9009_SYSREF",
    13: "ADRV9009_REF_CLK",
}


@dataclass(frozen=True)
class Candidate:
    name: str
    r1: int
    n2: int
    m1: int
    out0_div: int

    @property
    def pfd_hz(self) -> int:
        return VCXO_HZ // self.r1

    @property
    def vco_hz(self) -> int:
        return self.pfd_hz * self.n2 * self.m1

    @property
    def parent_hz(self) -> int:
        return self.vco_hz // self.m1

    @property
    def out0_hz(self) -> int:
        return self.parent_hz // self.out0_div

    @property
    def odiv2_count_1ms(self) -> int:
        return self.out0_hz // 2 // 1000

    @property
    def calibration_divider(self) -> int:
        return self.m1 * self.n2

    @property
    def feedback_ab(self) -> int:
        divider = self.calibration_divider
        return ((divider % 4) << 6) | (divider // 4)

    @property
    def theoretical_line_rate_hz(self) -> int:
        return self.out0_hz * 8

    @property
    def error_ppm_from_1g(self) -> int:
        return round((self.theoretical_line_rate_hz - 1_000_000_000) * 1_000_000 / 1_000_000_000)


CANDIDATES = (
    Candidate("PLL2_TEST0_OUT0_125P44", r1=6, n2=49, m1=4, out0_div=8),
    Candidate("PLL2_TEST0_OUT0_124P416", r1=8, n2=81, m1=3, out0_div=10),
)


@dataclass(frozen=True)
class RegisterPlanRow:
    address: str
    baseline_value: str
    target_value: str
    write_mask: str
    readback_mask: str
    expected_readback: str
    field_breakdown: str
    value_source: str
    buffered_or_live: str
    requires_io_update: bool
    included_in_snapshot: bool
    included_in_restore: bool
    confidence: str


def calibration_divider_valid(value: int) -> bool:
    return 16 <= value <= 255 and value not in (18, 19, 23, 27)


def parse_full_dump(text: str) -> dict[int, int]:
    pattern = re.compile(r"AD9528_REG\s+addr=0x([0-9A-Fa-f]{4})\s+value=0x([0-9A-Fa-f]{2})")
    values: dict[int, int] = {}
    for match in pattern.finditer(text):
        address, value = int(match.group(1), 16), int(match.group(2), 16)
        if address in values:
            raise ValueError(f"duplicate AD9528 register 0x{address:04X}")
        values[address] = value
    missing = [address for address in EXPECTED_ADDRESSES if address not in values]
    if missing:
        sample = ", ".join(f"0x{address:04X}" for address in missing[:8])
        raise ValueError(f"full dump missing {len(missing)} register(s): {sample}")
    return values


def masked_new(old: int, mask: int, value: int) -> int:
    return (old & ~mask) | (value & mask)


def _row(baseline: dict[int, int], address: int, mask: int, value: int,
         breakdown: str, source: str, confidence: str,
         *, buffered: str = "BUFFERED", io_update: bool = True,
         snapshot: bool = True, restore: bool = True) -> RegisterPlanRow:
    old = baseline[address]
    target = masked_new(old, mask, value)
    return RegisterPlanRow(
        f"0x{address:04X}", f"0x{old:02X}", f"0x{target:02X}", f"0x{mask:02X}",
        f"0x{mask:02X}", f"0x{target & mask:02X}", breakdown, source, buffered, io_update,
        snapshot and mask != 0, restore and mask != 0, confidence)


def register_plan(candidate: Candidate, baseline: dict[int, int]) -> list[RegisterPlanRow]:
    rows = [
        _row(baseline, 0x0108, 0x05, 0x01,
             "VCXO differential receiver enabled and receiver power-down cleared",
             "AD9528_DATASHEET+BOARD_122P88_VCXO", "FIELD_CONFIRMED_BOARD_ASSUMPTION"),
        _row(baseline, 0x0109, 0x38, 0x38,
             "PLL1 bypass/VCXO path enabled for PLL2 reference input",
             "AD9528_DATASHEET+EXISTING_VCXO_CANDIDATE", "FIELD_CONFIRMED"),
        _row(baseline, 0x010A, 0x00, 0x00, "Preserve reference control byte",
             "APPLICATION_INITIALIZED_BASELINE", "PRESERVED", snapshot=False, restore=False),
        _row(baseline, 0x0200, 0xFF, 0xE6,
             "PLL2 charge-pump code 230 (805 uA reference at approximately 3.5 uA/LSB)",
             ADI_DRIVER_SOURCE, "REFERENCE_ONLY_NOT_BOARD_CONFIRMED"),
        _row(baseline, 0x0201, 0xFF, candidate.feedback_ab,
             f"feedback calibration divider={candidate.calibration_divider}; "
             f"A={candidate.calibration_divider % 4}; B={candidate.calibration_divider // 4}",
             "AD9528_DATASHEET+ADI_DRIVER_ENCODING", "FIELD_CONFIRMED"),
        _row(baseline, 0x0202, 0xA3, 0x03,
             "lock detector enabled, doubler disabled, charge pump normal mode",
             "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0203, 0x17, 0x10,
             "R1 path enabled; calibration bit remains clear in base image and is a later action",
             "AD9528_DATASHEET+ADI_DRIVER_SEQUENCE", "FIELD_AND_SEQUENCE_CONFIRMED"),
        _row(baseline, 0x0204, 0x0F, candidate.m1,
             f"M1={candidate.m1}; M1 power-down cleared", "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0205, 0xFF, 0x3A,
             "reference loop-filter byte: RPOLE2=900 ohm, RZERO=1850 ohm, CPOLE1=16 pF",
             ADI_DRIVER_SOURCE, "REFERENCE_ONLY_NOT_BOARD_CONFIRMED"),
        _row(baseline, 0x0206, 0x01, 0x00, "RZERO bypass disabled",
             ADI_DRIVER_SOURCE, "REFERENCE_ONLY_NOT_BOARD_CONFIRMED"),
        _row(baseline, 0x0207, 0x1F, candidate.r1,
             f"PLL2 R1 divider={candidate.r1}", "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0208, 0xFF, candidate.n2 - 1,
             f"PLL2 N2 divider encoding=N2-1={candidate.n2 - 1}",
             "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0300, 0xE0, 0x00, "OUT0 source=PLL2/VCO",
             "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0301, 0xC0, 0x00, "OUT0 driver=LVDS; preserve phase bits",
             "AD9528_DATASHEET+BOARD_SCHEMATIC", "FIELD_CONFIRMED"),
        _row(baseline, 0x0302, 0xFF, candidate.out0_div - 1,
             f"OUT0 divider encoding=divide-{candidate.out0_div} minus one",
             "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x032A, 0x00, 0x00,
             "SYNC is a separate 1->0 action after output-divider change; no static byte write",
             "AD9528_DATASHEET", "SEQUENCE_CONFIRMED_SHARED_IMPACT_OPEN",
             snapshot=False, restore=False),
        _row(baseline, 0x032B, 0x00, 0x00, "SYNC ignore mask channels 0..7 preserved",
             "APPLICATION_INITIALIZED_BASELINE", "PRESERVED", snapshot=False, restore=False),
        _row(baseline, 0x032C, 0x00, 0x00, "SYNC ignore mask channels 8..13 preserved",
             "APPLICATION_INITIALIZED_BASELINE", "PRESERVED", snapshot=False, restore=False),
        _row(baseline, 0x0500, 0x08, 0x00, "clear PLL2 power-down only",
             "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0501, 0x01, 0x00, "clear OUT0 channel power-down only",
             "AD9528_DATASHEET", "FIELD_CONFIRMED"),
        _row(baseline, 0x0508, 0x00, 0x00,
             "read-only postcondition: VCXO OK, PLL2 feedback OK and PLL2 locked",
             "AD9528_DATASHEET", "STATUS_CONFIRMED", buffered="READ_ONLY", io_update=False,
             snapshot=False, restore=False),
        _row(baseline, 0x0509, 0x00, 0x00,
             "read-only postcondition: calibration in progress bit cleared",
             "AD9528_DATASHEET", "STATUS_CONFIRMED", buffered="READ_ONLY", io_update=False,
             snapshot=False, restore=False),
    ]
    # Read-only expected values are conditions, not the baseline-derived zeroes.
    replacements = {"0x0508": ("0xA2", "0xA2"), "0x0509": ("0x01", "0x00")}
    return [RegisterPlanRow(**({**asdict(row),
             "readback_mask": replacements[row.address][0],
             "expected_readback": replacements[row.address][1]}
            if row.address in replacements else asdict(row))) for row in rows]


def decoded_output_matrix(baseline: dict[int, int]) -> list[dict[str, object]]:
    source_names = {
        0: "PLL2", 1: "PLL1_VCXO", 2: "SYSREF_RETIMED_PLL2", 3: "SYSREF_RETIMED_PLL1",
        4: "SYSREF_DIRECT", 5: "INV_SYSREF_DIRECT", 6: "INV_SYSREF_RETIMED_PLL2",
        7: "INV_SYSREF_RETIMED_PLL1",
    }
    rows = []
    for index in range(14):
        base = 0x0300 + index * 3
        source_code = (baseline[base] >> 5) & 0x7
        enabled = not bool(baseline[0x0501 + (index // 8)] & (1 << (index % 8)))
        uses_pll2 = source_code in (0, 2, 6)
        rows.append({
            "output_index": index,
            "register_range": f"0x{base:04X}-0x{base + 2:04X}",
            "enabled": enabled,
            "source_code": source_code,
            "source": source_names[source_code],
            "divider": baseline[base + 2] + 1,
            "driver_mode_code": (baseline[base + 1] >> 6) & 0x3,
            "schematic_destination": BOARD_DESTINATIONS.get(index, "UNCONFIRMED"),
            "affected_by_pll2_common_change": enabled and uses_pll2,
            "affected_by_reference_path_change": enabled,
            "affected_by_global_sync": enabled,
            "risk_class": "KNOWN_SHARED_PLL2_CONSUMER" if enabled and uses_pll2 else
                          "ENABLED_GLOBAL_SYNC_CONSUMER" if enabled else "POWERED_DOWN",
        })
    return rows


def candidate_summary(candidate: Candidate) -> dict[str, object]:
    return {
        "candidate_name": candidate.name,
        "vcxo_hz": VCXO_HZ,
        "r1": candidate.r1,
        "n2": candidate.n2,
        "m1": candidate.m1,
        "pfd_hz": candidate.pfd_hz,
        "vco_hz": candidate.vco_hz,
        "vco_lower_margin_hz": candidate.vco_hz - VCO_MIN_HZ,
        "vco_upper_margin_hz": VCO_MAX_HZ - candidate.vco_hz,
        "calibration_divider": candidate.calibration_divider,
        "calibration_divider_valid": calibration_divider_valid(candidate.calibration_divider),
        "feedback_ab": f"0x{candidate.feedback_ab:02X}",
        "out0_div": candidate.out0_div,
        "out0_hz": candidate.out0_hz,
        "odiv2_hz": candidate.out0_hz // 2,
        "odiv2_count_1ms": candidate.odiv2_count_1ms,
        "theoretical_gt_line_rate_hz": candidate.theoretical_line_rate_hz,
        "error_ppm_from_1g": candidate.error_ppm_from_1g,
    }


def gate_for(candidate: Candidate, matrix: list[dict[str, object]]) -> dict[str, object]:
    failed = [
        "CHARGE_PUMP_BOARD_PROFILE_NOT_CONFIRMED",
        "LOOP_FILTER_BOARD_PROFILE_NOT_CONFIRMED",
        "SHARED_PLL2_OUTPUT_IMPACT_NOT_ACCEPTED",
        "GLOBAL_SYNC_IMPACT_NOT_ACCEPTED",
    ]
    if not calibration_divider_valid(candidate.calibration_divider):
        failed.append("PLL2_CALIBRATION_DIVIDER_NOT_ENCODABLE")
    if not any(row["affected_by_pll2_common_change"] for row in matrix):
        failed.append("PLL2_SHARED_OUTPUT_DECODE_NOT_PROVEN")
    return {
        "candidate_name": candidate.name,
        "result": "NOT_SAFE_TO_IMPLEMENT",
        "safe_to_implement": False,
        "failed_gates": failed,
        "requires_calibration": True,
        "requires_io_update": True,
        "requires_sync": True,
        "sync_safe": False,
        "executable_initializer_generated": False,
        "board_verified": False,
    }


def sequence_plan(candidate: Candidate) -> dict[str, object]:
    return {
        "candidate_name": candidate.name,
        "executable": False,
        "ordered_actions": [
            "snapshot_every_written_register_full_byte",
            "write_masked_0x0108_0x0109_and_0x0200_0x0208_and_OUT0_and_power",
            "io_update_1",
            "set_0x0203_calibration_bit",
            "io_update_2",
            "poll_0x0509_IS_CALIBRATING_until_clear",
            "poll_0x0508_VCXO_OK_PLL2_FEEDBACK_OK_PLL2_LOCKED",
            "sync_0x032A_1_to_0_required_after_divider_change",
            "post_readback_all_masked_fields",
            "measure_OUT0_ODIV2_for_complete_windows",
        ],
        "restore_actions": [
            "invalidate_measurement",
            "restore_all_snapshot_full_bytes",
            "io_update",
            "restore_sync_only_if_apply_sync_was_executed_and_safe",
            "post_restore_readback",
            "confirm_shared_outputs_returned_to_baseline",
        ],
        "critical_note": "Sequence is documentary only; shared-output SYNC permission is not closed.",
    }


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def generate(dump_text: str, output_dir: Path) -> None:
    baseline = parse_full_dump(dump_text)
    output_dir.mkdir(parents=True, exist_ok=True)
    normalized = "".join(f"AD9528_REG addr=0x{address:04X} value=0x{baseline[address]:02X}\n"
                         for address in EXPECTED_ADDRESSES)
    (output_dir / "baseline_full_dump.txt").write_text(normalized, encoding="utf-8")
    (output_dir / "baseline_full_dump.json").write_text(json.dumps({
        "semantic": "APPLICATION_INITIALIZED_BASELINE",
        "serial_port_note": "Application already wrote 0x0000=0x18 for four-wire SDO.",
        "register_count": len(baseline),
        "registers": {f"0x{address:04X}": f"0x{baseline[address]:02X}" for address in EXPECTED_ADDRESSES},
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    matrix = decoded_output_matrix(baseline)
    write_csv(output_dir / "shared_output_matrix.csv", matrix, list(matrix[0]))
    summaries = []
    gates = []
    for candidate in CANDIDATES:
        plan = register_plan(candidate, baseline)
        summary = candidate_summary(candidate)
        gate = gate_for(candidate, matrix)
        summaries.append(summary)
        gates.append(gate)
        stem = "candidate_125p44" if candidate.out0_hz == 125_440_000 else "candidate_124p416"
        payload = {
            "summary": summary,
            "register_plan": [asdict(row) for row in plan],
            "sequence": sequence_plan(candidate),
            "gate": gate,
        }
        (output_dir / f"{stem}_register_plan.json").write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        write_csv(output_dir / f"{stem}_register_plan.csv",
                  [asdict(row) for row in plan], list(RegisterPlanRow.__annotations__))

    write_csv(output_dir / "candidate_comparison.csv", summaries, list(summaries[0]))
    recommendation = {
        "recommended_candidate": "PLL2_TEST0_OUT0_124P416",
        "recommendation_scope": "LOWER_RISK_FOR_NEXT_PARAMETER_CLOSURE_ONLY",
        "safe_to_implement": False,
        "reason": (
            "Candidate B has materially larger margin to both AD9528 PLL2 VCO limits; "
            "candidate A is closer to the 125 MHz target but only 10.92 MHz below the upper VCO limit."
        ),
        "candidate_a_target_error_ppm": CANDIDATES[0].error_ppm_from_1g,
        "candidate_b_target_error_ppm": CANDIDATES[1].error_ppm_from_1g,
        "blocking_gates": sorted(set(item for gate in gates for item in gate["failed_gates"])),
    }
    (output_dir / "recommended_candidate.json").write_text(
        json.dumps(recommendation, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    overall = {
        "result": FINAL_GATE,
        "safe_to_implement": False,
        "candidate_results": gates,
        "executable_initializer_generated": False,
        "ad9528_write_operations": 0,
        "rtl_or_vitis_changes": False,
        "fixed_3000m_cpll_status": "BLOCKED/NO_LEGAL_VERIFIED_125M_CPLL_PROFILE",
    }
    (output_dir / "gate_result.json").write_text(
        json.dumps(overall, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary_lines = [
        "AD9528 PLL2 TEST0 dual-candidate register-plan generation",
        f"baseline_register_count={len(baseline)}",
        "baseline_semantic=APPLICATION_INITIALIZED_BASELINE",
        *[f"{item['candidate_name']}: out0_hz={item['out0_hz']} vco_hz={item['vco_hz']} "
          f"cal_div={item['calibration_divider']} count_1ms={item['odiv2_count_1ms']}"
          for item in summaries],
        f"recommended_for_next_closure={recommendation['recommended_candidate']}",
        f"final_gate={FINAL_GATE}",
        "safe_to_implement=false",
        "executable_initializer_generated=false",
    ]
    (output_dir / "generation_summary.txt").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dump-input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    generate(args.dump_input.read_text(encoding="utf-8", errors="replace"), args.output_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

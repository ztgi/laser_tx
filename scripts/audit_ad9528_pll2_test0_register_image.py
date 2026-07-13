#!/usr/bin/env python3
"""Generate the non-executable AD9528 PLL2 TEST0 register-image audit.

This tool never accesses hardware and never emits an executable C initializer.
It intentionally keeps unknown board-specific values as JSON null.  The
candidate under audit is mathematically 124.8 MHz, but its M1*N2 calibration
divider is 260 and therefore fails the official ADI no-OS 16..255 gate.
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Optional


CANDIDATE_NAME = "PLL2_TEST0_OUT0_124P8_CPLL_998P4"
FINAL_GATE = "NO_PROVEN_PLL2_REGISTER_IMAGE"
VCXO_HZ = 122_880_000
DOUBLER = 1
R1 = 8
N2 = 65
M1 = 4
OUT0_DIV = 8
PFD_HZ = VCXO_HZ * DOUBLER // R1
VCO_HZ = PFD_HZ * N2 * M1
OUT0_PARENT_HZ = VCO_HZ // M1
OUT0_HZ = OUT0_PARENT_HZ // OUT0_DIV
ODIV2_COUNT_1MS = OUT0_HZ // 2 // 1000
CALIBRATION_DIVIDER = M1 * N2

ADI_NO_OS_SOURCE = (
    "D:/FPGA_Learn/project_gtx/vitis_clean/laser_tx_rate/src/ad9528.c+h"
)


@dataclass(frozen=True)
class RegisterRow:
    address: str
    register_name: str
    current_readback: Optional[str]
    target_value: Optional[str]
    write_mask: Optional[str]
    expected_after_write: Optional[str]
    field_breakdown: str
    source_reference: str
    source_class: str
    buffered_or_live: str
    requires_io_update: Optional[bool]
    restored_value_source: str
    confidence: str


def calibration_divider_valid(value: int) -> bool:
    return 16 <= value <= 255 and value not in (18, 19, 23, 27)


def register_plan() -> list[RegisterRow]:
    unknown = None
    rows = [
        RegisterRow("0x0200", "PLL2_CHARGE_PUMP", unknown, unknown, unknown,
                    unknown,
                    "CP current code=current_nA/3500; board TEST0 loop design unconfirmed",
                    ADI_NO_OS_SOURCE, "ADI_DRIVER_DERIVED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "UNCONFIRMED"),
        RegisterRow("0x0201", "PLL2_FEEDBACK_DIVIDER_AB", unknown, unknown,
                    "0xFF", unknown,
                    "calibration_divider=M1*N2=260; A=divider%4=0; B=divider/4=65 exceeds B[5:0]",
                    ADI_NO_OS_SOURCE, "ADI_DRIVER_DERIVED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "INVALID_NOT_ENCODABLE"),
        RegisterRow("0x0202", "PLL2_CONTROL", unknown, "0x03", "0xA3",
                    unknown,
                    "bit7 lock-detector power-down=0; bit5 doubler=0; bits1:0 CP normal=3",
                    ADI_NO_OS_SOURCE, "ADI_DRIVER_DERIVED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0203", "PLL2_VCO_CONTROL", unknown, "0x10/0x11",
                    "0x17", unknown,
                    "bit4 R1/doubler path enable; bit0 calibration request; force bits2:1=0",
                    ADI_NO_OS_SOURCE, "ADI_DRIVER_DERIVED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "SEQUENCE_DERIVED_IMAGE_BLOCKED"),
        RegisterRow("0x0204", "PLL2_VCO_DIVIDER_M1", unknown, "0x04",
                    "0x0F", unknown,
                    "bits2:0 M1=4; bit3 M1 power-down=0",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0205", "PLL2_LOOP_FILTER_BYTE0", unknown, unknown,
                    unknown, unknown,
                    "CPOLE1/RZERO/RPOLE2 are board-loop-design inputs, not frequency-formula outputs",
                    ADI_NO_OS_SOURCE, "UNKNOWN", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "UNCONFIRMED"),
        RegisterRow("0x0206", "PLL2_LOOP_FILTER_BYTE1", unknown, unknown,
                    unknown, unknown,
                    "RZERO bypass and upper loop-filter byte require a proven board profile",
                    ADI_NO_OS_SOURCE, "UNKNOWN", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "UNCONFIRMED"),
        RegisterRow("0x0207", "PLL2_R1_DIVIDER", unknown, "0x08", "0x1F",
                    unknown, "bits4:0 R1=8",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0208", "PLL2_N2_DIVIDER", unknown, "0x40", "0xFF",
                    unknown, "N2 register encoding=N2-1=64; distinct from 0x0201 A/B",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0300", "OUT0_SOURCE", unknown, "0x00", "0xE0",
                    unknown, "bits7:5 source=PLL2/VCO; preserve unrelated bits",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0301", "OUT0_DRIVER_PHASE", unknown, unknown, "0x00",
                    unknown, "preserve current LVDS mode and phase; no write planned",
                    "BOARD_READBACK_REQUIRED", "UNKNOWN", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "UNCONFIRMED"),
        RegisterRow("0x0302", "OUT0_DIVIDER", unknown, "0x07", "0xFF",
                    unknown, "divider encoding=OUT0_DIV-1=7",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0500", "GLOBAL_POWER", unknown, "0x00", "0x08",
                    unknown, "clear PLL2 power-down only; preserve PLL1/bias/output/chip bits",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
        RegisterRow("0x0501", "CHANNEL_POWER_OUT0", unknown, "0x00", "0x01",
                    unknown, "clear OUT0 power-down only; preserve OUT1..OUT7",
                    ADI_NO_OS_SOURCE, "DATASHEET_DEFINED", "BUFFERED", True,
                    "BOARD_DUMP_SNAPSHOT", "FIELD_CONFIRMED_IMAGE_BLOCKED"),
    ]
    return rows


BOARD_DESTINATIONS = {
    0: "FPGA_REF0_CLK / Bank110",
    1: "FPGA_REF1_CLK / Bank109",
    3: "FPGA_SYSREF",
    12: "ADRV9009_SYSREF",
    13: "ADRV9009_REF_CLK",
}


def shared_output_matrix() -> list[dict[str, object]]:
    return [
        {
            "output_index": index,
            "register_range": f"0x{0x300 + index * 3:04X}-0x{0x302 + index * 3:04X}",
            "enabled": "UNKNOWN",
            "source": "UNKNOWN",
            "divider": None,
            "phase": None,
            "driver_mode": "UNKNOWN",
            "schematic_net": BOARD_DESTINATIONS.get(index, "UNCONFIRMED"),
            "board_destination": BOARD_DESTINATIONS.get(index, "UNCONFIRMED"),
            "affected_by_pll2_common_change": "UNKNOWN",
            "risk_class": "UNKNOWN",
            "evidence": "BOARD_DUMP_REQUIRED",
        }
        for index in range(14)
    ]


def gate_result() -> dict[str, object]:
    failed = [
        "PLL2_CALIBRATION_DIVIDER_NOT_ENCODABLE",
        "FEEDBACK_AB_NOT_ENCODABLE",
        "CHARGE_PUMP_NOT_CONFIRMED_FOR_BOARD_TEST0",
        "LOOP_FILTER_NOT_CONFIRMED_FOR_BOARD_TEST0",
        "BOARD_DUMP_REQUIRED_FOR_A_B_C_STATES",
        "SYNC_DECISION_NOT_CLOSED",
        "SHARED_CLOCK_TREE_IMPACT_NOT_ACCEPTED",
    ]
    return {
        "candidate_name": CANDIDATE_NAME,
        "result": FINAL_GATE,
        "safe_to_implement": False,
        "failed_gates": failed,
        "calibration_divider": CALIBRATION_DIVIDER,
        "calibration_divider_valid": calibration_divider_valid(CALIBRATION_DIVIDER),
        "executable_initializer_generated": False,
        "board_verified": False,
    }


def sequence_plan() -> dict[str, object]:
    return {
        "candidate_name": CANDIDATE_NAME,
        "executable": False,
        "sequence_source": ADI_NO_OS_SOURCE,
        "nominal_order": [
            "snapshot_all_modified_registers",
            "masked_write_pll2_common_out0_and_power",
            "io_update_1",
            "write_0x0203_calibrate_bit",
            "io_update_2",
            "poll_0x0508_IS_CALIBRATING_clear",
            "poll_0x0508_PLL2_LOCKED_and_PLL2_OK",
            "channel_sync_only_if_shared_output_audit_proves_safe",
            "post_readback",
            "frequency_measurement",
        ],
        "calibration_timeout": None,
        "lock_timeout": None,
        "poll_interval": None,
        "requires_sync": None,
        "sync_reason": "FULL_OUTPUT_IMAGE_AND_SYNC_IGNORE_MASK_REQUIRED",
        "restore": [
            "invalidate_measurement_result",
            "restore_full_snapshot_bytes",
            "io_update",
            "readback_verify",
            "verify_pll2_common_and_all_outputs_returned_to_preapply_state",
            "clear_measurement_cache",
        ],
        "failure_status_fields": [
            "last_error", "failed_reg", "expected", "actual",
            "rollback_attempted", "rollback_success",
        ],
    }


def generate(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    registers = register_plan()
    matrix = shared_output_matrix()
    payload = {
        "candidate_name": CANDIDATE_NAME,
        "target_out0_hz": OUT0_HZ,
        "expected_odiv2_count_1ms": ODIV2_COUNT_1MS,
        "math": {
            "vcxo_hz": VCXO_HZ,
            "doubler": DOUBLER,
            "r1": R1,
            "n2": N2,
            "m1": M1,
            "pfd_hz": PFD_HZ,
            "vco_hz": VCO_HZ,
            "out0_parent_hz": OUT0_PARENT_HZ,
            "out0_div": OUT0_DIV,
            "calibration_divider": CALIBRATION_DIVIDER,
        },
        "registers": [asdict(row) for row in registers],
        "requires_calibration": True,
        "requires_sync": None,
        "shared_clock_tree_accepted": False,
        "safe_to_implement": False,
    }
    (output_dir / "pll2_test0_register_plan.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (output_dir / "pll2_test0_register_plan.csv").open(
            "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(RegisterRow.__annotations__),
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(asdict(row) for row in registers)
    (output_dir / "pll2_test0_sequence.json").write_text(
        json.dumps(sequence_plan(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8")
    with (output_dir / "pll2_test0_shared_output_matrix.csv").open(
            "w", newline="", encoding="utf-8") as handle:
        fields = list(matrix[0])
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(matrix)
    (output_dir / "pll2_test0_gate_result.json").write_text(
        json.dumps(gate_result(), indent=2, sort_keys=True) + "\n",
        encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path,
                        default=Path("reports/ad9528_pll2_test0_register_image"))
    args = parser.parse_args()
    generate(args.output_dir)
    print(f"PASS: gate={FINAL_GATE} output={args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

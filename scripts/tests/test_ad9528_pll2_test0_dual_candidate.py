import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import compare_ad9528_pll2_test0_register_plans as compare


def synthetic_dump() -> str:
    values = {address: 0 for address in compare.EXPECTED_ADDRESSES}
    values.update({0x0000: 0x18, 0x0106: 0x0C, 0x0201: 0x04, 0x0202: 0x03,
                   0x0302: 0x04, 0x0500: 0x10, 0x0503: 0xFF, 0x0504: 0xFF,
                   0x0508: 0x10, 0x0509: 0x08})
    for channel in range(14):
        base = 0x0300 + channel * 3
        values[base] = 0x40 if channel % 2 else 0x00
        values[base + 2] = 0x00 if channel % 2 else 0x04
    values[0x0324] = values[0x0327] = 0x20
    return "".join(f"AD9528_REG addr=0x{address:04X} value=0x{values[address]:02X}\n"
                   for address in compare.EXPECTED_ADDRESSES)


class DualCandidatePlanTest(unittest.TestCase):
    def test_parse_full_dump(self):
        parsed = compare.parse_full_dump(synthetic_dump())
        self.assertEqual(len(parsed), len(compare.EXPECTED_ADDRESSES))
        self.assertEqual(parsed[0x0000], 0x18)

    def test_missing_register_rejected(self):
        with self.assertRaisesRegex(ValueError, "missing"):
            compare.parse_full_dump(synthetic_dump().replace(
                "AD9528_REG addr=0x0208 value=0x00\n", ""))

    def test_duplicate_register_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            compare.parse_full_dump(synthetic_dump() + "AD9528_REG addr=0x0208 value=0x00\n")

    def test_candidate_a_math(self):
        a = compare.CANDIDATES[0]
        self.assertEqual((a.pfd_hz, a.vco_hz, a.out0_hz),
                         (20_480_000, 4_014_080_000, 125_440_000))
        self.assertEqual((a.feedback_ab, a.odiv2_count_1ms), (0x31, 62_720))
        self.assertEqual(a.error_ppm_from_1g, 3520)

    def test_candidate_b_math(self):
        b = compare.CANDIDATES[1]
        self.assertEqual((b.pfd_hz, b.vco_hz, b.out0_hz),
                         (15_360_000, 3_732_480_000, 124_416_000))
        self.assertEqual((b.feedback_ab, b.odiv2_count_1ms), (0xFC, 62_208))
        self.assertEqual(b.error_ppm_from_1g, -4672)

    def test_calibration_dividers_valid(self):
        self.assertEqual([c.calibration_divider for c in compare.CANDIDATES], [196, 243])
        self.assertTrue(all(compare.calibration_divider_valid(c.calibration_divider)
                            for c in compare.CANDIDATES))

    def test_vco_margins(self):
        a, b = map(compare.candidate_summary, compare.CANDIDATES)
        self.assertEqual(a["vco_upper_margin_hz"], 10_920_000)
        self.assertEqual(b["vco_lower_margin_hz"], 282_480_000)
        self.assertEqual(b["vco_upper_margin_hz"], 292_520_000)

    def test_all_written_registers_are_snapshotted_and_restored(self):
        plan = compare.register_plan(compare.CANDIDATES[0], compare.parse_full_dump(synthetic_dump()))
        for row in plan:
            if row.write_mask != "0x00" and row.buffered_or_live != "READ_ONLY":
                self.assertTrue(row.included_in_snapshot, row.address)
                self.assertTrue(row.included_in_restore, row.address)

    def test_shared_output_decode_and_gate(self):
        matrix = compare.decoded_output_matrix(compare.parse_full_dump(synthetic_dump()))
        self.assertEqual(len(matrix), 14)
        self.assertTrue(any(row["affected_by_pll2_common_change"] for row in matrix))
        self.assertTrue(all(row["affected_by_global_sync"] for row in matrix))

    def test_unknown_critical_fields_keep_gate_closed(self):
        matrix = compare.decoded_output_matrix(compare.parse_full_dump(synthetic_dump()))
        gate = compare.gate_for(compare.CANDIDATES[0], matrix)
        self.assertFalse(gate["safe_to_implement"])
        self.assertIn("CHARGE_PUMP_BOARD_PROFILE_NOT_CONFIRMED", gate["failed_gates"])
        self.assertIn("LOOP_FILTER_BOARD_PROFILE_NOT_CONFIRMED", gate["failed_gates"])

    def test_sync_required_but_not_safe(self):
        gate = compare.gate_for(compare.CANDIDATES[0],
                                compare.decoded_output_matrix(compare.parse_full_dump(synthetic_dump())))
        self.assertTrue(gate["requires_sync"])
        self.assertFalse(gate["sync_safe"])

    def test_status_readback_masks(self):
        plan = {row.address: row for row in compare.register_plan(
            compare.CANDIDATES[0], compare.parse_full_dump(synthetic_dump()))}
        self.assertEqual((plan["0x0508"].write_mask, plan["0x0508"].readback_mask,
                          plan["0x0508"].expected_readback), ("0x00", "0xA2", "0xA2"))
        self.assertEqual((plan["0x0509"].write_mask, plan["0x0509"].readback_mask,
                          plan["0x0509"].expected_readback), ("0x00", "0x01", "0x00"))

    def test_no_executable_initializer(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            compare.generate(synthetic_dump(), output)
            self.assertFalse(any(path.suffix in (".c", ".h") for path in output.iterdir()))
            gate = json.loads((output / "gate_result.json").read_text())
            self.assertFalse(gate["safe_to_implement"])

    def test_deterministic_generation(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            compare.generate(synthetic_dump(), Path(first))
            compare.generate(synthetic_dump(), Path(second))
            names = sorted(path.name for path in Path(first).iterdir())
            self.assertEqual(names, sorted(path.name for path in Path(second).iterdir()))
            for name in names:
                self.assertEqual((Path(first) / name).read_bytes(), (Path(second) / name).read_bytes())

    def test_3000m_fixed_cpll_remains_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            compare.generate(synthetic_dump(), Path(directory))
            gate = json.loads((Path(directory) / "gate_result.json").read_text())
            self.assertEqual(gate["fixed_3000m_cpll_status"],
                             "BLOCKED/NO_LEGAL_VERIFIED_125M_CPLL_PROFILE")


if __name__ == "__main__":
    unittest.main()

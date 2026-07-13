import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import audit_ad9528_pll2_test0_register_image as audit


class Pll2Test0RegisterAuditTest(unittest.TestCase):
    def test_01_math_pfd(self): self.assertEqual(audit.PFD_HZ, 15_360_000)
    def test_02_math_vco(self): self.assertEqual(audit.VCO_HZ, 3_993_600_000)
    def test_03_math_parent(self): self.assertEqual(audit.OUT0_PARENT_HZ, 998_400_000)
    def test_04_math_out0(self): self.assertEqual(audit.OUT0_HZ, 124_800_000)
    def test_05_math_count(self): self.assertEqual(audit.ODIV2_COUNT_1MS, 62_400)
    def test_06_r1_range(self): self.assertTrue(1 <= audit.R1 <= 31)
    def test_07_n2_range(self): self.assertTrue(1 <= audit.N2 <= 256)
    def test_08_m1_range(self): self.assertIn(audit.M1, (3, 4, 5))
    def test_09_outdiv_range(self): self.assertTrue(1 <= audit.OUT0_DIV <= 256)
    def test_10_feedback_gate_fails(self):
        self.assertEqual(audit.CALIBRATION_DIVIDER, 260)
        self.assertFalse(audit.calibration_divider_valid(260))

    def test_11_no_duplicate_registers(self):
        addresses = [row.address for row in audit.register_plan()]
        self.assertEqual(len(addresses), len(set(addresses)))

    def test_12_unknown_cp_fails_gate(self):
        cp = next(row for row in audit.register_plan() if row.address == "0x0200")
        self.assertIsNone(cp.target_value)
        self.assertIn("CHARGE_PUMP", audit.gate_result()["failed_gates"][2])

    def test_13_unknown_loop_filter_fails_gate(self):
        rows = {row.address: row for row in audit.register_plan()}
        self.assertIsNone(rows["0x0205"].target_value)
        self.assertIsNone(rows["0x0206"].target_value)

    def test_14_shared_unknown_fails_gate(self):
        self.assertEqual(len(audit.shared_output_matrix()), 14)
        self.assertTrue(all(row["risk_class"] == "UNKNOWN"
                            for row in audit.shared_output_matrix()))

    def test_15_safe_false_and_no_initializer(self):
        gate = audit.gate_result()
        self.assertFalse(gate["safe_to_implement"])
        self.assertFalse(gate["executable_initializer_generated"])

    def test_16_snapshot_source_for_every_planned_register(self):
        self.assertTrue(all(row.restored_value_source == "BOARD_DUMP_SNAPSHOT"
                            for row in audit.register_plan()))

    def test_17_sync_unconfirmed(self):
        self.assertIsNone(audit.sequence_plan()["requires_sync"])

    def test_18_deterministic_outputs(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            audit.generate(Path(first)); audit.generate(Path(second))
            names = sorted(path.name for path in Path(first).iterdir())
            self.assertEqual(names, sorted(path.name for path in Path(second).iterdir()))
            for name in names:
                self.assertEqual((Path(first) / name).read_bytes(),
                                 (Path(second) / name).read_bytes())

    def test_19_gate_json_roundtrip(self):
        with tempfile.TemporaryDirectory() as directory:
            audit.generate(Path(directory))
            gate = json.loads((Path(directory) / "pll2_test0_gate_result.json").read_text())
            self.assertEqual(gate["result"], audit.FINAL_GATE)

    def test_20_full_dump_includes_readback_high_byte(self):
        with tempfile.TemporaryDirectory() as directory:
            audit.generate(Path(directory))
            plan = json.loads((Path(directory) / "pll2_test0_register_plan.json").read_text())
            self.assertIn("0500-0509", plan["full_dump"]["ranges"])
            self.assertEqual(plan["full_dump"]["udp_response"], "SUMMARY_ONLY")
            self.assertEqual(plan["full_dump"]["register_data_sink"],
                             "UART AD9528_REG lines")

    def test_21_vitis_full_dump_range_and_protocol_text(self):
        driver = (REPO / "vitis_bringup/bringup/src/laser_ad9528.c").read_text()
        udp = (REPO / "vitis_bringup/bringup/src/laser_udp_server.c").read_text()
        self.assertIn("{0x0500U, 0x0509U}", driver)
        self.assertNotIn("{0x0500U, 0x0508U}", driver)
        self.assertIn("0500-0509", udp)


if __name__ == "__main__":
    unittest.main()

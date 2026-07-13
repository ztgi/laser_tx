import csv
import json
import sys
import tempfile
import unittest
from fractions import Fraction
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

import enumerate_ad9528_gt_refclk_candidates as planner


class FineStepPlannerTest(unittest.TestCase):
    def test_124p8_math_is_reproducible_but_not_encodable(self):
        pfd = Fraction(122_880_000, 8)
        vco = pfd * 65 * 4
        out0 = vco / 4 / 8
        self.assertEqual(pfd, Fraction(15_360_000))
        self.assertEqual(vco, Fraction(3_993_600_000))
        self.assertEqual(out0, Fraction(124_800_000))
        self.assertFalse(planner.pll2_calibration_divider_valid(65 * 4))
        configs = planner.enumerate_pll2_configs()
        self.assertNotIn(Fraction(124_800_000), configs)

    def test_calibration_divider_driver_limits(self):
        for value in (16, 17, 20, 255):
            self.assertTrue(planner.pll2_calibration_divider_valid(value))
        for value in (0, 15, 18, 19, 23, 27, 256, 260):
            self.assertFalse(planner.pll2_calibration_divider_valid(value))

    def test_invalid_pfd_and_vco_excluded(self):
        bad_pfd = planner.Ad9528Pll2Limits(
            Fraction(200_000_000), Fraction(210_000_000),
            planner.PLL2_LIMITS.pll2_vco_min_hz,
            planner.PLL2_LIMITS.pll2_vco_max_hz,
            (8,), (65,), (4,), (1,), (8,), Fraction(1_250_000_000))
        self.assertEqual(planner.enumerate_pll2_configs(limits=bad_pfd), {})
        bad_vco = planner.Ad9528Pll2Limits(
            Fraction(1), Fraction(275_000_000), Fraction(4_100_000_000),
            Fraction(4_200_000_000), (8,), (65,), (4,), (1,), (8,),
            Fraction(1_250_000_000))
        self.assertEqual(planner.enumerate_pll2_configs(limits=bad_vco), {})

    def test_gt_gap_is_excluded(self):
        for gt in planner.gt_tuples(Fraction(125_000_000)):
            self.assertFalse(Fraction(8_000_000_000) < gt.line_rate_bps <
                             Fraction(9_800_000_000))

    def test_vcxo_direct_not_pll2_candidate(self):
        row = planner.vcxo_direct_row()
        self.assertEqual(row["source"], planner.VCXO_DIRECT)
        self.assertFalse(row["pll2_fine_step_candidate"])
        rows, low, exact = planner.generate_candidates()
        self.assertEqual(rows[0].source, planner.VCXO_DIRECT)
        self.assertTrue(rows[0].board_measured)
        self.assertFalse(any(item.source == planner.VCXO_DIRECT for item in low + exact))

    def test_3000_paths_are_independent(self):
        fixed = planner.fixed_3000_blocked_row()
        self.assertEqual(fixed["rate_path"], planner.FIXED_125M_CPLL)
        self.assertEqual(fixed["rate_state"], planner.BLOCKED)
        self.assertEqual(fixed["reason"],
                         planner.NO_LEGAL_VERIFIED_125M_CPLL_PROFILE)
        _, _, exact = planner.generate_candidates()
        self.assertEqual(exact, [])

    def test_no_duplicate_implementation_path_records(self):
        rows, _, _ = planner.generate_candidates()
        keys = [(r.out0_hz, r.rate_path, r.gt_refclk_div, r.gt_fbdiv_45,
                 r.gt_fbdiv, r.gt_txout_div, r.target_rate_mbps) for r in rows]
        self.assertEqual(len(keys), len(set(keys)))

    def test_measurement_count(self):
        self.assertEqual(Fraction(124_800_000, 2_000), 62400)

    def test_repeat_generation_is_identical_and_not_verified(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            planner.generate(Path(a))
            planner.generate(Path(b))
            for name in ("all_candidates.csv", "low_risk_shortlist.csv",
                         "exact_3000m_shortlist.csv", "recommended_test0.json",
                         "generation_summary.txt"):
                self.assertEqual((Path(a) / name).read_bytes(),
                                 (Path(b) / name).read_bytes())
            data = json.loads((Path(a) / "recommended_test0.json").read_text())
            self.assertFalse(data["board_verified"])
            self.assertEqual(data["decision"], "NO_SAFE_PLL2_TEST0_CANDIDATE")
            pending = data.get("preferred_candidate_pending_gates", {})
            self.assertNotEqual(pending.get("candidate_name"),
                                "PLL2_TEST0_OUT0_124P8_CPLL_998P4")

    def test_no_candidate_has_explicit_safe_stop(self):
        data = planner.recommendation([], [])
        self.assertEqual(data["decision"], "NO_SAFE_PLL2_TEST0_CANDIDATE")
        self.assertNotIn("preferred_candidate_pending_gates", data)
        self.assertFalse(data["board_verified"])

    def test_csv_states_and_no_duplicate_header(self):
        with tempfile.TemporaryDirectory() as directory:
            planner.generate(Path(directory))
            with (Path(directory) / "exact_3000m_shortlist.csv").open() as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(rows, [])


if __name__ == "__main__":
    unittest.main()

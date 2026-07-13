import re
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
DRIVER = (REPO / "vitis_bringup/bringup/src/laser_ad9528.c").read_text()
HEADER = (REPO / "vitis_bringup/bringup/src/laser_ad9528.h").read_text()
UDP = (REPO / "vitis_bringup/bringup/src/laser_udp_server.c").read_text()
PLANNER = (REPO / "vitis_bringup/bringup/src/gt_rate_plan.c").read_text()


class Pll2Test0MeasurementExecutorTest(unittest.TestCase):
    def test_candidate_identity_and_frequency(self):
        self.assertIn('AD9528_PLL2_TEST0_PROFILE_NAME "PLL2_TEST0"', DRIVER)
        self.assertIn("AD9528_PLL2_TEST0_OUT0_HZ      124416000UL", DRIVER)
        self.assertIn("AD9528_PLL2_TEST0_COUNT         62208U", DRIVER)

    def test_reference_configuration_is_one_complete_set(self):
        for token in ("0xE6U", "0xFCU", "0x03U", "0x10U", "0x3AU",
                      "0x08U", "0x50U"):
            self.assertIn(token, DRIVER)
        self.assertIn("REFERENCE_CONFIGURATION", DRIVER)

    def test_measurement_requires_three_windows_and_one_percent_max(self):
        self.assertIn("AD9528_PLL2_TEST0_WINDOWS       3U", DRIVER)
        self.assertIn("AD9528_PLL2_TEST0_COUNT_MIN     61586U", DRIVER)
        self.assertIn("AD9528_PLL2_TEST0_COUNT_MAX     62830U", DRIVER)
        self.assertIn("AD9528_PLL2_TEST0_PREFERRED_MIN 61897U", DRIVER)
        self.assertIn("AD9528_PLL2_TEST0_PREFERRED_MAX 62519U", DRIVER)

    def test_no_channel_sync_write(self):
        self.assertNotRegex(DRIVER,
            r"laser_ad9528_write\s*\(\s*AD9528_CHANNEL_SYNC_REG")
        self.assertNotIn("CLOCK_DEDICATED_ROUTE", DRIVER)

    def test_failure_paths_rollback(self):
        for error in ("CALIBRATION_TIMEOUT", "PLL2_LOCK_TIMEOUT",
                      "MEASUREMENT_TIMEOUT", "MEASUREMENT_OUT_OF_RANGE"):
            self.assertIn(error, HEADER)
        self.assertIn("ad9528_candidate_rollback(&plan, 0U)", DRIVER)

    def test_lab_only_and_board_verified_false(self):
        self.assertIn("ACCEPTED_FOR_LAB_TEST_ONLY", DRIVER)
        self.assertIn("pll2_functionally_measured=%u", DRIVER)
        self.assertIn("board_verified=0", DRIVER)

    def test_udp_command_uses_existing_candidate_interface(self):
        self.assertIn("laser_ad9528_candidate_set(profile)", UDP)
        self.assertIn("LASER_AD9528_CANDIDATE_READY_MEASURED", UDP)

    def test_fixed_rate_planner_unchanged_for_3000(self):
        self.assertNotRegex(PLANNER, r"\.rate_mbps\s*=\s*3000U")
        self.assertIn("NO_LEGAL_VERIFIED_125M_CPLL_PROFILE", PLANNER)

    def test_no_production_profile_or_gt_reference_select(self):
        for forbidden in ("GTNORTHREFCLK", "CPLLREFCLKSEL", "QPLLREFCLKSEL",
                          "RATE_ID_3000"):
            self.assertNotIn(forbidden, DRIVER)


if __name__ == "__main__":
    unittest.main()

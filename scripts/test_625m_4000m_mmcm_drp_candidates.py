#!/usr/bin/env python3
"""Focused checks for isolated 625M/4000M VPHY-style MMCM DRP candidates."""

import unittest

import generate_625m_4000m_mmcm_drp_candidates as generator


class MmcmCandidateTest(unittest.TestCase):
    def test_625m_wizard_clock_solution_and_sequence(self) -> None:
        profile = generator.PROFILES[0]
        self.assertEqual((profile.clkfbout_mult, profile.clkout0_divide,
                          profile.clkout1_divide), (31, 62, 31))
        self.assertAlmostEqual(profile.clkin_mhz * profile.clkfbout_mult,
                               605.46875)
        values = {entry["address"]: entry["value"]
                  for entry in generator.sequence(profile)}
        self.assertEqual(values[0x14], 0x13D0)
        self.assertEqual(values[0x15], 0x0080)
        self.assertEqual(values[0x08], 0x17DF)
        self.assertEqual(values[0x4F], 0x9000)

    def test_4000m_wizard_clock_solution_and_sequence(self) -> None:
        profile = generator.PROFILES[1]
        self.assertEqual((profile.clkfbout_mult, profile.clkout0_divide,
                          profile.clkout1_divide), (5, 10, 5))
        self.assertAlmostEqual(profile.clkin_mhz * profile.clkfbout_mult,
                               625.0)
        values = {entry["address"]: entry["value"]
                  for entry in generator.sequence(profile)}
        self.assertEqual(values[0x14], 0x1083)
        self.assertEqual(values[0x15], 0x0080)
        self.assertEqual(values[0x08], 0x1145)
        self.assertEqual(values[0x4F], 0x1900)


if __name__ == "__main__":
    unittest.main()

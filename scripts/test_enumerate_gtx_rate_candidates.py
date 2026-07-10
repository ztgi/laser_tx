#!/usr/bin/env python3
"""Focused unit tests for the GTX candidate-rate enumerator constraints."""

from fractions import Fraction
import unittest

import enumerate_gtx_rate_candidates as enumerator


class CandidateEnumeratorTest(unittest.TestCase):
    def test_qpll_upper_band_div4_2500_is_legal(self) -> None:
        legal, _ = enumerator.enumerate_qpll(Fraction(125))
        row = next(row for row in legal
                   if row.m == "1" and row.n2_or_n == "80" and
                   row.txout_div == "4")
        self.assertEqual(row.pll_vco_mhz, "10000")
        self.assertEqual(row.line_rate_mbps, "2500")
        self.assertEqual(row.qpll_fbdiv_ratio, "1")

    def test_qpll_fbdiv_ratio_for_66(self) -> None:
        legal, _ = enumerator.enumerate_qpll(Fraction(625, 4))
        row = next(row for row in legal
                   if row.m == "1" and row.n2_or_n == "66" and
                   row.txout_div == "1")
        self.assertEqual(row.pll_vco_mhz, "10312.5")
        self.assertEqual(row.line_rate_mbps, "10312.5")
        self.assertEqual(row.qpll_fbdiv_ratio, "0")
        self.assertEqual(enumerator.qpll_fbdiv_ratio(64), "1")
        self.assertEqual(enumerator.qpll_fbdiv_ratio(80), "1")

    def test_qpll_lower_band_div16_is_blocked(self) -> None:
        _, blocked = enumerator.enumerate_qpll(Fraction(125))
        row = next(row for row in blocked
                   if row.m == "1" and row.n2_or_n == "64" and
                   row.txout_div == "16")
        self.assertEqual(row.pll_vco_mhz, "8000")
        self.assertEqual(row.line_rate_mbps, "500")
        self.assertEqual(row.reason_or_gate,
                         "QPLL_TXOUT_DIV_LINE_RATE_RANGE_VIOLATION")

    def test_cpll_vco_below_minimum_is_blocked(self) -> None:
        _, blocked = enumerator.enumerate_cpll(Fraction(125))
        row = next(row for row in blocked
                   if row.m == "1" and row.n1 == "4" and
                   row.n2_or_n == "3" and row.txout_div == "1")
        self.assertEqual(row.pll_vco_mhz, "1500")
        self.assertEqual(row.line_rate_mbps, "3000")
        self.assertEqual(row.reason_or_gate,
                         "CPLL_VCO_OUTSIDE_XC7Z100_2_RANGE_1600_TO_3300MHZ")


if __name__ == "__main__":
    unittest.main()

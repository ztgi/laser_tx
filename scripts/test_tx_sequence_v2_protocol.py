#!/usr/bin/env python3
"""Host-side protocol/record checks for the incompatible TX sequence V2."""
from __future__ import annotations

import pathlib
import struct
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MAX_REPEAT = 16
WORDS = 16


def parse_number(text: str) -> int:
    value = int(text, 0)
    if value < 0 or value > 0xFFFFFFFF:
        raise ValueError("u32 range")
    return value


def phase_count(pattern127: int, phase_shift: int) -> int:
    if not phase_shift:
        return 1
    return 127 if pattern127 else 63


def legacy_prbs_period(order: int, seed: int) -> int:
    """Reference-only model of the removed production LFSR."""
    if order == 6:
        state, width, count = seed & 0x3F, 6, 63
    elif order == 7:
        state, width, count = seed & 0x7F, 7, 127
    else:
        raise ValueError("legacy PRBS order")
    if state == 0:
        state = (1 << width) - 1
    period = 0
    for bit_index in range(count):
        period |= ((state >> (width - 1)) & 1) << bit_index
        feedback = ((state >> (width - 1)) ^
                    (state >> (width - 2))) & 1
        state = ((state << 1) & ((1 << width) - 1)) | feedback
    return period


def parse_write_config(command: str) -> dict:
    tokens = command.split()
    if not tokens or tokens[0].upper() != "WRITE_CONFIG":
        raise ValueError("command")
    values = [parse_number(item) for item in tokens[1:]]
    if len(values) < 14:
        raise ValueError("argument count")
    index, repeat, pattern127, phase_shift, loop, head = values[:6]
    if not (0 <= index < 128 and 1 <= repeat <= MAX_REPEAT):
        raise ValueError("base range")
    if pattern127 not in (0, 1) or phase_shift not in (0, 1) or loop not in (0, 1):
        raise ValueError("boolean")
    if head > 255:
        raise ValueError("head")
    expected = repeat + 13
    if len(values) != expected:
        raise ValueError("argument count")
    gap_count = repeat - 1
    gaps = values[6:6 + gap_count]
    if any(gap > 255 for gap in gaps):
        raise ValueError("gap")
    tail = values[6 + gap_count:]
    eom_enable, eom_index, lead, trail, p0, p1, p2, p3 = tail
    if eom_enable not in (0, 1) or lead > 65535 or trail > 65535 or p3 & 0x80000000:
        raise ValueError("EOM/pattern range")
    instances = phase_count(pattern127, phase_shift) * repeat
    if eom_enable and eom_index >= instances:
        raise ValueError("global EOM index")
    return dict(index=index, repeat=repeat,
                pattern127=pattern127, phase_shift=phase_shift,
                loop=loop, head=head, gaps=gaps, eom_enable=eom_enable,
                eom_index=eom_index, lead=lead, trail=trail,
                pattern=(p0, p1, p2, p3))


def pack_record(cfg: dict, sequence: int = 0x21, committed: bool = True) -> list[int]:
    words = [0] * WORDS
    words[0] = (0x5458 << 16) | (2 << 12) | ((1 if committed else 0) << 11) | sequence
    words[1] = 0
    words[2] = (cfg["repeat"] |
                 (cfg["phase_shift"] << 13) | (cfg["loop"] << 14) |
                 (cfg["pattern127"] << 16) |
                (cfg["eom_enable"] << 17) | (cfg["eom_index"] << 18))
    words[3] = cfg["head"]
    gaps = list(cfg["gaps"]) + [0] * (15 - len(cfg["gaps"]))
    for i in range(3):
        words[4 + i] = sum(gaps[i * 4 + j] << (8 * j) for j in range(4))
    words[7] = sum(gaps[12 + j] << (8 * j) for j in range(3))
    words[8] = cfg["lead"] | (cfg["trail"] << 16)
    words[9:13] = cfg["pattern"]
    words[13] = sequence | (16 << 8) | (16 << 16) | (8 << 24)
    payload = b"".join(struct.pack("<I", word) for word in words[1:15])
    words[15] = zlib.crc32(payload) & 0xFFFFFFFF
    return words


class TxSequenceV2ProtocolTest(unittest.TestCase):
    def make_command(self, repeat: int, gaps: list[int], *, head: int = 0,
                     eom_enable: int = 1, eom_index: int = 0,
                     phase_shift: int = 0, pattern127: int = 1) -> str:
        # Reserved ABI slots are internal fixed zeros and are no longer part
        # of the UDP syntax. pattern127 and words9..12 define the pattern.
        base = [0, repeat, pattern127, phase_shift, 0, head]
        tail = [eom_enable, eom_index, 2, 3,
                0x89ABCDEF, 0x01234567, 0x76543210, 0x02A55AA5]
        return "WRITE_CONFIG " + " ".join(str(v) for v in base + gaps + tail)

    def test_repeat_one_no_gap(self):
        cfg = parse_write_config(self.make_command(1, []))
        self.assertEqual(cfg["gaps"], [])

    def test_repeat_sixteen_fifteen_gaps(self):
        cfg = parse_write_config(self.make_command(16, list(range(15))))
        self.assertEqual(len(cfg["gaps"]), 15)

    def test_gap_count_short_and_long(self):
        with self.assertRaises(ValueError):
            parse_write_config(self.make_command(5, [1, 2, 3]))
        with self.assertRaises(ValueError):
            parse_write_config(self.make_command(5, [1, 2, 3, 4, 5]))

    def test_field_ranges(self):
        with self.assertRaises(ValueError):
            parse_write_config(self.make_command(2, [256]))
        with self.assertRaises(ValueError):
            parse_write_config(self.make_command(1, [], head=256))
        with self.assertRaises(ValueError):
            parse_write_config(self.make_command(1, [], eom_index=1))

    def test_phase_global_eom_range(self):
        cfg = parse_write_config(self.make_command(5, [0, 0, 0, 0],
                                                   phase_shift=1,
                                                   eom_index=127 * 5 - 1))
        self.assertEqual(cfg["eom_index"], 634)
        with self.assertRaises(ValueError):
            parse_write_config(self.make_command(5, [0, 0, 0, 0],
                                                       phase_shift=1,
                                                       eom_index=127 * 5))

    def test_reserved_prbs_fields_are_not_udp_arguments(self):
        cfg = parse_write_config(self.make_command(2, [0], phase_shift=1,
                                                  pattern127=0))
        words = pack_record(cfg)
        self.assertEqual(words[1], 0)
        self.assertEqual(words[2] & ((0xFF << 5) | (1 << 15)), 0)
        self.assertEqual(phase_count(cfg["pattern127"], cfg["phase_shift"]), 63)

    def test_legacy_udp_argument_shape_is_rejected(self):
        legacy = "WRITE_CONFIG 0 0 1 0 0 0 0 0 0 1 0 0 0 1 2 3 4"
        with self.assertRaises(ValueError):
            parse_write_config(legacy)

        source = (ROOT / "vitis_bringup/bringup/src/laser_udp_server.c").read_text(
            encoding="utf-8")
        self.assertNotIn("seed_reserved", source)
        self.assertNotIn("prbs_reserved", source)
        self.assertNotIn("source_reserved", source)

    def test_eom_and_soa_share_one_generator_window(self):
        generator = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/tx_eom_window_generator.v").read_text(
            encoding="utf-8")
        core = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v").read_text(
            encoding="utf-8")
        sync = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/sync_signal_gen.v").read_text(
            encoding="utf-8")
        self.assertIn("assign soa_gate_out = eom_out;", generator)
        self.assertIn(".eom_out(eom_out), .soa_gate_out(soa_gate_out)", core)
        self.assertNotIn("soa_gate_out", sync)

    def test_record_layout_crc_and_reserved_slots(self):
        cfg = parse_write_config(self.make_command(5, [1, 2, 63, 255],
                                                   head=65, phase_shift=1,
                                                   eom_index=17))
        words = pack_record(cfg)
        self.assertEqual(len(words), 16)
        self.assertEqual(words[4], 0xFF3F0201)
        self.assertEqual(words[5], 0)
        self.assertEqual(words[7] >> 24, 0)
        self.assertEqual(words[12] >> 31, 0)
        payload = b"".join(struct.pack("<I", word) for word in words[1:15])
        self.assertEqual(words[15], zlib.crc32(payload) & 0xFFFFFFFF)

    def test_production_source_has_only_v2_protocol(self):
        sources = [
            ROOT / "vitis_bringup/bringup/src/laser_bram.c",
            ROOT / "vitis_bringup/bringup/src/laser_udp_server.c",
            ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/config_loader.v",
        ]
        text = "\n".join(path.read_text(encoding="utf-8") for path in sources)
        self.assertNotIn("WRITE_CONFIG_V2", text)
        self.assertNotIn("insert_after", text)
        self.assertIn("LASER_TX_RECORD_WORD_COUNT        16U", (ROOT / "vitis_bringup/bringup/src/laser_bram.h").read_text(encoding="utf-8"))

    def test_removed_prbs_golden_vectors_are_configured_patterns(self):
        self.assertEqual(legacy_prbs_period(6, 0x5A),
                         0x376938BCA3083F56)
        self.assertEqual(legacy_prbs_period(7, 0x5A),
                         0x491C2F95CD13C50C103FAA6774B1BDAD)
        cases = (ROOT / "vitis_bringup/bringup/src/laser_config_cases.c").read_text(
            encoding="utf-8").lower()
        for word in ("a3083f56", "376938bc", "74b1bdad", "103faa67",
                     "cd13c50c", "491c2f95"):
            self.assertIn(word, cases)

    def test_production_rtl_has_no_internal_prbs_source(self):
        core_dir = ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core"
        core = (core_dir / "laser_tx_core.v").read_text(encoding="utf-8")
        loader = (core_dir / "config_loader.v").read_text(encoding="utf-8")
        project = (ROOT / "laser_tx.xpr").read_text(encoding="utf-8")
        self.assertFalse((core_dir / "pattern_source.v").exists())
        for token in ("u_pattern_source", "source_sel_tx", "prbs_order_tx",
                      "seed_tx"):
            self.assertNotIn(token, core)
        self.assertNotIn("pattern_source.v", project)
        self.assertIn("configured_pattern", loader)

    def test_scope_debug_outputs_are_observation_only(self):
        engine = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/pattern_tx_engine.v").read_text(encoding="utf-8")
        core = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v").read_text(encoding="utf-8")
        scope = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/tx_scope_debug_outputs.v").read_text(encoding="utf-8")
        top = (ROOT / "rtl/laser_tx_board_top.v").read_text(encoding="utf-8")
        xdc = (ROOT / "constraints/laser_tx_board_io.xdc").read_text(encoding="utf-8")

        self.assertIn("first_sequence_word_fire", engine)
        self.assertIn("current_first_sequence_q &&", engine)
        self.assertIn("(|current_append_plan_mask_q)", engine)
        self.assertIn(".SYNC_WIDTH_CYCLES(16)", core)
        self.assertIn('ODDR #(', scope)
        self.assertIn('.D1 (1\'b1)', scope)
        self.assertIn('.D2 (1\'b0)', scope)
        self.assertIn("gt_sequence_sync_out", top)
        self.assertIn("txusrclk2_monitor_out", top)
        self.assertIn("PACKAGE_PIN AE17 [get_ports gt_sequence_sync_out]", xdc)
        self.assertIn("PACKAGE_PIN AD15 [get_ports txusrclk2_monitor_out]", xdc)

    def test_gpio9_monitor_ila_bus_is_tx_domain_observation_only(self):
        core = (ROOT / "laser_tx.srcs/sources_1/new/laser_tx_core/laser_tx_core.v").read_text(encoding="utf-8")
        expected_order = (
            "enable_gpio_meta,      // [9]\n"
            "        eom_clock_safe_meta,   // [8]\n"
            "        scope_sync_reset_tx,   // [7]\n"
            "        enable_tx,             // [6]\n"
            "        eom_clock_safe_tx,     // [5]\n"
            "        rate_block_tx,         // [4]\n"
            "        gt_ready,              // [3]\n"
            "        enable_gpio_tx,        // [2]\n"
            "        soft_reset_tx,         // [1]\n"
            "        tx_rst                 // [0]"
        )
        self.assertIn("output wire [9:0]  dbg_gpio9_tx_bus", core)
        self.assertIn("assign dbg_gpio9_tx_bus = {", core)
        self.assertIn(expected_order, core)

        bd_script = (ROOT / "scripts/bd_add_laser_ila.tcl").read_text(encoding="utf-8")
        refresh_script = (ROOT / "scripts/refresh_tx_sequence_v2_bd_module_refs.tcl").read_text(encoding="utf-8")
        self.assertIn("laser_get_or_create_ila ila_laser_tx 16", bd_script)
        self.assertIn("dbg_gpio9_tx_bus ila_laser_tx/probe15", bd_script)
        self.assertIn("CONFIG.C_PROBE15_WIDTH {10}", refresh_script)


if __name__ == "__main__":
    unittest.main(verbosity=2)

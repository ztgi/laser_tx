import binascii
import json
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class DescriptorSpecTest(unittest.TestCase):
    def test_generated_files_are_current_and_crc_matches_golden(self):
        subprocess.run(["python", str(ROOT / "scripts/generate_dynamic_rate_descriptor.py")],
                       check=True, cwd=ROOT)
        spec = json.loads((ROOT / "generated/dynamic_rate_descriptor_spec.json").read_text())
        self.assertEqual(spec["magic"], 0x31505452)
        self.assertEqual(spec["descriptor_words"], 64)
        self.assertEqual(spec["max_mmcm_writes"], 16)
        words = [0] * spec["descriptor_words"]
        words[0] = spec["magic"]
        words[1] = (spec["descriptor_words"] << 16) | spec["version"]
        words[2] = 0x12345678
        payload = b"".join(w.to_bytes(4, "little") for i, w in enumerate(words) if i != 3)
        self.assertEqual(binascii.crc32(payload) & 0xFFFFFFFF, 0x3C66E160)


if __name__ == "__main__":
    unittest.main()

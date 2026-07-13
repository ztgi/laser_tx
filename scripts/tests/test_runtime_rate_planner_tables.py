import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "generate_runtime_rate_planner_tables.py"


class RuntimeRatePlannerTableTests(unittest.TestCase):
    def test_deterministic_generated_tables(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            subprocess.run([sys.executable, str(SCRIPT), "--output-dir", first],
                           cwd=ROOT, check=True, capture_output=True, text=True)
            subprocess.run([sys.executable, str(SCRIPT), "--output-dir", second],
                           cwd=ROOT, check=True, capture_output=True, text=True)
            first_path, second_path = Path(first), Path(second)
            self.assertEqual(sorted(p.name for p in first_path.iterdir()),
                             sorted(p.name for p in second_path.iterdir()))
            for path in first_path.iterdir():
                self.assertEqual(path.read_bytes(), (second_path / path.name).read_bytes())

    def test_manifest_has_legal_sets_not_target_profiles(self):
        data = json.loads((ROOT / "generated" / "runtime_rate_planner_manifest.json").read_text())
        self.assertEqual(data["ad9528_config_count"], 1319)
        self.assertEqual(data["cpll_tuple_count"], 80)
        self.assertEqual(data["qpll_tuple_count"], 160)
        self.assertEqual(data["gt_tuple_count"], 240)
        self.assertEqual(data["mmcm_recipe_count"], 63)
        self.assertEqual(data["mmcm_write_count"], 15)
        self.assertEqual(data["target_profiles_generated"], 0)
        self.assertEqual(data["fixed_3000m_cpll_state"], "BLOCKED")

    def test_generated_c_tables_do_not_allocate_rate_ids(self):
        text = "\n".join(path.read_text(encoding="utf-8")
                         for path in (ROOT / "generated").glob("*.c"))
        self.assertNotIn("RATE_ID", text)
        self.assertNotIn("3000M", text)


if __name__ == "__main__":
    unittest.main()

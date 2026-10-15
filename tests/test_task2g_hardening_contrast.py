"""Acceptance checks for the safe, temporary-file hardening contrast demo."""

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEMO = ROOT / "linux/appliance/hardening_contrast_demo.py"


class HardeningContrastTests(unittest.TestCase):
    def test_all_four_control_cases_pass(self):
        result = subprocess.run(["python3", str(DEMO)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("temporary host files; no board or block device access", result.stdout)
        self.assertIn("Valid signed release", result.stdout)
        self.assertIn("Tampered release", result.stdout)
        self.assertIn("Interrupted update", result.stdout)
        self.assertIn("Trial health failure", result.stdout)
        self.assertEqual(result.stdout.count("| PASS"), 4, result.stdout)
        self.assertIn("not secure-boot or target proof", result.stdout)


if __name__ == "__main__":
    unittest.main()

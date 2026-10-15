"""Host-run control check for the C source deployed to ZCU102 Linux."""

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts/build_task2g_board_demo.py"
SOURCE = ROOT / "linux/appliance/hardening_contrast_board.c"
INCLUDES = ROOT / ".build/task2g_board"


class BoardDemoHostCheck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["python3", str(BUILDER)], check=True, capture_output=True, text=True)

    def test_board_demo_control_cases(self):
        with tempfile.TemporaryDirectory(prefix="msu2-board-demo-host-") as temp:
            executable = Path(temp) / "hardening_contrast_host"
            subprocess.run([
                "gcc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                "-D_FORTIFY_SOURCE=2", "-I", str(INCLUDES), str(SOURCE),
                "-ldl", "-o", str(executable),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=False, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(result.stdout.count("| PASS"), 4, result.stdout)
        self.assertIn("Overall: PASS (0 failures)", result.stdout)
        self.assertIn("not verified boot or hardware-rooted key proof", result.stdout)


if __name__ == "__main__":
    unittest.main()

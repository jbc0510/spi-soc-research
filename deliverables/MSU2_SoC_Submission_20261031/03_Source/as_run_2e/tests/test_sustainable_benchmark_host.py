import csv
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SustainableBenchmarkHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="task2e-sustain-")
        cls.work = Path(cls.temp.name)
        cls.runner = cls.work / "spi_sustainable_benchmark"
        cls.mock = cls.work / "mock_spi_ioctl.so"
        subprocess.run([
            "cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
            "-I", str(ROOT / "common"),
            str(ROOT / "linux/src/spi_sustainable_benchmark.c"),
            "-lm", "-o", str(cls.runner),
        ], check=True)
        subprocess.run([
            "cc", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
            str(ROOT / "tests/fixtures/task2e_mock_spi_ioctl.c"),
            "-o", str(cls.mock),
        ], check=True)
        cls.device = cls.work / "mock-spidev"
        cls.device.touch()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_mock(self, payload, seconds, failure=None):
        env = os.environ.copy()
        env["LD_PRELOAD"] = str(self.mock)
        if failure:
            env["MSU2_MOCK_SPI_FAILURE"] = failure
        else:
            env.pop("MSU2_MOCK_SPI_FAILURE", None)
        return subprocess.run(
            [str(self.runner), str(self.device), str(payload), str(seconds)],
            env=env, capture_output=True, text=True, check=False,
        )

    def parse_record(self, result):
        rows = [line for line in result.stdout.splitlines() if line.startswith("repetition,payload_bytes,")]
        self.assertEqual(len(rows), 1, result.stdout)
        index = result.stdout.splitlines().index(rows[0])
        return next(csv.DictReader(result.stdout.splitlines()[index:]))

    def test_echo_loop_completes_window_and_counts_verified_bytes(self):
        result = self.run_mock(64, 1)
        self.assertEqual(result.returncode, 0, result.stderr)
        row = self.parse_record(result)
        self.assertAlmostEqual(float(row["window_s"]), 1.0, delta=0.03)
        self.assertGreater(int(row["verified_transfers"]), 0)
        self.assertEqual(row["verified_transfers"], row["attempts"])
        self.assertEqual(int(row["verified_bytes"]), 64 * int(row["verified_transfers"]))
        self.assertEqual(int(row["api_errors"]), 0)
        self.assertEqual(int(row["mismatches"]), 0)
        self.assertEqual(row["cpu_metric_kind"], "thread_cpu_share")

    def test_api_error_stops_point_and_is_nonzero(self):
        result = self.run_mock(8, 5, "api")
        self.assertEqual(result.returncode, 1, result.stdout)
        row = self.parse_record(result)
        self.assertEqual(int(row["attempts"]), 1)
        self.assertEqual(int(row["api_errors"]), 1)

    def test_receive_mismatch_stops_point_and_is_nonzero(self):
        result = self.run_mock(8, 5, "mismatch")
        self.assertEqual(result.returncode, 1, result.stdout)
        row = self.parse_record(result)
        self.assertEqual(int(row["attempts"]), 1)
        self.assertEqual(int(row["mismatches"]), 1)
        self.assertEqual(int(row["verified_transfers"]), 0)
        self.assertEqual(int(row["verified_bytes"]), 0)

    def test_invalid_payload_and_window_fail_before_device_access(self):
        invalid_payload = subprocess.run(
            [str(self.runner), "/not/a/device", "3", "1"],
            capture_output=True, text=True, check=False,
        )
        invalid_window = subprocess.run(
            [str(self.runner), "/not/a/device", "8", "0"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(invalid_payload.returncode, 2)
        self.assertEqual(invalid_window.returncode, 2)
        self.assertNotIn("open SPI device", invalid_payload.stderr)
        self.assertNotIn("open SPI device", invalid_window.stderr)


if __name__ == "__main__":
    unittest.main()

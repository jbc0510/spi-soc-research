"""Host-only fault injection. Does not access a SPI controller or board."""
import csv
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CC = os.environ.get("CC", "clang")
MOCK = r'''
#include <errno.h>
#include <linux/spi/spidev.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
int __wrap_open(const char *path, int flags, ...) { (void)path; (void)flags; return 999; }
int __real_close(int fd);
int __wrap_close(int fd) { return fd == 999 ? 0 : __real_close(fd); }
int __wrap_ioctl(int fd, unsigned long req, ...) {
    (void)fd;
    va_list ap; va_start(ap, req); void *arg = va_arg(ap, void *); va_end(ap);
    if (req == SPI_IOC_RD_MODE32) { *(uint32_t *)arg = getenv("MOCK_BAD_MODE") ? 1 : 0; return 0; }
    if (req == SPI_IOC_RD_BITS_PER_WORD) { *(uint8_t *)arg = 8; return 0; }
    if (req == SPI_IOC_RD_MAX_SPEED_HZ) { *(uint32_t *)arg = 15623438; return 0; }
    if (req != SPI_IOC_MESSAGE(1)) return 0;
    struct spi_ioc_transfer *tr = arg;
    static unsigned trial;
    unsigned t = trial++ % 1000;
    uint8_t *tx = (void *)(uintptr_t)tr->tx_buf;
    uint8_t *rx = (void *)(uintptr_t)tr->rx_buf;
    for (unsigned i = 0; i < tr->len; ++i)
        if (tx[i] != (uint8_t)i || rx[i] != (uint8_t)(tx[i] ^ 255)) abort();
    if (getenv("MOCK_CLEAN")) { memcpy(rx, tx, tr->len); return tr->len; }
    if (getenv("MOCK_ALL_FAIL") || t == 0) { errno = EIO; return -1; }
    if (t == 1) { errno = ETIMEDOUT; return -1; }
    if (t == 2) return tr->len - 1;
    memcpy(rx, tx, tr->len);
    if (t == 3) rx[0] ^= 255;
    return tr->len;
}
'''


class Phase1(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="spi-phase1-")
        cls.work = Path(cls.temp.name)
        mock = cls.work / "mock.c"
        mock.write_text(MOCK)
        cls.binary = cls.work / "linux-mocked"
        subprocess.run([CC, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(ROOT / "common"),
                        str(ROOT / "linux/src/spi_benchmark_v3_rxverify.c"), str(mock),
                        "-Wl,--wrap=open,--wrap=ioctl,--wrap=close", "-lm",
                        "-o", str(cls.binary)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def rows(self, all_fail=False, clean=False):
        env = dict(os.environ)
        for key in ("MOCK_ALL_FAIL", "MOCK_CLEAN", "MOCK_BAD_MODE"):
            env.pop(key, None)
        if all_fail:
            env["MOCK_ALL_FAIL"] = "1"
        if clean:
            env["MOCK_CLEAN"] = "1"
        run = subprocess.run([str(self.binary)], env=env, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0 if clean else 1, run.stderr)
        text = run.stdout.split("---CSV-BEGIN---\n")[1].split("---CSV-END---")[0]
        return list(csv.DictReader(io.StringIO("\n".join(
            line for line in text.splitlines() if not line.startswith("#")))))

    def test_fault_accounting_and_rx_poison(self):
        rows = self.rows()
        self.assertEqual([int(r["payload_bytes"]) for r in rows],
                         [1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536])
        for r in rows:
            for key, expected in {"attempt_count": 1000, "api_success_count": 997,
                                  "timed_success_count": 996, "api_error_count": 3,
                                  "timeout_count": 1, "rx_mismatch_count": 1,
                                  "short_return_count": 1, "first_mismatch_trial": 3,
                                  "first_mismatch_offset": 0, "first_expected": 0,
                                  "first_actual": 255, "first_failure_trial": 0}.items():
                self.assertEqual(int(r[key]), expected, (key, r))
            self.assertEqual(r["first_failure_kind"], "ioctl_errno")
            self.assertGreaterEqual(float(r["avg_ns"]), float(r["min_ns"]))
            self.assertLessEqual(float(r["avg_ns"]), float(r["max_ns"]))

    def test_no_valid_samples(self):
        for r in self.rows(all_fail=True):
            self.assertEqual(int(r["api_error_count"]), 1000)
            self.assertEqual(int(r["timed_success_count"]), 0)
            for key in ("min_ns", "avg_ns", "max_ns", "stddev_ns"):
                self.assertEqual(float(r[key]), -1)

    def test_clean_mock_sweep(self):
        for r in self.rows(clean=True):
            self.assertEqual(int(r["attempt_count"]), 1000)
            self.assertEqual(int(r["timed_success_count"]), 1000)
            self.assertEqual(int(r["rx_mismatch_count"]), 0)
            self.assertEqual(r["first_failure_kind"], "none")

    def test_mode_readback_mismatch_aborts(self):
        run = subprocess.run([str(self.binary)], env=dict(os.environ, MOCK_BAD_MODE="1"),
                             capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertNotIn("---CSV-BEGIN---", run.stdout)

    def test_known_population_variance(self):
        src = self.work / "stats.c"
        src.write_text('''#include "spi_benchmark_contract.h"
int main(void) {
    SpiBenchResult r = spi_bench_result();
    spi_bench_sample(&r, 10); spi_bench_sample(&r, 20); spi_bench_sample(&r, 30);
    return !(r.samples == 3 && r.minimum == 10 && r.maximum == 30 &&
             r.mean == 20 && fabs(sqrt(r.m2 / r.samples) - sqrt(200.0 / 3)) < 1e-9);
}
''')
        binary = self.work / "stats"
        subprocess.run([CC, "-std=c11", "-Wall", "-Wextra", "-Werror",
                        "-I" + str(ROOT / "common"), str(src), "-lm", "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    unittest.main()

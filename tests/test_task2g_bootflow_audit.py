import unittest

from scripts.task2g_audit_bootflow import audit_script, extract_legacy_script


class BootflowAuditTests(unittest.TestCase):
    def test_detects_raw_boot_and_external_environment_fallbacks(self):
        text = "bootm ${fit_addr}; env import -t ${loadaddr} ${filesize}; booti ${kernel_addr} - ${fdt_addr}; setenv kernel_name=Image"
        codes = {finding["code"] for finding in audit_script(text)}
        self.assertTrue({"raw-kernel-boot", "separate-kernel-path", "environment-import"} <= codes)

    def test_fit_only_script_has_no_bypass_finding(self):
        self.assertEqual([], audit_script("fatload mmc ${devnum}:${part} ${loadaddr} image.ub; bootm ${loadaddr}"))

    def test_extracts_plain_text(self):
        self.assertEqual("bootm ${fit_addr}", extract_legacy_script(b"bootm ${fit_addr}\0\n"))


if __name__ == "__main__":
    unittest.main()

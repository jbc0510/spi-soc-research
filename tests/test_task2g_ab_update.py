"""Fault-injection tests for the host-only Task 2g A/B update prototype.

These tests exercise file-backed reference behavior. They do not validate
U-Boot, SD-card power-loss behavior, or the ZCU102 secure-boot chain.
"""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "linux/appliance/ab_update_prototype.py"


class ABUpdatePrototypeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="msu2-task2g-")
        self.root = Path(self.temp.name)
        self.state = self.root / "boot-state.json"
        self.slot_a = self.root / "slot-a.img"
        self.slot_b = self.root / "slot-b.img"
        self.payload = self.root / "release.img"
        self.private_key = self.root / "test-private.pem"
        self.public_key = self.root / "test-public.pem"
        self.signature = self.root / "release.sig"
        self.slot_a.write_bytes(b"A" * 4096)
        self.slot_b.write_bytes(b"B" * 4096)
        self.payload.write_bytes(bytes(range(256)) * 8)
        self.state.write_text(json.dumps({
            "confirmed_slot": "A", "pending_slot": None,
            "boot_attempts": 0, "boot_limit": 2,
        }))
        subprocess.run([
            "openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt",
            "rsa_keygen_bits:2048", "-out", str(self.private_key),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([
            "openssl", "pkey", "-in", str(self.private_key), "-pubout",
            "-out", str(self.public_key),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.resign()

    def tearDown(self):
        self.temp.cleanup()

    def resign(self):
        subprocess.run([
            "openssl", "dgst", "-sha256", "-sign", str(self.private_key),
            "-out", str(self.signature), str(self.payload),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def run_tool(self, *args, expected=0):
        result = subprocess.run(
            ["python3", str(TOOL), *map(str, args)],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def stage_args(self):
        return (
            "stage", "--state", self.state, "--slot-a", self.slot_a,
            "--slot-b", self.slot_b, "--payload", self.payload,
            "--signature", self.signature, "--public-key", self.public_key,
        )

    def read_state(self):
        return json.loads(self.state.read_text())

    def test_valid_release_stages_inactive_slot_and_confirms(self):
        self.run_tool(*self.stage_args())
        state = self.read_state()
        self.assertEqual(state["confirmed_slot"], "A")
        self.assertEqual(state["pending_slot"], "B")
        self.assertEqual(self.slot_b.read_bytes()[:self.payload.stat().st_size],
                         self.payload.read_bytes())
        self.run_tool("select", "--state", self.state)
        self.run_tool("mark-good", "--state", self.state)
        state = self.read_state()
        self.assertEqual(state["confirmed_slot"], "B")
        self.assertIsNone(state["pending_slot"])

    def test_invalid_signature_does_not_change_slots_or_state(self):
        original_state = self.state.read_bytes()
        original_slots = (self.slot_a.read_bytes(), self.slot_b.read_bytes())
        self.signature.write_bytes(b"not-a-signature")
        self.run_tool(*self.stage_args(), expected=3)
        self.assertEqual(self.state.read_bytes(), original_state)
        self.assertEqual((self.slot_a.read_bytes(), self.slot_b.read_bytes()),
                         original_slots)

    def test_interrupted_inactive_write_keeps_confirmed_slot_and_no_pending(self):
        original_a = self.slot_a.read_bytes()
        self.run_tool(*self.stage_args(), "--fail-after-bytes", "512", expected=3)
        state = self.read_state()
        self.assertEqual(state["confirmed_slot"], "A")
        self.assertIsNone(state["pending_slot"])
        self.assertEqual(self.slot_a.read_bytes(), original_a)
        self.assertEqual(self.slot_b.read_bytes()[:512], self.payload.read_bytes()[:512])
        self.assertEqual(self.slot_b.read_bytes()[512:], b"B" * (4096 - 512))
        selected = self.run_tool("select", "--state", self.state)
        self.assertIn("slot=A confirmed=1", selected.stdout)

    def test_boot_limit_rolls_back_and_health_rejection_keeps_confirmed(self):
        self.run_tool(*self.stage_args())
        first = self.run_tool("select", "--state", self.state)
        second = self.run_tool("select", "--state", self.state)
        third = self.run_tool("select", "--state", self.state)
        self.assertIn("trial=1/2", first.stdout)
        self.assertIn("trial=2/2", second.stdout)
        self.assertIn("rollback=boot_limit", third.stdout)
        self.assertEqual(self.read_state()["confirmed_slot"], "A")

        self.run_tool(*self.stage_args())
        self.run_tool("mark-bad", "--state", self.state)
        state = self.read_state()
        self.assertEqual(state["confirmed_slot"], "A")
        self.assertIsNone(state["pending_slot"])


if __name__ == "__main__":
    unittest.main()

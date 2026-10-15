#!/usr/bin/env python3
"""Compare a deliberately unsafe updater with the Task 2g A/B reference.

This is a host-only teaching model. It creates all files under TemporaryDirectory
and cannot target block devices or the ZCU102. The baseline is intentionally
unsafe and exists only to make the control differences visible.
"""

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UPDATER = ROOT / "linux/appliance/ab_update_prototype.py"
PAYLOAD = b"MSU-2 signed release image v1\n" * 32


def run(command, expected=None):
    result = subprocess.run(command, capture_output=True, text=True)
    if expected is not None and result.returncode != expected:
        raise RuntimeError(f"command failed ({result.returncode}): {result.stderr}")
    return result


def create_keys(root):
    private, public = root / "test-private.pem", root / "test-public.pem"
    run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt",
         "rsa_keygen_bits:2048", "-out", str(private)], 0)
    run(["openssl", "pkey", "-in", str(private), "-pubout", "-out", str(public)], 0)
    return private, public


def hardened_case(root, payload, signature, public, fail_after=None, reject_health=False):
    state, a, b = root / "state.json", root / "slot-a.img", root / "slot-b.img"
    state.write_text(json.dumps({"confirmed_slot": "A", "pending_slot": None,
                                 "boot_attempts": 0, "boot_limit": 2}))
    a.write_bytes(b"CONFIRMED-A\n" + b"a" * 4096)
    b.write_bytes(b"OLD-B\n" + b"b" * 4096)
    original_b = b.read_bytes()
    cmd = ["python3", str(UPDATER), "stage", "--state", str(state), "--slot-a", str(a),
           "--slot-b", str(b), "--payload", str(payload), "--signature", str(signature),
           "--public-key", str(public)]
    if fail_after is not None:
        cmd += ["--fail-after-bytes", str(fail_after)]
    staged = run(cmd)
    state_value = json.loads(state.read_text())
    if staged.returncode != 0:
        intact = (state_value["confirmed_slot"] == "A" and state_value["pending_slot"] is None
                  and a.read_bytes().startswith(b"CONFIRMED-A"))
        if fail_after is None:
            intact = intact and b.read_bytes() == original_b
        return "reject; A intact", intact
    if reject_health:
        run(["python3", str(UPDATER), "mark-bad", "--state", str(state)], 0)
        state_value = json.loads(state.read_text())
        return "rollback; A selected", state_value["confirmed_slot"] == "A" and state_value["pending_slot"] is None
    return "accept; B trial", state_value["pending_slot"] == "B"


def baseline_case(payload, tamper=False, interrupt=False, health_fail=False):
    """Unsafe behavior: trust any bytes, overwrite A, no pending/rollback state."""
    active = bytearray(b"CONFIRMED-A\n" + b"a" * 4096)
    update = bytearray(payload)
    if tamper:
        update[0] ^= 0xFF
    if interrupt:
        active[:16] = update[:16]
        return "partial overwrite; A damaged", not active.startswith(b"CONFIRMED-A")
    active[:len(update)] = update
    if health_fail:
        return "bad image remains active", not active.startswith(b"CONFIRMED-A")
    if tamper:
        return "tampered image accepted", active[:len(update)] == update
    return "image accepted in place", active[:len(update)] == update


def main():
    with tempfile.TemporaryDirectory(prefix="msu2-hardening-contrast-") as temp:
        root = Path(temp)
        private, public = create_keys(root)
        payload_path, sig_path = root / "release.img", root / "release.sig"
        payload_path.write_bytes(PAYLOAD)
        run(["openssl", "dgst", "-sha256", "-sign", str(private), "-out", str(sig_path), str(payload_path)], 0)
        cases = [
            ("Valid signed release", {}, {}),
            ("Tampered release", {"tamper": True}, {}),
            ("Interrupted update", {"interrupt": True}, {"fail_after": 12}),
            ("Trial health failure", {"health_fail": True}, {"reject_health": True}),
        ]
        rows = []
        for label, baseline_options, hardened_options in cases:
            case_root = root / label.lower().replace(" ", "-")
            case_root.mkdir()
            bad_payload = root / f"{len(rows)}-release.img"
            bad_signature = root / f"{len(rows)}-release.sig"
            bad_payload.write_bytes(PAYLOAD)
            bad_signature.write_bytes(sig_path.read_bytes())
            if baseline_options.get("tamper"):
                bad_payload.write_bytes(bytes([PAYLOAD[0] ^ 0xFF]) + PAYLOAD[1:])
            base_result, base_proves = baseline_case(PAYLOAD, **baseline_options)
            hard_result, hard_proves = hardened_case(
                case_root, bad_payload, bad_signature, public, **hardened_options)
            rows.append((label, base_result, hard_result, "PASS" if base_proves and hard_proves else "FAIL"))

        print("MODEL-ONLY DEMO — temporary host files; no board or block device access")
        print(f"Release SHA-256: {hashlib.sha256(PAYLOAD).hexdigest()}")
        print(f"{'Scenario':<24} | {'Baseline (unsafe)':<34} | {'Hardened reference':<28} | Check")
        print("-" * 112)
        for row in rows:
            print(f"{row[0]:<24} | {row[1]:<34} | {row[2]:<28} | {row[3]}")
        if any(row[3] != "PASS" for row in rows):
            raise SystemExit(1)
        print("\nScope: demonstrates updater control-flow differences only; not secure-boot or target proof.")


if __name__ == "__main__":
    main()

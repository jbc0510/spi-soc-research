#!/usr/bin/env python3
"""Verify a PetaLinux signed FIT using the generated U-Boot control DTB."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str], log: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    log.write_text(result.stdout, encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fit", type=Path, required=True)
    parser.add_argument("--control-dtb", type=Path, required=True)
    parser.add_argument("--fit-check-sign", type=Path, required=True)
    parser.add_argument("--dumpimage", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "results/task2g_petalinux_fit_20261015")
    args = parser.parse_args()

    fit, control = args.fit.resolve(), args.control_dtb.resolve()
    verifier, dumpimage = args.fit_check_sign.resolve(), args.dumpimage.resolve()
    fdtget_path = shutil.which("fdtget")
    output = args.output.resolve()
    for required in (fit, control, verifier, dumpimage):
        if not required.is_file():
            parser.error(f"missing input: {required}")
    if not fdtget_path:
        parser.error("fdtget is required to audit the U-Boot required-key property")
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fit, output / "image.ub")
    shutil.copy2(control, output / "u-boot-control.dtb")

    key_props = run([fdtget_path, "-p", str(control), "/signature/key-msu2-test"],
                    output / "required_key_audit.log")
    key_algo = run([fdtget_path, "-t", "s", str(control), "/signature/key-msu2-test", "algo"],
                   output / "required_key_algorithm.log")
    if key_props.returncode != 0 or "required" not in key_props.stdout.split():
        raise SystemExit("U-Boot control DTB does not mark key-msu2-test as required")
    if key_algo.returncode != 0 or "sha256,rsa2048" not in key_algo.stdout:
        raise SystemExit("U-Boot control DTB does not select the expected RSA-2048/SHA-256 key")

    signature_log = output / "signature_verification.log"
    verified = run([str(verifier), "-f", str(fit), "-k", str(control),
                    "-c", "conf-system-top.dtb"], signature_log)
    if verified.returncode != 0 or "Signature check OK" not in verified.stdout:
        raise SystemExit("the PetaLinux FIT signature did not verify")

    with tempfile.TemporaryDirectory(prefix="task2g-fit-check-") as temp:
        kernel = Path(temp) / "kernel.gz"
        extracted = run([str(dumpimage), "-T", "flat_dt", "-p", "0", "-o",
                         str(kernel), str(fit)], output / "kernel_extract.log")
        if extracted.returncode != 0 or not kernel.is_file():
            raise SystemExit("could not extract kernel subimage from FIT")
        payload = kernel.read_bytes()
        blob = bytearray(fit.read_bytes())
        offset = blob.find(payload)
        if offset < 0:
            raise SystemExit("could not locate extracted kernel payload in FIT")
        tampered = output / "tampered-image.ub"
        blob[offset + len(payload) // 2] ^= 1
        tampered.write_bytes(blob)

    tamper_log = output / "tampered_verification.log"
    rejected = run([str(verifier), "-f", str(tampered), "-k", str(control),
                    "-c", "conf-system-top.dtb"], tamper_log)
    if rejected.returncode == 0 or "Signature check OK" in rejected.stdout:
        raise SystemExit("tampered FIT was not rejected")

    summary = {
        "result": "PASS",
        "fit_configuration": "conf-system-top.dtb",
        "signature_verification": "PASS (U-Boot fit_check_sign)",
        "tampered_kernel_payload": "REJECTED (signature/hash verification failed)",
        "fit_sha256": sha256(output / "image.ub"),
        "control_dtb_sha256": sha256(output / "u-boot-control.dtb"),
        "required_key_node": "PASS (/signature/key-msu2-test has required property)",
        "key_algorithm": key_algo.stdout.strip(),
        "tampered_fit_sha256": sha256(tampered),
        "claim_boundary": "Host verification of a PetaLinux-generated signed FIT. Does not prove this U-Boot or FIT was booted on ZCU102, BootROM/FSBL authentication, secure key provisioning, A/B slot behavior, or power-loss recovery.",
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    evidence = [path for path in sorted(output.iterdir()) if path.is_file() and path.name != "SHA256SUMS"]
    (output / "SHA256SUMS").write_text("\n".join(f"{sha256(path)}  {path.name}" for path in evidence) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

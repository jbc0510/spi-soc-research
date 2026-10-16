#!/usr/bin/env python3
"""Exercise required FIT signatures with the pinned U-Boot sandbox runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BUILD = ROOT / ".build/uboot-task2g-sandbox"
DEFAULT_OUTPUT = ROOT / "results/task2g_uboot_fit_sandbox_20261015"


def run(command: list[str], *, cwd: Path, env: dict[str, str], log: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log:
        log.write_text(result.stdout, encoding="utf-8")
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
    parser.add_argument("--source-dir", type=Path, default=ROOT / ".build/uboot-task2g-source")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    build = args.build_dir.resolve()
    source = args.source_dir.resolve()
    output = args.output_dir.resolve()
    for required in (build / "u-boot", build / "tools/mkimage",
                     build / "tools/fit_check_sign", build / "arch/sandbox/dts/test.dtb",
                     build / ".config", source / "test/py/tests/vboot/sandbox-kernel.dts"):
        require(required.is_file(), f"missing required U-Boot build input: {required}")
    config = (build / ".config").read_text(encoding="utf-8")
    require("CONFIG_FIT_SIGNATURE=y" in config and "CONFIG_RSA=y" in config,
            "sandbox build does not have FIT RSA signature verification enabled")

    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["PATH"] = str(build / "scripts/dtc") + os.pathsep + env.get("PATH", "")
    report: dict[str, object] = {
        "u_boot_version": "2025.01-xilinx",
        "source_revision": "5e0d8abc7e092b62a5de17aa7aadfad7af5f0f59",
        "configuration": {"FIT_SIGNATURE": True, "RSA": True, "LEGACY_IMAGE_FORMAT": False},
        "tests": {},
        "claim_boundary": "Host U-Boot sandbox test only; it does not validate the board's BootROM, signed BOOT.BIN, eFUSE trust anchor, SD layout, or power-loss recovery.",
    }
    with tempfile.TemporaryDirectory(prefix="task2g-fit-private-", dir=output.parent) as tmp:
        work = Path(tmp)
        keys = work / "keys"
        keys.mkdir()
        kernel = work / "test-kernel.bin"
        kernel.write_bytes(bytes(500))
        fdt_dts = work / "sandbox-kernel.dts"
        fdt_dtb = work / "sandbox-kernel.dtb"
        fdt_dts.write_text('/dts-v1/; / { compatible = "sandbox"; model = "MSU-2 FIT test"; };\n', encoding="utf-8")
        control = output / "test-control.dtb"
        shutil.copy2(build / "arch/sandbox/dts/test.dtb", control)
        its = work / "fit.its"
        its.write_text('''/dts-v1/;
/ {
 description = "MSU-2 Task 2g signed FIT verification test";
 #address-cells = <1>;
 images {
  kernel { data = /incbin/("test-kernel.bin"); type = "kernel_noload"; arch = "sandbox"; os = "linux"; compression = "none"; load = <0x4>; entry = <0x8>; hash-1 { algo = "sha256"; }; };
  fdt-1 { data = /incbin/("sandbox-kernel.dtb"); type = "flat_dt"; arch = "sandbox"; compression = "none"; hash-1 { algo = "sha256"; }; };
 };
 configurations {
  default = "conf-1";
  conf-1 {
   kernel = "kernel";
   fdt = "fdt-1";
   signature { algo = "sha256,rsa2048"; key-name-hint = "dev"; sign-images = "fdt", "kernel"; };
  };
 };
};
''', encoding="utf-8")

        gen_key = run(["openssl", "genpkey", "-algorithm", "RSA", "-out", str(keys / "dev.key"), "-pkeyopt", "rsa_keygen_bits:2048"], cwd=work, env=env)
        require(gen_key.returncode == 0, "test signing key generation failed")
        cert = run(["openssl", "req", "-batch", "-new", "-x509", "-key", str(keys / "dev.key"), "-out", str(keys / "dev.crt"), "-subj", "/CN=MSU2-Task2g-Development-Test/"], cwd=work, env=env)
        require(cert.returncode == 0, "test certificate generation failed")
        dtc = run([str(build / "scripts/dtc/dtc"), "-I", "dts", "-O", "dtb", "-o", str(fdt_dtb), str(fdt_dts)], cwd=work, env=env)
        require(dtc.returncode == 0, "test FDT compilation failed")

        signed = output / "signed-fit.itb"
        sign = run([str(build / "tools/mkimage"), "-f", str(its), "-k", str(keys), "-K", str(control), "-r", str(signed)], cwd=work, env=env, log=output / "mkimage_signed.log")
        require(sign.returncode == 0, "mkimage could not sign the FIT")
        verify = run([str(build / "tools/fit_check_sign"), "-f", str(signed), "-k", str(control), "-c", "conf-1"], cwd=work, env=env, log=output / "fit_check_sign.log")
        require(verify.returncode == 0 and "Signature check OK" in verify.stdout,
                "U-Boot fit_check_sign rejected the authentic FIT")

        unsigned = output / "unsigned-fit.itb"
        unsigned_build = run([str(build / "tools/mkimage"), "-f", str(its), str(unsigned)], cwd=work, env=env)
        require(unsigned_build.returncode == 0, "could not build unsigned negative-control FIT")
        tampered = output / "tampered-fit.itb"
        blob = bytearray(signed.read_bytes())
        offset = blob.find(bytes(500))
        require(offset >= 0, "could not locate test kernel payload in signed FIT")
        blob[offset + 250] = 1
        tampered.write_bytes(blob)

        def bootm_case(name: str, fit: Path) -> tuple[bool, str]:
            command = f"host load hostfs - 100 {fit}; bootm 100"
            result = run([str(build / "u-boot"), "-d", str(control), "-c", command], cwd=work, env=env, log=output / f"uboot_{name}.log")
            accepted = (result.returncode == 0 and
                        "sha256,rsa2048:dev+ OK" in result.stdout and
                        "sandbox: continuing, as we cannot run Linux" in result.stdout)
            return accepted, result.stdout

        accepted, positive_log = bootm_case("valid", signed)
        require(accepted, "U-Boot sandbox did not accept the correctly signed FIT")
        unsigned_accepted, unsigned_log = bootm_case("unsigned", unsigned)
        require(not unsigned_accepted and "Failed to verify required signature" in unsigned_log,
                "U-Boot sandbox did not fail closed for an unsigned FIT")
        tampered_accepted, tampered_log = bootm_case("tampered", tampered)
        require(not tampered_accepted and "Bad Data Hash" in tampered_log,
                "U-Boot sandbox did not reject a modified FIT payload")

        report["tests"] = {
            "signed_fit": {"result": "PASS", "fit_check_sign": "PASS", "bootm_transferred_to_linux_handoff": True},
            "unsigned_fit": {"result": "PASS", "rejected_before_handoff": "Failed to verify required signature" in unsigned_log},
            "tampered_fit": {"result": "PASS", "rejected_before_handoff": "Bad Data Hash" in tampered_log},
        }

    report["artifacts"] = {
        p.name: sha256(p) for p in sorted(output.iterdir()) if p.is_file() and p.name != "SHA256SUMS"
    }
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    lines = [f"{sha256(p)}  {p.relative_to(ROOT)}" for p in sorted(output.iterdir()) if p.is_file() and p.name != "SHA256SUMS"]
    (output / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

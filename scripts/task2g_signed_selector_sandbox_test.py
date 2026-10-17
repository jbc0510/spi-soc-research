#!/usr/bin/env python3
"""Test signed Linux and standalone-program selections in U-Boot sandbox.

This is a host-side integration prototype. It checks that a required-key FIT
can select both a Linux configuration and a standalone SPI-test configuration,
and that modifying the standalone payload is rejected before boot handoff.
It does not validate the ZCU102 BootROM, BOOT.BIN, eFUSE root of trust, or the
board's actual boot menu.
"""

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
BUILD = ROOT / ".build/uboot-task2g-sandbox"
OUTPUT = ROOT / "results/task2g_signed_selector_sandbox_20261017"


def run(command: list[str], *, cwd: Path, env: dict[str, str], log: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(result.stdout, encoding="utf-8")
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=BUILD)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    args = parser.parse_args()
    build, output = args.build_dir.resolve(), args.output_dir.resolve()
    for artifact in (build / "u-boot", build / "tools/mkimage",
                     build / "tools/fit_check_sign", build / "scripts/dtc/dtc",
                     build / "arch/sandbox/dts/test.dtb", build / ".config"):
        require(artifact.is_file(), f"missing sandbox artifact: {artifact}")
    config = (build / ".config").read_text(encoding="utf-8")
    require("CONFIG_FIT_SIGNATURE=y" in config and "CONFIG_RSA=y" in config,
            "U-Boot sandbox lacks FIT RSA signature verification")
    require(not output.exists(), f"refusing to overwrite existing evidence: {output}")
    output.mkdir(parents=True)

    env = os.environ.copy()
    env["PATH"] = str(build / "scripts/dtc") + os.pathsep + env.get("PATH", "")
    report: dict[str, object] = {
        "u_boot_version": "2025.01-xilinx",
        "fit_policy": "required sha256,rsa2048 configuration signatures; legacy image format disabled",
        "tests": {},
        "claim_boundary": "Host U-Boot sandbox only; no ZCU102 BootROM, BOOT.BIN, eFUSE, menu-display, or physical SPI validation.",
    }

    with tempfile.TemporaryDirectory(prefix="task2g-selector-private-", dir=output.parent) as temp:
        work = Path(temp)
        keys = work / "keys"
        keys.mkdir()
        linux = work / "linux-kernel.bin"
        standalone = work / "spi-test.bin"
        fdt_dts, fdt_dtb = work / "linux.dts", work / "linux.dtb"
        linux.write_bytes(bytes(range(1, 251)) * 2)
        standalone.write_bytes(bytes(range(1, 251)) * 4)
        fdt_dts.write_text('/dts-v1/; / { compatible = "sandbox"; model = "MSU-2 signed selector test"; };\n', encoding="utf-8")
        its = work / "selector.its"
        its.write_text('''/dts-v1/;
/ {
 description = "MSU-2 signed dual-mode selector integration test";
 #address-cells = <1>;
 images {
  linux-kernel { data = /incbin/("linux-kernel.bin"); type = "kernel_noload"; arch = "sandbox"; os = "linux"; compression = "none"; load = <0x4>; entry = <0x8>; hash-1 { algo = "sha256"; }; };
  linux-fdt { data = /incbin/("linux.dtb"); type = "flat_dt"; arch = "sandbox"; compression = "none"; hash-1 { algo = "sha256"; }; };
  spi-test { data = /incbin/("spi-test.bin"); type = "firmware"; arch = "sandbox"; os = "u-boot"; compression = "none"; load = <0x100000>; entry = <0x100000>; hash-1 { algo = "sha256"; }; };
 };
 configurations {
  default = "linux";
  linux { kernel = "linux-kernel"; fdt = "linux-fdt"; signature { algo = "sha256,rsa2048"; key-name-hint = "dev"; sign-images = "kernel", "fdt"; }; };
  spi-test { kernel = "spi-test"; signature { algo = "sha256,rsa2048"; key-name-hint = "dev"; sign-images = "kernel"; }; };
 };
};
''', encoding="utf-8")

        key = run(["openssl", "genpkey", "-algorithm", "RSA", "-out", str(keys / "dev.key"), "-pkeyopt", "rsa_keygen_bits:2048"], cwd=work, env=env, log=output / "keygen.log")
        require(key.returncode == 0, "could not generate temporary test key")
        cert = run(["openssl", "req", "-batch", "-new", "-x509", "-key", str(keys / "dev.key"), "-out", str(keys / "dev.crt"), "-subj", "/CN=MSU2-selector-test/"], cwd=work, env=env, log=output / "cert.log")
        require(cert.returncode == 0, "could not generate test certificate")
        dtc = run([str(build / "scripts/dtc/dtc"), "-I", "dts", "-O", "dtb", "-o", str(fdt_dtb), str(fdt_dts)], cwd=work, env=env, log=output / "dtc.log")
        require(dtc.returncode == 0, "could not compile Linux test FDT")
        control = output / "selector-control.dtb"
        shutil.copy2(build / "arch/sandbox/dts/test.dtb", control)
        signed = output / "signed-dual-mode.itb"
        signed_result = run([str(build / "tools/mkimage"), "-f", str(its), "-k", str(keys), "-K", str(control), "-r", str(signed)], cwd=work, env=env, log=output / "mkimage.log")
        require(signed_result.returncode == 0, "could not sign dual-mode FIT")

        verifications: dict[str, bool] = {}
        for conf in ("linux", "spi-test"):
            checked = run([str(build / "tools/fit_check_sign"), "-f", str(signed), "-k", str(control), "-c", conf], cwd=work, env=env, log=output / f"fit_check_sign_{conf}.log")
            verifications[conf] = checked.returncode == 0 and "Signature check OK" in checked.stdout
            require(verifications[conf], f"required-key verifier rejected {conf} configuration")

        def sandbox_boot(name: str, image: Path, conf: str) -> subprocess.CompletedProcess[str]:
            command = f"setenv autostart no; host load hostfs - 100 {image}; bootm 100#{conf}"
            return run([str(build / "u-boot"), "-d", str(control), "-c", command], cwd=work, env=env, log=output / f"uboot_{name}.log")

        linux_boot = sandbox_boot("linux_valid", signed, "linux")
        require(linux_boot.returncode == 0 and "sandbox: continuing, as we cannot run Linux" in linux_boot.stdout,
                "sandbox did not accept the signed Linux selection")
        bm_boot = sandbox_boot("spi_test_valid", signed, "spi-test")
        require(bm_boot.returncode == 0 and "Loading Firmware" in bm_boot.stdout,
                "sandbox did not load the signed standalone-program selection")

        tampered = output / "tampered-standalone.itb"
        modified = bytearray(signed.read_bytes())
        needle = bytes(range(1, 251)) * 4
        offset = modified.find(needle)
        require(offset >= 0, "cannot locate standalone FIT payload for tamper case")
        modified[offset + 150] ^= 0x80
        tampered.write_bytes(modified)
        tampered_boot = sandbox_boot("spi_test_tampered", tampered, "spi-test")
        require(tampered_boot.returncode != 0 and
                ("Bad Data Hash" in tampered_boot.stdout or "Failed to verify required signature" in tampered_boot.stdout),
                "sandbox did not fail closed for modified standalone payload")

        report["tests"] = {
            "linux_config_signature": "PASS",
            "standalone_spi_config_signature": "PASS",
            "signed_linux_selection": "PASS",
            "signed_standalone_selection": "PASS (loaded with autostart disabled; no host code execution)",
            "tampered_standalone_selection": "PASS (rejected before transfer)",
            "configuration_verification": verifications,
        }

    report["artifacts"] = {
        item.name: sha256(item) for item in sorted(output.iterdir())
        if item.is_file() and item.name != "SHA256SUMS"
    }
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    checksums = [f"{sha256(item)}  {item.relative_to(ROOT)}" for item in sorted(output.iterdir()) if item.is_file() and item.name != "SHA256SUMS"]
    (output / "SHA256SUMS").write_text("\n".join(checksums) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

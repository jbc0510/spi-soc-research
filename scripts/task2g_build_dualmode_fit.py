#!/usr/bin/env python3
"""Build and verify a signed Linux/SPI-test FIT from an existing SD-card FIT.

The private signing key is supplied by path at runtime and is never copied into
the output tree. The output FIT is a host-side candidate; using it on hardware
also requires a matching trusted key in the board's U-Boot control FDT and a
trusted boot path for that U-Boot.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str], log: Path, *, expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=log.parent, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(result.stdout, encoding="utf-8")
    if expect_success and result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}); see {log}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-fit", type=Path, required=True,
                        help="FIT from the currently validated Linux SD card")
    parser.add_argument("--spi-elf", type=Path, required=True,
                        help="unified bare-metal SPI menu ELF")
    parser.add_argument("--keys", type=Path, required=True,
                        help="directory containing <key-name>.key and .crt")
    parser.add_argument("--key-name", default="msu2-test")
    parser.add_argument("--control-dtb", type=Path, required=True,
                        help="U-Boot control DTB to augment with the public key")
    parser.add_argument("--dumpimage", type=Path, required=True)
    parser.add_argument("--mkimage", type=Path, required=True)
    parser.add_argument("--fit-check-sign", type=Path, required=True)
    parser.add_argument("--objcopy", default="aarch64-linux-gnu-objcopy")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    inputs = [args.source_fit, args.spi_elf, args.keys / f"{args.key_name}.key",
              args.keys / f"{args.key_name}.crt", args.control_dtb,
              args.dumpimage, args.mkimage, args.fit_check_sign]
    for path in inputs:
        if not path.is_file():
            parser.error(f"required input is missing: {path}")
    output = args.output_dir.resolve()
    if output.exists():
        parser.error(f"refusing to overwrite existing output: {output}")
    output.mkdir(parents=True)
    payloads = output / "payloads"
    payloads.mkdir()
    source_fit, elf = args.source_fit.resolve(), args.spi_elf.resolve()
    for index, name in enumerate(("Image.gz", "system.dtb", "fdt-pl.dtbo", "rootfs.cpio")):
        run([str(args.dumpimage.resolve()), "-T", "flat_dt", "-p", str(index),
             "-o", str(payloads / name), str(source_fit)], output / f"extract_{index}.log")
    run([args.objcopy, "-O", "binary", str(elf), str(payloads / "spi-menu.bin")],
        output / "objcopy.log")
    shutil.copy2(args.control_dtb, output / "u-boot-control.dtb")

    its = output / "dual-mode.its"
    its.write_text(f'''/dts-v1/;
/ {{
 description = "MSU-2 signed Linux and SPI menu dual-mode image";
 #address-cells = <1>;
 images {{
  kernel-1 {{ description = "Existing Linux kernel"; data = /incbin/("payloads/Image.gz"); type = "kernel"; arch = "arm64"; os = "linux"; compression = "gzip"; load = <0x00200000>; entry = <0x00200000>; hash-1 {{ algo = "sha256"; }}; }};
  fdt-system-top {{ description = "Existing Linux device tree"; data = /incbin/("payloads/system.dtb"); type = "flat_dt"; arch = "arm64"; compression = "none"; hash-1 {{ algo = "sha256"; }}; }};
  fdt-pl {{ description = "Existing programmable logic overlay"; data = /incbin/("payloads/fdt-pl.dtbo"); type = "flat_dt"; arch = "arm64"; compression = "none"; hash-1 {{ algo = "sha256"; }}; }};
  ramdisk-1 {{ description = "Existing Linux root filesystem"; data = /incbin/("payloads/rootfs.cpio"); type = "ramdisk"; arch = "arm64"; os = "linux"; compression = "none"; hash-1 {{ algo = "sha256"; }}; }};
  spi-test {{ description = "Unified AXI SPI test menu"; data = /incbin/("payloads/spi-menu.bin"); type = "firmware"; arch = "arm64"; os = "u-boot"; compression = "none"; load = <0x00100000>; entry = <0x00100000>; hash-1 {{ algo = "sha256"; }}; }};
 }};
 configurations {{
  default = "linux";
  linux {{ description = "Normal Linux operation"; kernel = "kernel-1"; fdt = "fdt-system-top"; ramdisk = "ramdisk-1"; signature-1 {{ algo = "sha256,rsa2048"; key-name-hint = "{args.key_name}"; sign-images = "kernel", "fdt", "ramdisk"; }}; }};
  spi-test {{ description = "Bare-metal AXI SPI test menu"; kernel = "spi-test"; signature-1 {{ algo = "sha256,rsa2048"; key-name-hint = "{args.key_name}"; sign-images = "kernel"; }}; }};
  pl-overlay {{ description = "Linux programmable logic overlay"; fdt = "fdt-pl"; signature-1 {{ algo = "sha256,rsa2048"; key-name-hint = "{args.key_name}"; sign-images = "fdt"; }}; }};
 }};
}};
''', encoding="utf-8")
    fit = output / "msu2-dual-mode.itb"
    run([str(args.mkimage.resolve()), "-f", str(its), "-k", str(args.keys.resolve()),
         "-K", str(output / "u-boot-control.dtb"), "-r", str(fit)], output / "mkimage.log")

    checks: dict[str, str] = {}
    for conf in ("linux", "spi-test", "pl-overlay"):
        result = run([str(args.fit_check_sign.resolve()), "-f", str(fit), "-k",
                      str(output / "u-boot-control.dtb"), "-c", conf],
                     output / f"verify_{conf}.log")
        if "Signature check OK" not in result.stdout:
            raise RuntimeError(f"signature check did not confirm {conf}")
        checks[conf] = "PASS"
    public_key_required = subprocess.run(
        ["fdtget", str(output / "u-boot-control.dtb"), "/signature/key-" + args.key_name,
         "required"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if public_key_required.returncode or "conf" not in public_key_required.stdout:
        raise RuntimeError("control DTB lacks required configuration-signature key")

    modified = bytearray(fit.read_bytes())
    marker = (payloads / "spi-menu.bin").read_bytes()
    offset = modified.find(marker)
    if offset < 0:
        raise RuntimeError("could not locate standalone test payload in FIT")
    modified[offset + len(marker) // 2] ^= 0x01
    tampered = output / "tampered.itb"
    tampered.write_bytes(modified)
    tamper = run([str(args.fit_check_sign.resolve()), "-f", str(tampered), "-k",
                  str(output / "u-boot-control.dtb"), "-c", "spi-test"],
                 output / "verify_tampered.log", expect_success=False)
    if "Signature check OK" in tamper.stdout:
        raise RuntimeError("tampered standalone image was accepted")

    summary = {
        "result": "PASS",
        "source_fit_sha256": sha256(source_fit),
        "spi_elf_sha256": sha256(elf),
        "signed_fit_sha256": sha256(fit),
        "control_dtb_sha256": sha256(output / "u-boot-control.dtb"),
        "configuration_signatures": checks,
        "tampered_spi_payload": "REJECTED",
        "signing_key_path": str(args.keys.resolve()),
        "security_boundary": "FIT signature verification only. It does not authenticate BootROM, FSBL, or U-Boot; the key is a development key. A matching trusted U-Boot control DTB and authenticated boot chain are required on hardware.",
    }
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    sums = [f"{sha256(path)}  {path.relative_to(ROOT)}" for path in sorted(output.rglob("*"))
            if path.is_file() and path.name != "SHA256SUMS" and path.name != "tampered.itb"]
    (output / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

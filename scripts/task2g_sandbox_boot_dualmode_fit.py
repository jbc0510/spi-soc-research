#!/usr/bin/env python3
"""Exercise both real FIT payloads through U-Boot sandbox without executing them.

The AArch64 candidate FIT is rebuilt with sandbox architecture tags so host
U-Boot can exercise FIT selection. Payload bytes are extracted unchanged. The
standalone SPI application is loaded with autostart disabled.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run(command: list[str], cwd: Path, log: Path, *, ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    log.write_text(result.stdout, encoding="utf-8")
    if ok and result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}); see {log}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-fit", type=Path, required=True)
    parser.add_argument("--sandbox-uboot", type=Path, required=True)
    parser.add_argument("--sandbox-control-template", type=Path, required=True)
    parser.add_argument("--keys", type=Path, required=True)
    parser.add_argument("--key-name", default="msu2-test")
    parser.add_argument("--dumpimage", type=Path, required=True)
    parser.add_argument("--mkimage", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    required = [args.source_fit, args.sandbox_uboot, args.sandbox_control_template,
                args.keys / f"{args.key_name}.key", args.keys / f"{args.key_name}.crt",
                args.dumpimage, args.mkimage]
    for path in required:
        if not path.is_file():
            parser.error(f"input not found: {path}")
    out = args.output_dir.resolve()
    if out.exists():
        parser.error(f"refusing to overwrite output directory: {out}")
    out.mkdir(parents=True)
    payload = out / "payloads"
    payload.mkdir()
    source = args.source_fit.resolve()
    names = ("Image.gz", "system.dtb", "fdt-pl.dtbo", "rootfs.cpio", "spi-menu.bin")
    hashes: dict[str, str] = {}
    for idx, name in enumerate(names):
        file = payload / name
        run([str(args.dumpimage.resolve()), "-T", "flat_dt", "-p", str(idx),
             "-o", str(file), str(source)], out, out / f"extract_{idx}.log")
        hashes[name] = digest(file)

    shutil.copy2(args.sandbox_control_template, out / "sandbox-control.dtb")
    its = out / "sandbox-fit.its"
    its.write_text(f'''/dts-v1/;
/ {{
 description = "MSU-2 host-only signed dual-mode selection check";
 #address-cells = <1>;
 images {{
  linux-kernel {{ data = /incbin/("payloads/Image.gz"); type = "kernel_noload"; arch = "sandbox"; os = "linux"; compression = "none"; load = <0x00000004>; entry = <0x00000008>; hash-1 {{ algo = "sha256"; }}; }};
  linux-fdt {{ data = /incbin/("payloads/system.dtb"); type = "flat_dt"; arch = "sandbox"; compression = "none"; hash-1 {{ algo = "sha256"; }}; }};
  pl-fdt {{ data = /incbin/("payloads/fdt-pl.dtbo"); type = "flat_dt"; arch = "sandbox"; compression = "none"; hash-1 {{ algo = "sha256"; }}; }};
  linux-ramdisk {{ data = /incbin/("payloads/rootfs.cpio"); type = "ramdisk"; arch = "sandbox"; os = "linux"; compression = "none"; hash-1 {{ algo = "sha256"; }}; }};
  spi-test {{ data = /incbin/("payloads/spi-menu.bin"); type = "firmware"; arch = "sandbox"; os = "u-boot"; compression = "none"; load = <0x00100000>; entry = <0x00100000>; hash-1 {{ algo = "sha256"; }}; }};
 }};
 configurations {{
  default = "linux";
  linux {{ kernel = "linux-kernel"; fdt = "linux-fdt"; ramdisk = "linux-ramdisk"; signature-1 {{ algo = "sha256,rsa2048"; key-name-hint = "{args.key_name}"; sign-images = "kernel", "fdt", "ramdisk"; }}; }};
  spi-test {{ kernel = "spi-test"; signature-1 {{ algo = "sha256,rsa2048"; key-name-hint = "{args.key_name}"; sign-images = "kernel"; }}; }};
  pl-overlay {{ fdt = "pl-fdt"; signature-1 {{ algo = "sha256,rsa2048"; key-name-hint = "{args.key_name}"; sign-images = "fdt"; }}; }};
 }};
}};
''', encoding="utf-8")
    fit = out / "sandbox-dualmode.itb"
    run([str(args.mkimage.resolve()), "-f", str(its), "-k", str(args.keys.resolve()),
         "-K", str(out / "sandbox-control.dtb"), "-r", str(fit)], out, out / "mkimage.log")

    def boot(name: str, config: str, *, autostart: bool) -> subprocess.CompletedProcess[str]:
        address = "0x01000000"
        commands = []
        if not autostart:
            commands.append("setenv autostart no")
        commands.extend([f"host load hostfs - {address} {fit}", f"bootm {address}#{config}"])
        return run([str(args.sandbox_uboot.resolve()), "-d", str(out / "sandbox-control.dtb"),
                    "-c", "; ".join(commands)], out, out / f"uboot_{name}.log", ok=False)

    linux = boot("linux", "linux", autostart=True)
    spi = boot("spi-test", "spi-test", autostart=False)
    if "Signature checking prevents use of unit addresses" in linux.stdout or "Signature checking prevents use of unit addresses" in spi.stdout:
        raise RuntimeError("U-Boot rejected a FIT node name")
    if "sandbox: continuing, as we cannot run Linux" not in linux.stdout:
        raise RuntimeError("sandbox did not accept the signed Linux selection")
    if "Loading Firmware to 100000" not in spi.stdout:
        raise RuntimeError("sandbox did not load the signed SPI program")
    if "Failed to verify required signature" in spi.stdout or "Bad Data Hash" in spi.stdout:
        raise RuntimeError("sandbox rejected the valid SPI program")

    tampered = out / "tampered.itb"
    data = bytearray(fit.read_bytes())
    marker = (payload / "spi-menu.bin").read_bytes()
    offset = data.find(marker)
    if offset < 0:
        raise RuntimeError("SPI payload not found in host FIT")
    data[offset + len(marker) // 2] ^= 1
    tampered.write_bytes(data)
    bad = run([str(args.sandbox_uboot.resolve()), "-d", str(out / "sandbox-control.dtb"),
               "-c", f"setenv autostart no; host load hostfs - 0x01000000 {tampered}; bootm 0x01000000#spi-test"],
              out, out / "uboot_tampered.log", ok=False)
    if "Failed to verify required signature" not in bad.stdout and "Bad Data Hash" not in bad.stdout:
        raise RuntimeError("sandbox did not reject the tampered SPI program")
    if "Loading Firmware to 100000" in bad.stdout:
        raise RuntimeError("tampered SPI program reached firmware loading")

    summary = {
        "result": "PASS",
        "source_fit_sha256": digest(source),
        "source_payload_sha256": hashes,
        "sandbox_fit_sha256": digest(fit),
        "linux_selection": "accepted; sandbox cannot execute Linux",
        "spi_selection": "signature accepted and firmware loaded with autostart disabled",
        "tampered_spi_selection": "rejected before firmware load",
        "claim_boundary": "Host U-Boot sandbox only. Payload bytes match the source FIT; metadata uses sandbox architecture and is not a target image. No target Linux boot, AArch64 execution, SPI transfer, BootROM trust, or key provisioning is demonstrated.",
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    sums = [f"{digest(p)}  {p.relative_to(out)}" for p in sorted(out.rglob("*"))
            if p.is_file() and p.name not in {"SHA256SUMS", "tampered.itb"}]
    (out / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)

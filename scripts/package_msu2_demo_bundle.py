#!/usr/bin/env python3
"""Create a hash-pinned, no-Python PetaLinux operator-menu bundle from Git-tracked inputs."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "msu2_demo.sh": "linux/appliance/msu2_demo.sh",
    "MSU2_DEMO_CONSOLE.md": "linux/appliance/MSU2_DEMO_CONSOLE.md",
    # Runtime assets are the immutable, hash-verified release bundle committed
    # alongside this builder. Do not depend on local SD-card backup folders.
    "pl0-clock-only.dtbo": "results/msu2_linux_demo_bundle_20261017_v3/pl0-clock-only.dtbo",
    "pl-reset-release.dtbo": "results/msu2_linux_demo_bundle_20261017_v3/pl-reset-release.dtbo",
    "axi-spi-controller.dtbo": "results/msu2_linux_demo_bundle_20261017_v3/axi-spi-controller.dtbo",
    "spi_ratio2_j55_lvcmos33_20260929.bit.bin": "results/msu2_linux_demo_bundle_20261017_v3/spi_ratio2_j55_lvcmos33_20260929.bit.bin",
    "linux_spi_smoke_aarch64": "results/msu2_linux_demo_bundle_20261017_v3/linux_spi_smoke_aarch64",
    "spi_benchmark_v3_rxverify_aarch64": "results/msu2_linux_demo_bundle_20261017_v3/spi_benchmark_v3_rxverify_aarch64",
    "spi_sustainable_benchmark_linux_aarch64": "results/msu2_linux_demo_bundle_20261017_v3/spi_sustainable_benchmark_linux_aarch64",
}
EXPECTED = {
    "msu2_demo.sh": "b113e2e9fd6f940f459e5631992bb8b648b74ac6da2598f543262d018cc1b59c",
    "MSU2_DEMO_CONSOLE.md": "cee2fcd15108422a9475df1c20ae47e6bedc66c13d13f3cb226659a5b44fe38a",
    "pl0-clock-only.dtbo": "00d3bd63dd926a41c3e8581c8d4ee8abb3e94307ad7e4ba345e500e45bb1bffa",
    "pl-reset-release.dtbo": "6ae01a4bddea4fe225e2fdee6c5da48df70ce68df7be14328326d7066a171255",
    "axi-spi-controller.dtbo": "92416746eaba51248438fdca8be324ef2a0455ccb2caa64da74d75df96bee693",
    "spi_ratio2_j55_lvcmos33_20260929.bit.bin": "c27bb684ca843e173585aed50096f95692530444b808ec948006dbb0d67f56fd",
    "linux_spi_smoke_aarch64": "fb01baec3d451849bd147837491f0d63b62efd0e1a1f99389314d407582b8dcd",
    "spi_benchmark_v3_rxverify_aarch64": "d4e0e6b747789eb44e9013397e8956703ab41d8b78800e18d5586e72e5037c85",
    "spi_sustainable_benchmark_linux_aarch64": "36f60c0d6584a654aa3cf5383359a37e084cc599b678b51bf7c59438e6b31ded",
}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new output directory; must not exist")
    args = parser.parse_args()
    out = args.out if args.out.is_absolute() else ROOT / args.out
    if out.exists():
        print(f"Refusing to overwrite existing package directory: {out}", file=sys.stderr)
        return 2

    sources = {name: ROOT / rel for name, rel in FILES.items()}
    missing = [str(path) for path in sources.values() if not path.is_file()]
    if missing:
        print("Missing package inputs:\n" + "\n".join(missing), file=sys.stderr)
        return 2
    hashes = {name: digest(path) for name, path in sources.items()}
    wrong = [f"{name}: {hashes[name]} (expected {expected})"
             for name, expected in EXPECTED.items() if hashes[name] != expected]
    if wrong:
        print("Input artifact hash check failed:\n" + "\n".join(wrong), file=sys.stderr)
        return 2

    out.mkdir(parents=True)
    try:
        for name, source in sources.items():
            shutil.copy2(source, out / name)
        manifest = {
            "schema": "msu2-linux-demo-bundle-v1",
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "target": "ZCU102 / AArch64 / PetaLinux 2025.1 minimal image",
            "launch": "sudo sh /run/media/BOOT-mmcblk0p1/msu2_demo/msu2_demo.sh",
            "limitations": [
                "Linux-side operator menu; not a power-on OS chooser",
                "source bitstream hash is checked; FPGA configuration has no readback identity proof",
                "physical SPI SCK and loopback topology are not measured by the application",
                "FIT signature prototype does not establish BootROM-to-U-Boot secure boot",
            ],
            "files": {name: {"sha256": hashes[name], "size_bytes": sources[name].stat().st_size}
                      for name in sources},
        }
        (out / "PACKAGE_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
        (out / "SHA256SUMS").write_text("".join(
            f"{hashes[name]}  {name}\n" for name in sorted(sources)))
        print(f"Created {out}")
        print(f"Files: {len(sources)}; bitstream SHA-256: {hashes['spi_ratio2_j55_lvcmos33_20260929.bit.bin']}")
        return 0
    except Exception:
        shutil.rmtree(out)
        raise


if __name__ == "__main__":
    raise SystemExit(main())

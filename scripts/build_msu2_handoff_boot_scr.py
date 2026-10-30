#!/usr/bin/env python3
"""Build a U-Boot script that consumes one MSU-2 bare-metal request."""
import argparse
import hashlib
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE = ROOT / "results/task2g_bootflow_audit_20261015/boot.scr"


def extract_script(image: bytes) -> bytes:
    if len(image) < 72 or struct.unpack(">I", image[:4])[0] != 0x27051956:
        raise ValueError("Input is not a legacy U-Boot script image")
    size = struct.unpack(">I", image[12:16])[0]
    payload = image[64:64 + size]
    if len(payload) != size or len(payload) < 8:
        raise ValueError("Truncated U-Boot script payload")
    script_size, terminator = struct.unpack(">II", payload[:8])
    script = payload[8:]
    if terminator != 0 or script_size != len(script) or not script.startswith(b"#"):
        raise ValueError("Unexpected U-Boot script payload framing")
    return script


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--elf", type=Path,
                        help="Handoff ELF; its e_entry is read for the `go` "
                             "launch address (default 0x00100940).")
    args = parser.parse_args()

    # U-Boot runs at EL2; `bootelf` autostart would call the entry at EL2 without
    # an exception-level switch, and the Xilinx standalone boot.S MMU bring-up
    # faults when enabled at EL1 under U-Boot. We therefore load the segments
    # (autostart off) and launch with `go`, whose ZynqMP do_go_exec performs the
    # full EL2->EL1 switch; the ELF's custom entry then installs its own identity
    # MMU before _startup. `go` must target the ELF entry, not the load address.
    entry = 0x00100940
    if args.elf is not None:
        hdr = args.elf.read_bytes()[:64]
        if hdr[:4] != b"\x7fELF" or hdr[4] != 2:
            raise SystemExit("--elf is not an ELF64 image")
        entry = struct.unpack("<Q", hdr[24:32])[0]

    source = extract_script(args.base.read_bytes()).decode("ascii")
    anchor = "for boot_target in ${boot_targets};"
    if source.count(anchor) != 1:
        raise SystemExit("Refusing: stock boot script anchor is not unique")
    handoff = r'''# MSU-2 one-shot Linux-to-bare-metal handoff. BOOT.BIN remains the Linux image.
if test -e mmc 0:1 msu2_demo/baremetal.once; then
	echo "MSU-2: consuming one-shot bare-metal request"
	if fatload mmc 0:1 0x08000000 msu2_demo/spi_axi_bm_menu_aarch64.elf; then
		if fatrm mmc 0:1 msu2_demo/baremetal.once; then
			setenv autostart no
			bootelf -p 0x08000000
			echo "MSU-2: entering bare-metal via go (EL2->EL1 switch)"
			go %s
			echo "MSU-2: bare-metal image returned; continuing to Linux default"
		else
			echo "MSU-2: could not consume request; refusing bare-metal launch"
		fi
	else
		echo "MSU-2: bare-metal ELF load failed; continuing to Linux default"
	fi
fi

''' % ("0x%08x" % entry)
    script = source.replace(anchor, handoff + anchor, 1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="msu2-boot-script-") as tmp:
        cmd = Path(tmp) / "boot.cmd"
        cmd.write_text(script, encoding="ascii")
        mkimage = shutil.which("mkimage")
        if not mkimage:
            raise SystemExit("mkimage is required")
        subprocess.run([mkimage, "-C", "none", "-A", "arm", "-T", "script",
                        "-d", str(cmd), str(args.output)], check=True)
    # Re-open the generated image to ensure the handoff branch is in its script.
    rebuilt = extract_script(args.output.read_bytes()).decode("ascii")
    if handoff not in rebuilt:
        raise SystemExit("Generated script failed its content check")
    print(f"base_sha256={hashlib.sha256(args.base.read_bytes()).hexdigest()}")
    print(f"script_sha256={hashlib.sha256(script.encode('ascii')).hexdigest()}")
    print(f"boot_scr_sha256={hashlib.sha256(args.output.read_bytes()).hexdigest()}")
    print(f"boot_scr_bytes={args.output.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

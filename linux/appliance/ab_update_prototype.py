#!/usr/bin/env python3
"""Host-testable prototype of signed inactive-slot update and boot rollback.

This prototype deliberately uses a JSON control file. It is not integrated
with U-Boot, a Linux block device, or the ZCU102 secure-boot chain.
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


class UpdateError(Exception):
    pass


def verify_signature(public_key: Path, signature: Path, payload: Path) -> None:
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-verify", str(public_key),
         "-signature", str(signature), str(payload)],
        check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if result.returncode != 0 or "Verified OK" not in result.stdout:
        raise UpdateError("release signature verification failed")


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_state(path: Path) -> dict:
    try:
        state = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateError(f"cannot read boot-control state: {exc}") from exc
    if state.get("confirmed_slot") not in ("A", "B"):
        raise UpdateError("boot-control state has invalid confirmed_slot")
    if state.get("pending_slot") not in (None, "A", "B"):
        raise UpdateError("boot-control state has invalid pending_slot")
    return state


def write_state_atomic(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(state, stream, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
        dir_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


def stage(args) -> None:
    state = read_state(args.state)
    if state.get("pending_slot"):
        raise UpdateError("a trial update is already pending")
    verify_signature(args.public_key, args.signature, args.payload)
    confirmed = state["confirmed_slot"]
    inactive = "B" if confirmed == "A" else "A"
    target = args.slot_a if inactive == "A" else args.slot_b
    payload_size = args.payload.stat().st_size
    target_size = target.stat().st_size
    if payload_size <= 0 or payload_size > target_size:
        raise UpdateError(f"payload size {payload_size} does not fit slot size {target_size}")

    written = 0
    with args.payload.open("rb") as source, target.open("r+b") as destination:
        while True:
            read_size = 1024 * 1024
            if args.fail_after_bytes is not None:
                read_size = min(read_size, max(1, args.fail_after_bytes - written))
            chunk = source.read(read_size)
            if not chunk:
                break
            destination.write(chunk)
            written += len(chunk)
            if args.fail_after_bytes is not None and written >= args.fail_after_bytes:
                destination.flush()
                os.fsync(destination.fileno())
                raise UpdateError("injected interruption during inactive-slot write")
        destination.flush()
        os.fsync(destination.fileno())

    # Verify the bytes read back from the target before publishing boot state.
    with target.open("rb") as source, tempfile.NamedTemporaryFile(prefix="msu2-readback-", delete=False) as out:
        readback = Path(out.name)
        remaining = payload_size
        digest = hashlib.sha256()
        while remaining:
            chunk = source.read(min(1024 * 1024, remaining))
            if not chunk:
                readback.unlink(missing_ok=True)
                raise UpdateError("short readback from inactive slot")
            digest.update(chunk)
            out.write(chunk)
            remaining -= len(chunk)
        out.flush()
        os.fsync(out.fileno())
    try:
        if digest.hexdigest() != sha256_path(args.payload):
            raise UpdateError("inactive-slot readback digest mismatch")
        verify_signature(args.public_key, args.signature, readback)
    finally:
        readback.unlink(missing_ok=True)

    state["pending_slot"] = inactive
    state["pending_sha256"] = digest.hexdigest()
    state["pending_size"] = payload_size
    state["boot_attempts"] = 0
    write_state_atomic(args.state, state)
    print(f"staged_slot={inactive} bytes={payload_size} sha256={digest.hexdigest()}")


def select_boot(args) -> None:
    state = read_state(args.state)
    pending = state.get("pending_slot")
    limit = int(state.get("boot_limit", 2))
    attempts = int(state.get("boot_attempts", 0))
    if pending and attempts < limit:
        state["boot_attempts"] = attempts + 1
        write_state_atomic(args.state, state)
        print(f"slot={pending} trial={attempts + 1}/{limit}")
        return
    if pending:
        state["pending_slot"] = None
        state.pop("pending_sha256", None)
        state.pop("pending_size", None)
        state["boot_attempts"] = 0
        write_state_atomic(args.state, state)
        print(f"slot={state['confirmed_slot']} rollback=boot_limit")
        return
    print(f"slot={state['confirmed_slot']} confirmed=1")


def mark_good(args) -> None:
    state = read_state(args.state)
    pending = state.get("pending_slot")
    if not pending:
        raise UpdateError("no pending slot to confirm")
    state["confirmed_slot"] = pending
    state["pending_slot"] = None
    state.pop("pending_sha256", None)
    state.pop("pending_size", None)
    state["boot_attempts"] = 0
    write_state_atomic(args.state, state)
    print(f"confirmed_slot={pending}")


def mark_bad(args) -> None:
    state = read_state(args.state)
    if not state.get("pending_slot"):
        raise UpdateError("no pending slot to reject")
    state["pending_slot"] = None
    state.pop("pending_sha256", None)
    state.pop("pending_size", None)
    state["boot_attempts"] = 0
    write_state_atomic(args.state, state)
    print(f"confirmed_slot={state['confirmed_slot']} rollback=health_check")


def common_state(parser):
    parser.add_argument("--state", type=Path, required=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    update = commands.add_parser("stage", help="verify and write the inactive slot")
    common_state(update)
    update.add_argument("--slot-a", type=Path, required=True)
    update.add_argument("--slot-b", type=Path, required=True)
    update.add_argument("--payload", type=Path, required=True)
    update.add_argument("--signature", type=Path, required=True)
    update.add_argument("--public-key", type=Path, required=True)
    update.add_argument("--fail-after-bytes", type=int)
    update.set_defaults(func=stage)
    select = commands.add_parser("select", help="select trial or confirmed slot")
    common_state(select)
    select.set_defaults(func=select_boot)
    good = commands.add_parser("mark-good", help="confirm a healthy trial slot")
    common_state(good)
    good.set_defaults(func=mark_good)
    bad = commands.add_parser("mark-bad", help="reject a trial slot and keep confirmed")
    common_state(bad)
    bad.set_defaults(func=mark_bad)
    args = parser.parse_args()
    try:
        args.func(args)
    except UpdateError as exc:
        print(f"update_error={exc}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

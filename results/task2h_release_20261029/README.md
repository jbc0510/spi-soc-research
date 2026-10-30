# October 29 Linux-to-bare-metal handoff recovery

Start here at LPS. All commands run from the repository root on branch
`feature/ratio2-j55-rebuild`. Original firmware checkpoint: `577e127`.

## Correct deployable ELF

`results/task2h_release_20261029/final/spi_axi_bm_menu_aarch64.elf`

SHA256: `e8e290945a304a9c4ed15ec90a47c2d44dcb9cf9d25b01256dc3b97e6009a25b`

ELF64 little-endian AArch64, entry **0x00100940**. Recovered unchanged from
October 29 20:24 scratchpad `fix5.elf`. A fresh October 30 build of the
unchanged committed firmware at the original checkout reproduced this full
ELF hash exactly. The startup shim is in the firmware C source; no separate
custom startup object is required. Standard startup objects come from the
installed cross-toolchain and startup/driver code from the packaged BSP.

**Do not deploy the earlier `results/task2h_boot_handoff_20261029/rebuilt/`
ELF as the final firmware.** That is the 11:48 candidate, SHA256
`9e379fd3f040df975f067a68ba29b2db260d8d58a4490f5d64c7eb0197437629`.
It and its exact source snapshot, UART variant, gzip copies, map and original
build_inputs.json are preserved as historical evidence. The historical
candidate also reproduced bit-for-bit at the original checkout.

## Tools and clean-clone build

Validated host: Ubuntu 22.04.5 LTS x86_64, Python 3.10, AMD PetaLinux 2025.1
cross compiler `aarch64-none-elf-gcc` (GNU 13.3.0) and accompanying binutils,
newlib/libc/libm/libgcc and standard CRT objects. Use the complete AMD compiler
installation, not just the gcc executable. The original compiler was at
`/home/opentitan/petalinux/2025.1/components/xsct/gnu/aarch64/lin/aarch64-none/bin/`.
Install the equivalent tools at any accessible path and set CROSS below.
The prebuilt BSP came from the Vitis 2025.1 handoff platform. Vivado/Vitis
2025.1 and PetaLinux 2025.1 are the recorded platform versions; no Vivado,
Vitis platform generation, hardware rebuild, or running board is needed for
this prebuilt-BSP application build. No full toolchain is included in Git.

```sh
git switch feature/ratio2-j55-rebuild
git pull --ff-only origin feature/ratio2-j55-rebuild
sha256sum -c results/task2h_release_20261029/SHA256SUMS
export CROSS=/path/to/AMD/aarch64-none/bin/aarch64-none-elf-
python3 scripts/reproduce_oct29_handoff.py --cc "${CROSS}gcc" --output /tmp/msu2-final
"${CROSS}readelf" -h /tmp/msu2-final/spi_axi_bm_menu_aarch64.elf
"${CROSS}objdump" -f /tmp/msu2-final/spi_axi_bm_menu_aarch64.elf
"${CROSS}objdump" -d --start-address=0x100940 --stop-address=0x100a00 /tmp/msu2-final/spi_axi_bm_menu_aarch64.elf
sha256sum /tmp/msu2-final/spi_axi_bm_menu_aarch64.elf
```

Expected output is `/tmp/msu2-final/spi_axi_bm_menu_aarch64.elf`, entry
`0x100940` (`0x00100940`), plus map, command.json and build.log.
The script prints the exact compiler/linker invocation and rejects a changed
entry. Expected warnings: GCC ignores the naked attribute and reports the
noreturn function returning; these were present in the recovered build.

A different clone path changes DWARF debug paths (`-g3`) and the GNU build ID, so the full ELF hash
can differ. Use the packaged final ELF above for the exact October 29 bytes.
Compare loadable content excluding the path-dependent GNU build ID for a relocated build with:

```sh
"${CROSS}objcopy" -O binary --remove-section=.note.gnu.build-id results/task2h_release_20261029/final/spi_axi_bm_menu_aarch64.elf /tmp/msu2-reference.bin
"${CROSS}objcopy" -O binary --remove-section=.note.gnu.build-id /tmp/msu2-final/spi_axi_bm_menu_aarch64.elf /tmp/msu2-rebuilt.bin
cmp /tmp/msu2-reference.bin /tmp/msu2-rebuilt.bin
```

For historical investigation only, add `--variant historical` and use a
separate output directory. This compiles the preserved morning source,
not the final firmware. `build_inputs.json` remains unmodified; every one
of its seven input paths has been inspected and hash-verified through
`dependency_mapping.json`. Its old bare_metal/vitis paths map to the
committed `rebuilt/lib/`, `rebuilt/Xilinx.spec`, and `rebuilt/lscript.ld`.
The old source hash maps to `rebuilt/spi_sustainable_benchmark_bare_axi.c`;
the final source is `bare_metal/src/spi_sustainable_benchmark_bare_axi.c`.
The original absolute compiler is replaced by --cc, all other absolute
repository inputs by paths derived from the script location. Existing
`final/command.json` and `final/build.log` record the Morgan reproduction,
not portable instructions to execute verbatim.

## Dependencies and preserved evidence

- `../task2h_boot_handoff_20261029/rebuilt/include/`: complete saved BSP headers.
- `../task2h_boot_handoff_20261029/rebuilt/lib/`: libxil.a, libxilstandalone.a,
  libxiltimer.a; exact hashes match the original build_inputs.json.
- `../task2h_boot_handoff_20261029/rebuilt/Xilinx.spec`, `lscript.ld`:
  compiler startup specification and linker placement/entry.
- `recovered_scratchpad/`: all 30 October 29 scratch files, including fix through
  fix5 ELFs, both boot script variants, assembly probes, objects, scripts,
  linker map, disassembly and UART log. Diagnostic/staging scripts are
  historical board-control tools; they are not the deployment procedure below.
- `recorded_notes/`: recovered contemporaneous notes and original commit
  validation statement. These include intermediate hypotheses and stale SD
  state; the final EOD update supersedes earlier notes.
- `../task2h_boot_handoff_20261029/`: all original local handoff files,
  diagnostics, UART logs, objects, source snapshots and compressed ELFs.
- `scripts/build_msu2_handoff_boot_scr.py`: preserved boot script builder;
  its default stock input is tracked at
  `results/task2g_bootflow_audit_20261015/boot.scr`. It accepts --elf to derive
  the launch entry. Generation uses `mkimage` (U-Boot tools). Reproduction
  is possible in a temporary output file; do not overwrite the card script.
- `linux/appliance/msu2_demo.sh`: preserved existing operator menu, prepares
  PL, clocks/reset and overlay, arms baremetal.once and uses PS-only reboot.
- `scripts/build_spi_axi_bm_ratio2_vitis.py`: existing October 29 BSP builder
  changes retained for provenance. This recovery uses the saved BSP instead
  of rerunning platform generation.

`SHA256SUMS` lists every packaged artifact individually with repository-relative
paths, plus the unchanged firmware, contract, builder, stock script and menu.
`final/build_inputs.json` identifies final inputs. Nothing requires access
to temporary scratch directories or an old bare_metal/vitis workspace.

## ELF-only SD deployment

The ZCU102 SD must already contain the working Linux BOOT.BIN, handoff
boot.scr and msu2_demo configuration/payloads. This is an ELF recovery,
not a replacement OS/SD image. Do not use the older standalone BOOT.BIN.
Set SD to the mounted FAT boot partition and run:

```sh
SD=/path/to/mounted/BOOT
ELF=results/task2h_release_20261029/final/spi_axi_bm_menu_aarch64.elf
test -f "$SD/BOOT.BIN" && test -f "$SD/boot.scr" && test -d "$SD/msu2_demo"
sha256sum "$SD/BOOT.BIN" "$SD/boot.scr" > /tmp/msu2-boot-before.sha256
cp -p "$SD/msu2_demo/spi_axi_bm_menu_aarch64.elf" "$SD/msu2_demo/spi_axi_bm_menu_aarch64.elf.backup.$(date +%Y%m%dT%H%M%S)"
cp "$ELF" "$SD/msu2_demo/spi_axi_bm_menu_aarch64.elf"
sync
cmp "$ELF" "$SD/msu2_demo/spi_axi_bm_menu_aarch64.elf"
sha256sum -c /tmp/msu2-boot-before.sha256
```

Run commands only if each preceding command succeeds. Unmount normally.
Do not create a marker during deployment. The existing operator menu
prepares PL/bitstream/clock/reset/overlay before arming the one-shot request.
Existing U-Boot sequence stays `setenv autostart no; bootelf -p 0x08000000;
go 0x00100940`; q returns through PSCI SYSTEM_RESET. BOOT.BIN and boot.scr
are not changed by deployment. Saved boot.scr.fixed has SHA256
`090de3741b18bcbe2d2d351a5cb575f9e3f2816fcee4c43d73348f5d7ec59f0c`;
fixed2 is an additional historical variant. Neither is automatically installed.

## Hardware status and limitations

No new UART actions, SD writes, board reboots or SPI tests were performed in
this recovery. October 29 EOD notes and commit 577e127 report Linux ->
bare-metal menu -> one-byte benchmark (~1.1M transfers/s, zero API errors)
-> q -> Linux. One-byte TX is zero, so that result alone does not prove
external RX integrity. Multi-byte RX mismatches remained unresolved across
two RX drain implementations. Internal AXI SPI loopback stays disabled.
The operator at LPS must perform the next hardware validation. Build success
and exact ELF reproduction do not establish new board validation.

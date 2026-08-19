# SOW 2.g -- Section 7 Unknowns: Measured Answers

Measured on `stile` (LPS), 2026-08-19. MSU-2 Task 2, IAC/TAT P1-22-2393.

## What this document is, and is not

This is **not** the lost `SOW_2G_APPLIANCE_DESIGN.md`. That file never existed
on disk; see the CORRECTION 2026-08-19 block in
`docs/sessions/CONTINUATION_PROMPT_TWOSITE.md`. What survived of the 2.g design
is a single paragraph in Section G of that file, which names four "cheap
unknowns" to close before appliance work begins. This document answers three of
those four from measurement, and states plainly which one remains open.

Anything here that is not accompanied by a file and line citation is not a
finding.

## THE MEASUREMENT SUBJECT -- read this before using any answer below

Everything was measured in the PetaLinux project `~/zcu102-spidev` on `stile`.

That tree's output images DO NOT match the recorded known-good boot artifacts:

| artifact | measured 2026-08-19 | recorded known-good |
|---|---|---|
| `images/linux/BOOT.BIN` | `57f6a85d4a3cbd26ecfa78c4bc9d7378` | `a25d6549...` |
| `images/linux/image.ub` | `f8f6a757cca655040eca1b1ddf7aea6c` | `ffe0c75b...` |

The recorded values are prefixes carried in the project record and were not
re-measured. What is established is a MISMATCH between this tree and the
record -- not which of the two is authoritative.

Timestamps are also split: `BOOT.BIN` is Jul 13, every other image is Mar 20.
The boot image was repackaged separately from the rest of the build.

**Consequence: every answer below is a property of THIS BUILD TREE. None is a
statement about what is currently running on either ZCU102.** Confirming that
requires the board.

U-Boot version in this tree, measured:
`build/tmp/work/zynqmp_generic_xczu9eg-amd-linux/u-boot-xlnx/2025.01-xilinx-v2025.1+git/`
This matches the version named in the Section G paragraph, so the questions are
being asked of the right source.

Config file cited throughout as `.config`:
`<u-boot-xlnx>/2025.01-xilinx-v2025.1+git/build/.config` -- 2547 lines.

## Q1 -- Is `fw_setenv` on the rootfs?

**NO.**

- `rootfs.cpio` contains 2503 entries. Zero match `fw_setenv` or `fw_printenv`.
- Positive control: `bin/mkimage` matches exactly 1 entry in the same archive,
  so the archive was genuinely read and the zero is meaningful.
- `rootfs.manifest` (240 lines) lists `u-boot-tools-xlnx` and its `mkimage`,
  `mkenvimage`, `mkeficapsule` subpackages. It lists NO `libubootenv` and NO
  `u-boot-fw-utils`, which are the Yocto packages that provide `fw_setenv`.

### Why this matters more than it looks

`.config:1119 CONFIG_ENV_IS_IN_FAT=y` and
`.config:1135 CONFIG_SYS_REDUNDAND_ENVIRONMENT=y` are both set. The A/B
environment mechanism EXISTS in U-Boot. But with no `fw_setenv` in the rootfs
there is no userspace tool to flip the boot pointer from Linux.

The 2.g robustness requirement (remain bootable through an interrupted update)
therefore has half its mechanism present and half missing. Remediation is
either adding `libubootenv-bin` to the rootfs, or designing the update path to
not depend on userspace env writes. **This is a design decision, not yet made.**

## Q2 -- Is mbedTLS enabled?

**NO.**

- `.config:2421  # CONFIG_MBEDTLS_LIB is not set`
- `.config:2420  CONFIG_LEGACY_CRYPTO=y`
- `.config:2432  CONFIG_LEGACY_CRYPTO_CERT=y`

U-Boot is built against the legacy crypto path, not mbedTLS. Note that the
rootfs manifest lists `openssl-conf 3.2.4` -- that is a USERSPACE package and
says nothing about U-Boot's crypto backend. The two must not be conflated.

Related, and already known: `.config:429 # CONFIG_FIT_SIGNATURE is not set`.
There is no cryptographic verification of the boot image today. The 2.g
verification requirement is unstarted, not partially met.

## Q3 -- Does a ZynqMP watchdog driver exist in U-Boot 2025.01?

**YES -- driver and device tree are both ready. Only the config is off.**

This is the most actionable finding in this document.

Driver, in-tree:

- `git/drivers/watchdog/cdns_wdt.c:292` -> `{ .compatible = "cdns,wdt-r1p2" }`

Device tree, in the BUILT blob (not merely the source `.dtsi`):

- `build/u-boot.dtb` and `build/dts/dt.dtb` are the SAME blob,
  md5 `fdc83257e923ff9df083f0e75dd330ce`.
- `watchdog@fd4d0000` -- `compatible = "cdns,wdt-r1p2"`, `status = "okay"`,
  `timeout-sec = <0x3c>` (60), `reset-on-timeout`, `clocks` populated.
- `watchdog@ff150000` -- `compatible = "cdns,wdt-r1p2"`, `status = "okay"`,
  `timeout-sec = <0x0a>` (10), `clocks` populated.

Config, all three unset:

- `.config:2350  # CONFIG_WATCHDOG is not set`
- `.config:2353  # CONFIG_WDT is not set`
- `.config:2354  # CONFIG_SPL_WDT is not set`

And, orphaned 2127 lines above them:

- `.config:223   CONFIG_WATCHDOG_TIMEOUT_MSECS=60000`

That 60000 ms exactly matches the FPD node's `timeout-sec = <60>`. The value has
been sitting in this config with a working driver available in-tree the whole
time, consumed by nothing.

### Two traps avoided here, recorded so they are not re-encountered

1. **The Kconfig help text is stale and would have produced the wrong answer.**
   `Kconfig:156 WDT_CDNS` describes itself as for "Xilinx Microzed Platform"
   (Zynq-7000). `Kconfig:406 WDT_XILINX` says "Versal".
   `Kconfig:398 XILINX_TB_WATCHDOG` says "MicroBlaze". Read literally, none
   names ZynqMP and the answer would have been "no driver". What actually
   decides is the driver's `of_match` compatible string against the DT node,
   and those match.

2. **The source `.dtsi` says `status = "disabled"` for BOTH nodes**
   (`git/arch/arm/dts/zynqmp.dtsi:1233-1249`). Reading the source alone would
   have produced the wrong answer. The BUILT blob overrides both to `"okay"`.
   Read the blob, not the include.

### Remediation

`CONFIG_WDT=y` plus `CONFIG_WDT_CDNS=y`, rebuild U-Boot. No device tree work,
no driver work. Rebuildable at both sites. NOT DONE -- not attempted, not
tested, and the rebuild is subject to the PetaLinux 2025.1 vs 2025.2 skew
recorded as open decision D-1.

## Q4 -- Is the FAT redundant environment initialised on the card?

**OPEN.** Not answerable on `stile`.

`CONFIG_ENV_IS_IN_FAT=y` and `CONFIG_SYS_REDUNDAND_ENVIRONMENT=y` establish
that U-Boot is BUILT for a redundant FAT environment. Whether the environment
files actually exist and are valid on the SD card is a property of the card,
which is at `jeremiahc` (LPS) or in the Morgan card reader. This requires
physical access and is the remaining item.

## UNPLANNED FINDING -- TPM2 over SPI is enabled in U-Boot

Not one of the four questions. Found while reading the config for Q2.

- `.config:2440  CONFIG_TPM=y`
- `.config:2112  CONFIG_TPM_V2=y`
- `.config:2114  CONFIG_TPM2_TIS_SPI=y`
- `.config:1939  CONFIG_TPM_RNG=y`

A TPM2-over-SPI stack is compiled into U-Boot. This is directly relevant to the
2.g verification requirement, and the transport is SPI -- this project's own
subject.

**NOT CLAIMED: that a TPM is physically present on the ZCU102, or wired to any
SPI bus, or that any DT node binds it.** An enabled driver is not a present
device. This is recorded as a lead to investigate, nothing more.

## DEVICE TREE IDENTITY -- unresolved, recorded honestly

`.config:205 CONFIG_DEFAULT_DEVICE_TREE="zynqmp-zcu100-revC"`. zcu100-revC is
the Ultra96, not the ZCU102.

The built blob does NOT appear to be an Ultra96 tree:

- root `compatible = "xlnx,zynqmp"` -- generic, no board-specific string
- ZERO occurrences of `zcu100`, `zcu102`, or `ultra96` anywhere in the tree
- NO `model` property at all
- `CONFIG_SUBSYSTEM_MACHINE_NAME="template"` in the PetaLinux project config

So the zcu100 default was overridden by a generated generic tree. But nothing
positively identifies the blob as ZCU102 either. `spi@a0000000` (the project's
AXI Quad SPI) is absent; only `spi@ff050000` (PS SPI1) is present, which is
expected at U-Boot stage since the PL is not loaded, and is therefore neither
evidence for nor against.

**Why Q3 survives this anyway:** `watchdog@fd4d0000` and `watchdog@ff150000`
are PS peripherals at fixed addresses in the ZynqMP silicon, identical on every
board using this SoC. Unlike a PL or PMOD peripheral, their presence does not
depend on which board DT was selected.

## BACKLOG -- record, do not fix on sight

- The built DTB aliases BOTH `spi1` and `spi2` to the same node:
  `spi2 = "/axi/spi@ff050000"` and `spi1 = "/axi/spi@ff050000"`.
  Two aliases, one controller. Given this project's history with mislabeled
  controller identity, verify this before reasoning from U-Boot SPI aliases.
- `~/zcu102-spidev` image md5s do not match the recorded known-good artifacts
  (see top). Establish which tree produced the board's current boot image.

## SOW POSITION

This closes three of four Section 7 unknowns and is 2.g work -- the first SOW
contractual activity of the 2026-08-19 session. 2.g remains DESIGN LOST and
NOT IMPLEMENTED. Nothing was built, configured, or flashed. Q4 is open and
requires board or card access.

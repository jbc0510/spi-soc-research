# Fixed signed startup selector

This U-Boot configuration presents two explicit choices: normal Linux operation
and the unified AXI SPI test menu. It uses a compiled-in default environment,
does not load a persistent environment, prevents the boot-menu console entry,
and reboots if a selection returns or fails. The FIT's `linux`, `spi-test`, and
`pl-overlay` configurations must all be signed by the private key corresponding
to the required public key in U-Boot's control device tree.

`task2g-selector.cfg` is a Yocto Kconfig fragment. The environment file must be
copied into the U-Boot source tree at
`board/xilinx/zynqmp/msu2-selector.env` before Kconfig runs. A PetaLinux recipe
append must add the fragment and perform that copy in `do_configure:prepend`.
The target project's existing `task2g-verified-boot.cfg` should be retained and
combined with this selector fragment, not replaced.

The menu refers to `msu2-dual-mode.itb` on FAT partition 1 of MMC device 0 and
loads it at `0x10000000`. Check these addresses against the board's final memory
map and U-Boot relocation settings before a hardware boot. The menu defaults
to neither choice: a person selects Linux or the test application.

## Security boundary

FIT signatures gate payload handoff only when this U-Boot is itself trusted.
The current ZCU102 `BOOT.BIN` does not authenticate the FSBL/U-Boot chain, and
the available `msu2-test` key is a development key. This prototype therefore
does not establish secure boot, eFUSE provisioning, or protection against an
attacker replacing U-Boot or its control DTB. Production hardening requires an
authenticated ZynqMP boot chain and controlled key provisioning.

The no-console menu option only removes the U-Boot console choice from the
boot menu. Validate console behavior and error recovery on the exact generated
U-Boot build before making it the board's boot image.

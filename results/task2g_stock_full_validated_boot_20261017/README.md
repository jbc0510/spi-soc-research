# Stock platform boot image with the validated J55 PL bitstream

This is the PetaLinux-generated ZynqMP boot image, built from the platform's stock FSBL, PMUFW, BL31, system DTB, and U-Boot. Its PL partition matches the validated September 29 J55 bitstream used by the bare-metal tests.

- Boot image SHA-256: `604df48f3e98f70e849df14c26562514149359b9a2a9e5921e4fcd1428e9abea`
- Validated Xilinx `.bit` SHA-256: `90f93479dd47c505b8f9e4fe6f4f18e853f8923d081f4b2037401ed3cb46994a`
- PL partition length: `0x0065216f`; PL destination/load address: `0xffffffff`; Bootgen checksum: `0xfecfb328`
- These PL partition fields match the previously checked corrected selector package and the bitstream is the same validated artifact by SHA-256.

The image is staged as a diagnostic baseline and has not yet been installed or booted during this investigation. It restores stock platform boot components while including the known validated PL design. `image.ub` on the card remains the kernel/root filesystem input and is not modified by installing this file as `BOOT.BIN`. This test distinguishes the no-PL FSBL loop from a broader boot/handoff problem and the custom selector integration.

The Bootgen readback copied from the platform package audit is `bootgen_read.log`. The exact source image was `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/build/tmp/deploy/images/zynqmp-generic-xczu9eg/BOOT-zynqmp-generic-xczu9eg-20261017180840.bin`.

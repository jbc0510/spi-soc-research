# Stock PetaLinux no-PL boot diagnostic

This diagnostic is designed to separate the custom selector U-Boot/keyed system-DTB package from the platform's stock PetaLinux U-Boot and system DTB while keeping the PL bitstream out of the image. It uses the FSBL, PMUFW, BL31, system DTB, and U-Boot extracted from the platform-generated `boot.bin` build at `/home/opentitan/zcu102_spi_benchmark/spi_benchmark_linux/build/tmp/deploy/images/zynqmp-generic-xczu9eg/boot.bin-extracted/`.

The image is a test artifact, not a release. It has no PL partition and does not provide the selector menu or a secure boot chain. It has not been installed or booted. The PetaLinux image's normal U-Boot behavior may autoboot from the card; the existing `image.ub` and boot script should therefore be treated as active boot inputs.

Build with the installed AMD Bootgen 2025.1:

```sh
/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/Vitis/bin/bootgen \
  -arch zynqmp \
  -image results/task2g_stock_no_pl_diagnostic_20261017/bootgen-stock-no-pl-diagnostic.bif \
  -o results/task2g_stock_no_pl_diagnostic_20261017/BOOT_STOCK_NO_PL_DIAGNOSTIC.bin \
  -w
```

Bootgen readback contains FSBL, PMUFW, BL31, system-top.dtb, and u-boot.elf and no PL partition. Image SHA-256: `2a10ff5726003b99992f588a66246842dc40e8bd8320f63f09926568d157ffb2`.

Interpretation: if this stock no-PL image reaches U-Boot while the custom no-PL image does not, the changed U-Boot/system-DTB path becomes the leading area to isolate. If it shows the same partial banner, the issue is common to the FSBL/handoff/boot media/console path and needs further evidence. Neither result alone identifies root cause.

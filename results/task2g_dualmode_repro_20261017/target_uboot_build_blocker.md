# Interim generic U-Boot build (superseded)

The selector fragment merged and resolved under U-Boot 2025.01-Xilinx. The resolved configuration enables the automatic boot menu, disables its U-Boot-console option, sets `BOOTDELAY=-2`, disables persistent environment storage and distro defaults, enables FIT RSA signature verification, and disables legacy images.

A standalone target compile succeeded after using the installed Xilinx `aarch64-none-elf` toolchain, adding the existing Yocto SWIG executable to `PATH`, setting `PYTHONNOUSERSITE=1`, and disabling only the optional host utility `TOOLS_MKEFICAPSULE` in this throwaway build configuration. The resulting `.build/uboot-task2g-selector-target/u-boot.elf` is a 64-bit AArch64 executable. The earlier retries first exposed the missing `aarch64-linux-gnu-gcc`, SWIG, and a Python user-site `distutils.msvccompiler` conflict; isolating Python resolved those host-tool issues.

This was only a generic `xilinx_zynqmp_virt_defconfig` build and did not establish the project boot path. It is retained as historical toolchain evidence; use `target_uboot_build.log`, `bootgen_package_build.log`, `bootgen_read_candidate.log`, and the parent investigation report for the later PetaLinux build and BOOT.BIN candidate.

The actual PetaLinux build and candidate package were completed later in this investigation. The candidate has been copied to the SD card with the original BOOT.BIN preserved as an on-card backup. No ZCU102 boot has yet been performed with it.

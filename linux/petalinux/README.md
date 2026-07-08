# PetaLinux Rebuild Instructions

## Prerequisites
- PetaLinux 2025.2 installed
- XSA file: `hardware/xsa/spi_benchmark_wrapper.xsa`

## Steps
```bash
source ~/petalinux/2025.2/settings.sh
petalinux-create -t project -n spi_benchmark_linux --template zynqMP
cd spi_benchmark_linux
petalinux-config --get-hw-description ../../hardware/xsa/spi_benchmark_wrapper.xsa
cp ../device-tree/system-user.dtsi project-spec/meta-user/recipes-bsp/device-tree/files/
petalinux-build
petalinux-package --boot --fsbl --fpga --u-boot --force
```

## Result
- `images/linux/BOOT.BIN` — matched bootloader with custom bitstream
- `images/linux/image.ub` — kernel + DTB with all 3 SPI interfaces

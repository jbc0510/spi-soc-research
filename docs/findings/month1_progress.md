# Month 1 Progress Report
Author: Jerry Conway (jbc0510)
Date: March 2026

## Summary
During the first session, the development environment 
was established including secure multi-machine Git 
configuration with separate SSH identities for personal 
and laboratory accounts.

Initial research into SPI communication architecture 
identified a fundamental performance distinction between 
the two target environments.

## Key Finding
Linux OS: 4 layers (app → syscall → kernel → hardware)
Bare-metal: 1 layer (app → hardware registers directly)

This architectural difference forms the core hypothesis
for Task A performance gap characterization.

## Completed This Month
- Secure repository setup with branch protection
- SSH identity separation across machines
- Research plan documented (Tasks A-G mapped)
- Linux SPI benchmark code (linux/src/spi_benchmark.c)
- Bare-metal benchmark code (bare_metal/src/spi_benchmark_bare.c)
- Defense-in-depth security model documented
- JTAG attack surface identified and mitigation planned
- BASE v3.0 HSM connection to research scope established

## Next Month Goals
- Acquire external SSD for Vivado installation
- Install Vivado + PetaLinux toolchain
- Configure lab machine with same repo setup
- Run first actual benchmarks on ZC702 hardware
- Begin DMA implementation for Task B

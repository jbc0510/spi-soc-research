# Development Environment Setup Guide
Author: Jerry Conway (jbc0510)
Last Updated: March 2026

## SSH Key Setup for Multiple GitHub Accounts

### Keys Required
- Lab account (MSU-CAPC): ~/.ssh/id_ed25519
- Personal account (jbc0510): ~/.ssh/id_ed25519_personal

### Generate Personal Key
ssh-keygen -t ed25519 -C "jecon1@morgan.edu" -f ~/.ssh/id_ed25519_personal

### Verify Correct Account
ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes -T git@github.com
Expected: Hi jbc0510!

## Operational Rules (Learned the Hard Way)

### Rule 1 - Key Hygiene
Before setting up a new machine:
- Run: ssh-add -l (list all loaded keys)
- Run: ls ~/.ssh/ (see all key files)
- Remove any keys you cannot identify
- Know which key belongs to which account

### Rule 2 - Passphrase Management
- Write down passphrase IMMEDIATELY after creation
- Store in password manager before doing anything else
- If passphrase is lost, delete key and start over
- Never reuse passphrases across keys

### Rule 3 - Branch Discipline
- main  → finished, working, demo-ready only
- dev   → integration, testing, in-progress
- feature/* → active development
- Path: feature → dev → main (never skip dev)

### Rule 4 - Multi Machine Sync
- BEFORE sitting down → git pull
- BEFORE walking away → git push
- Never leave uncommitted work overnight

## Lab Server Tool Setup (capc-cl1-2)

### Source these before working:
# Set XILINX_ROOT to your local AMD/Xilinx install root, then source the tools.
# Example (this machine): Vivado/Vitis 2025.1 at
#   /home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1
export XILINX_ROOT=/home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1
source /tools/scripts/ee463-env.sh
source $XILINX_ROOT/Vivado/settings64.sh
source $XILINX_ROOT/Vitis/settings64.sh

### Cross Compiler (ARM Cortex-A9)
export PATH=$XILINX_ROOT/Vitis/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin:$PATH
Verify: arm-linux-gnueabihf-gcc --version

### Available Tools
Vivado  2025.1 → $XILINX_ROOT/Vivado/   (e.g. /home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/Vivado/)
Vitis   2025.1 → $XILINX_ROOT/Vitis/    (e.g. /home/opentitan/Documents/AMD/Vivado_2025.1_Enterprise/2025.1/Vitis/)
PetaLinux      → NOT INSTALLED

### Quick Setup Script
source ~/setup_spi_env.sh

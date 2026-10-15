# Vivado License Diagnostic — 2026-10-15

## Finding

The permanent Vivado ML Enterprise license is present and valid for synthesis on this workstation. The earlier expired-license result was produced by running Vivado and FlexNet diagnostics inside a restricted sandbox that could not read the workstation's network-interface identifiers. This caused FlexNet to report the node-locked license as invalid, and Vivado surfaced that failed checkout as an expired Synthesis feature.

## Evidence

- `~/.Xilinx/Xilinx(2).lic` contains `Vivado_ML_Enterprise_Edition` and `Vivado_Enterprise_Package`, with Enterprise tier and permanent license metadata. The package includes the Synthesis feature.
- The license is node-locked to the active Ethernet interface on this workstation. With normal host access, `lmutil lmdiag` reported: **“This is the correct node for this node-locked license”** for the Enterprise package and its Synthesis feature.
- With `XILINXD_LICENSE_FILE` explicitly set to this license file and `LM_LICENSE_FILE` unset, a fresh Vivado 2025.1 `synth_design` for `xczu9eg-ffvb1156-2-e` reported **“Got license for feature 'Synthesis' and/or device 'xczu9eg'”** and completed with zero errors.
- The successful test log is in [zcu9eg_license_synthesis.log](zcu9eg_license_synthesis.log). It synthesizes a one-input pass-through module, so it verifies license checkout and part targeting only; it is not a build of the project design.

AMD's Vivado 2025.1 device table lists Enterprise support for all Zynq UltraScale+ MPSoC devices, including the ZCU102's device family: [UG973 — Supported Devices](https://docs.amd.com/r/2025.1-English/ug973-vivado-release-notes-install-license/Supported-Devices).

## Root cause and scope

The Linux/container sandbox prevented FlexNet from reading host network-interface information (`Cannot open netlink socket`). The license is tied to a physical NIC address; the sandbox saw no usable host ID and returned an invalid-host diagnostic. Vivado then reported the synthesis checkout as expired. Repeating the check outside the sandbox resolved the checkout. The physical ZCU102 board was not involved in this synthesis-license check.

This clears the workstation's synthesis license as a blocker. It does not validate a full project implementation, bitstream generation, or board programming.

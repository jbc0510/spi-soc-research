# Platform Regen — Status (2026-07-15, OpenTitan machine)

## Diagnosis (confirmed, reproduced on clean retry)
create_zdma_platform.py fails with generic RPC error. Root cause is NOT
transient and NOT an RPC timeout — it is: **the platform is created without a
domain.** Reconnect-and-build the scaffold gives the real message:

    Error in generating platform. No domains available in the given platform 'spi_bm_plat'.

So create_platform_component() runs SDT gen + scaffolds the project, but does
NOT attach the standalone domain from the os=/cpu=/domain_name= args. No domain
-> nothing to build -> no .xpfm.

## Ruled out
- cpu name: SDT confirms node is psu_cortexa53_0 (correct in script).
- stale workspace: reproduced identically after rm -rf ws2 (clean).
- argument names: all accepted by the signature (help() checked).
- transient RPC: reproduced on clean retry — deterministic, not timing.

## The fix to try (NOT yet tested — needs the shipped API example)
Domain likely must be added as a SEPARATE step after platform creation, e.g.
platform.add_domain(cpu=..., os="standalone", name="standalone_psu_cortexa53_0",
display_name=...). Confirm exact signature from the shipped docs before running:
  - API docs: <VITIS>/Vitis/cli/api_docs/build/html/index.html
    (full path printed at `vitis -i` startup)
  - Or grep the CLI for a worked example:
    grep -rn "add_domain\|create_platform_component" \
      $XILINX_ROOT/Vitis/cli/ 2>/dev/null | head
Mirror the shipped example exactly rather than guessing arg names.

## State
- .xsa tracked: hardware/xsa/spi_benchmark_wrapper.xsa ✓
- create_zdma_platform.py written (dma/baremetal/) — creates platform but no
  domain; needs the add_domain step added once its signature is confirmed.
- Workspace bare_metal/vitis/ws2 currently removed (clean) after last retry.
- Toolchain: Vivado/Vitis 2025.1 at $XILINX_ROOT, on PATH, version-matched.

## After platform builds (.xpfm present)
1. vitis -s dma/baremetal/create_zdma_app.py   (builds spi_bm_zdma app)
2. verify ELF, package BOOT_zdma.bin, deploy (board path on THIS machine TBD —
   see PHASE3_HANDOFF.md section

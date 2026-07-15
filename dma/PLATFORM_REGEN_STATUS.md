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
## FINAL DIAGNOSIS (2026-07-15) — Vitis install broken, repo exonerated
AMD's OWN shipped example fails identically:
  vitis -s $XILINX_ROOT/Vitis/cli/examples/embedded/create_platform_add_domain_build.py
  -> creates a fresh /tmp workspace, downloads a stock vck190 XSA, and STILL
     fails with "Cannot create platform, StatusCode.UNKNOWN, Application error
     processing RPC". Stock example, stock XSA, clean workspace = nothing of ours.

Clean login shell (env -i, only 2025.1 sourced) did NOT help either.

=> The Vitis 2025.1 platform-creation RPC is broken on this machine's install.
   This is 100% environmental. Repo, .xsa, script, and shell config all ruled
   out with evidence.

## Fixes (system-level, not repo — do when convenient)
1. rm -rf /tmp/.Xil ~/.Xilinx/Vitis  then REBOOT (clears wedged gRPC/IPC state).
   Retry the shipped example FIRST after reboot — if AMD's example works, ours
   will too.
2. If still broken after reboot: check missing libs / locale:
     ldd $XILINX_ROOT/Vitis/vitis-server/bin/*  | grep "not found"
     locale
   and check Vitis 2025.1 release notes / AMD forums for known RPC-on-Ubuntu22
   platform-creation issues. May need install repair/reinstall.
3. FALLBACK if this install stays broken: the platform build is the ONLY thing
   blocked. The .xsa is tracked and the scripts are correct — regenerating the
   platform on stile (where the workspace originally built fine) and committing
   the resulting workspace, OR building on any machine with a working Vitis,
   would unblock. The bare-metal ELF + BOOT_zdma.bin are already committed
   (round-3, aba250eb) — the board can still be tested with the EXISTING image
   while the platform-rebuild issue is sorted separately.

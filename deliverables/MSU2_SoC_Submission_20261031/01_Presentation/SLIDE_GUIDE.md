# MSU-2 Task 2 evidence review — slide guide

Deck: `deliverables/MSU2_Task2_Evidence_Review_20261023_v54.pptx`
Evidence cutoff shown on the cover/status slide: 23 October 2026.

1. **Cover and scope.** Frames Task 2 around SPI performance, determinism, and secure integration, and says the deck covers measured comparisons, simulation, and open verification.
2. **Vivado block design.** Uses the actual Vivado/Nlview export from the project’s `spi_benchmark` block design, showing the ZynqMP PS, reset logic, AXI SmartConnect, AXI Quad SPI, clocking, and external SPI ports. The proposed ILA is not instantiated in this BD or the current FPGA image; physical wiring and SCK remain unmeasured.
3. **Performance gap (2a).** Compares Linux and bare-metal transfer performance across payload sizes; reports 11,000 transfers per path and zero API errors or receive mismatches.
4. **PIO/DMA mechanisms (2b).** Reports a six-size CDMA loopback simulation with byte-for-byte matching, clearly separating simulation from physical DMA validation.
5. **Real-time suitability (2c).** Shows that Linux timing spread increases as CPU frequency falls and states that the evidence does not establish a hard real-time guarantee.
6. **SOW status.** Summarizes completion/partial status for 2a–2g; 2e still needs a reliable clock/payload stress envelope, 2f still has open comparisons, and 2g has unresolved target recovery and bare-metal handoff.
7. **System-hardening design (2d).** Presents the proposed verified-boot and rollback architecture as a design result, not a deployed secure-boot system.
8. **Benchmark framework (2e).** Shows Linux CPU share falling with larger payloads and reports the paired comparison’s transfer integrity results.
9. **A/B update prototype (2g).** Describes the host-side update prototype and its fault-injection checks; it does not claim a production target update system.
10. **Vivado license diagnostic.** Records a workstation license-check problem encountered during the toolchain work and distinguishes the environment issue from the design results.
11. **Target update-control demo.** Summarizes the live Linux update-control demonstration and its defined test cases, with the limitations of temporary slots and missing persistent recovery noted.
12. **FIT signature verification.** Shows that host-side PetaLinux FIT signature checking rejected tampering; it is not evidence of a hardware-rooted secure boot chain.
13. **Boot-chain audit.** Explains how the generated boot policy and unsigned active chain limit the security claim; it distinguishes host verification from what the ZCU102 actually boots.
14. **Fixed-trial board comparison (2a/2e).** Presents Linux and bare-metal J55-loopback comparisons using 11 payload sizes × 1,000 trials, with both paths reporting zero transfer errors.
15. **Paired sustained windows (2e).** Shows 66 long-duration payload/backend points with verified bytes and zero mismatches; the requested clock is not presented as a measured physical SCK rate.
16. **Proposed operator workflow.** Illustrates the intended one-stop demonstration flow from run selection to evidence output; this is a proposal slide, not proof every mode is available.
17. **Additional bare-metal repeatability.** Reports 33 sustained points and 46.24 million byte-verified transfers, while retaining the topology/physical-clock caveats.
18. **Linux demo console.** Shows the working Linux menu and intended bare-metal menu choices. The update states that Linux menu/benchmark tests passed, but the bare-metal launch is blocked before menu entry.
19. **Selector package status.** Separates successful host-side FIT checks from unresolved target boot; no secure-boot success is claimed.
20. **Linux AXI SPI re-bring-up.** Summarizes how the SPI controller appeared after the validated PL image, clock, and reset were established; the slide’s single-byte smoke test is narrower than the later full menu run.
21. **Live Linux menu validation.** Reports the ZCU102 Linux operator workflow, 55,937 verified transfers, zero API errors/mismatches, and the limitation that physical SCK was not measured.
22. **Bare-metal handoff closeout.** Records two experimental handoff faults in U-Boot before menu entry, confirms normal Linux fallback, and states that bare-metal launch and secure boot remain unverified.

The deck’s main story is: the SPI performance and Linux menu evidence is substantial; simulation and host-side security prototypes are useful but bounded; physical clock/topology measurement, a stable benchmark stress envelope, and bare-metal handoff remain open before the deliverable can be called fully closed.

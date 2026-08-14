# DECISION — DMA scope for SOW 2.b (2026-08-14)

**DECIDED: the CDMA keyhole path is delivered as a validated pre-silicon
result. No hardware bring-up. This thread is closed.**

Decision owner: J. Conway. No sponsor request for DMA specifically has
been received; this is a self-directed scope decision on technical and
capacity grounds.

## What is being delivered for 2.b

PIO: complete. 11 payload sizes, 1000 trials, both environments.

DMA: two documented findings, neither a throughput measurement.
  1. ZDMA cannot drive PS SPI. Closed negative result, hardware register
     readback plus AMD documentation. Architecturally unsupported.
  2. CDMA keyhole into enhanced-mode AXI Quad SPI works. Proven in
     simulation on the v3 (axi_interconnect) topology.
     See hardware/sim/R6_SIM_FINDINGS.md, sections M1-M4 (commit 97dce50)
     and A5 (commit 8d19670).

## Why not take it to hardware

1. THE MEASUREMENT WOULD NOT SHOW WHAT IT APPEARS TO SHOW.
   With SPICR.SPE=1 the CDMA self-throttles to SCK (M3). DMA throughput
   is therefore SCK-bound and roughly equal to PIO. A hardware run would
   produce a DMA row indistinguishable from the PIO row. The real DMA
   advantage is CPU offload and determinism -- and CPU utilisation is
   measured in software instrumentation, not by bringing up the CDMA.

2. THE COMPARISON WOULD BE TRUNCATED.
   DMA source is PL BRAM, 8192 words x 32-bit. Enhanced mode passes one
   SPI byte per 32-bit beat, so maximum DMA SPI payload is 8,192 B
   against the PIO sweep's 65,536 B. Any joint table needs capping or
   footnoting regardless.

3. CAPACITY.
   Single researcher. SOW 2.d/2.f/2.g are unstarted with 2.f and 2.g due
   ~Dec 2026. Bring-up means a bitstream rebuild, a new BOOT.BIN with a
   .bit partition (the current bare-metal image has none -- 323,952 B,
   no room for a ~26 MB bitstream), and debug against an engine that has
   already consumed six rounds.

## What the SOW actually asks

2.b: "Analyze Data Transfer Mechanisms -- Assess the performance
characteristics of Programmed I/O (PIO) and Direct Memory Access (DMA)
across varying payload sizes."

An assessment is delivered: DMA is mechanically viable via CDMA keyhole,
is SCK-bound rather than throughput-advantaged, carries a hard FIFO
ceiling requiring SPE=1, and has a payload ceiling set by the BRAM
source. That is a characterisation, supported by simulation evidence.

## Consequence for 2.f -- MUST BE DISCLOSED

2.f requires "Compare Driver Performance: Evaluate the performance of
standard drivers relative to optimized DMA based transfers." No hardware
DMA numbers means this bullet is met by comparison against the
simulation-derived characterisation plus CPU-utilisation measurements,
not by a measured DMA throughput sweep.

DISCLOSE THIS IN THE SEPTEMBER MSR (risk section), proactively and in
writing, alongside the jitter correction and the Task 1 risk paragraph.
A timestamped disclosure four months early is a managed substitution;
the same fact surfacing in the final report is non-delivery.

## What would reverse this decision

Any one of:
  - A sponsor request for measured DMA throughput or DMA hardware
    validation.
  - A second researcher joining who can own 2.d/2.g, freeing capacity.
  - 2.d/2.f/2.g reaching a state where December delivery is secure with
    time remaining.
  - A finding that CPU-offload cannot be demonstrated without the DMA
    path running on silicon.

Absent one of these, do not reopen. Drifting back into DMA bring-up
without a stated reason is the failure mode this record exists to
prevent.

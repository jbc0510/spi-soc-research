# Task 2e — Benchmark-framework closure experiment

**Purpose:** Fill the remaining Task 2e measurement gaps with a paired physical run. The current fixed 1,000-trial sweep already supplies latency and integrity data for 11 common payload sizes; Linux loop metrics also supply thread CPU time. This plan adds a defined sustainable-throughput run, a comparable bare-metal CPU-occupancy field, and one run manifest tying both backends together.

**Readiness:** The ZCU102 was not reachable from the workstation session on 2026-10-15: no serial device was exposed and SSH to the last known address was unavailable. This plan is not a record of a new physical measurement.

## Shared run definition

Use the same validated FPGA image, AXI Quad SPI instance, external J55 MOSI-to-MISO loopback, SPI mode/word size, measured SCK, data pattern, and payload ladder in both environments. The shared contract is `common/spi_benchmark_contract.h`; the existing ladder is 1, 8, 16, 64, 128, 256, 512, 1,024, 4,096, 16,384, and 65,536 bytes. Keep the existing 1,000-trial latency/integrity sweep. Preserve the Linux and bare-metal raw logs and CSVs unchanged; emit a new paired run manifest with image hashes, software IDs, clocks, CPU point, timer sources, start/end times, and the output-file hashes.

## Sustainable-throughput test

Define a sustainable point as a **60-second continuous transfer window per payload size and software environment**, with no intentional delay between completed transactions. Use the common deterministic pattern and verify every received payload. Count only fully successful, byte-verified transfers. Report `verified_payload_bytes / measured_window_seconds` as the application-level sustainable payload rate; record attempted/successful transfers, API errors, timeouts, short returns, receive mismatches, and the longest observed transaction. Repeat each point three times and report each run plus the median rate. Do not call the highest value across sizes a universal hardware maximum; call it the maximum observed for this tested configuration.

Stop a point immediately after any mismatch, timeout, short transfer, or controller error. Preserve the failing run and do not automatically retry it as though it were valid data. Re-run only after recording and diagnosing the failure.

## CPU-utilization field

- **Linux:** retain `CLOCK_THREAD_CPUTIME_ID / CLOCK_MONOTONIC_RAW` over the exact 60-second loop, and report per-core benchmark-thread share. Also save `/proc/stat` deltas as a separate whole-system context measure; do not conflate the two.
- **Bare metal:** the current XSpi path busy-waits on `irq_state.terminal` until the interrupt handler reports completion and has no scheduler or idle task during the measurement loop. Report dedicated-core occupancy as 100% for this implementation, derived from its execution model, and label it `busy_wait_core_occupancy` rather than implying a PMU hardware measurement. If the implementation later sleeps while waiting, add an independently validated active/idle counter before comparing utilization.

CPU metrics cover the same wall interval as the sustained-rate measurement. Report the benchmark's source-copy, pattern-check, and RX-validation costs in the manifest; they are part of application-level CPU share and must not be silently removed from one backend.

## Execution order

1. Verify the image hash and identify the same AXI SPI controller and J55 loopback in both runs.
2. Capture measured SCK, PL/controller clock, A53 operating point, kernel or BSP build ID, and timer source.
3. Run the 1,000-trial common integrity/latency ladder on Linux and bare metal.
4. Run the 60-second no-delay sustained loop for each of the 11 payload sizes, three repetitions per environment. Alternate which environment runs first between repetitions to limit order effects.
5. Generate one manifest and validate that every backend has the required payload records and error counters before combining them.
6. Report Linux thread share and system CPU deltas separately from the bare-metal busy-wait core occupancy. Keep sustained application throughput separate from payload/mean-transaction-latency effective rate.

## Closure conditions

Task 2e can close when the same harness contract and patterns run in both environments, the latency and error counts validate, the sustained-throughput windows have complete raw evidence, and the CPU-utilization basis is recorded for both backends. Until then, the current results support a partial framework disposition; the 1,000-trial fixed ladder is not relabeled as a maximum-sustainable-throughput test.

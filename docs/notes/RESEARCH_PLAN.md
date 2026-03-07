# SPI Performance Research Plan
Author: Jerry Conway (jbc0510)
Last Updated: March 2026
Hardware: Xilinx ZC702 (Zynq-7000 SoC)

## Research Question
What is the measurable performance cost of the Linux kernel SPI stack
compared to direct bare-metal hardware execution on a Zynq-7000 SoC?

## Hardware Architecture
- PS (Processing System): ARM Cortex-A9 → runs Linux OS
- PL (Programmable Logic): FPGA fabric → runs bare-metal
- Interface: AXI bus connects PS to PL
- Target Protocol: SPI (Serial Peripheral Interface)

## Task Mapping

### Task A - Performance Gap Characterization
- Measure Linux SPI overhead vs bare-metal execution
- Location: linux/src/ vs bare_metal/src/
- Metric: transaction latency in microseconds

### Task B - Data Transfer Mechanisms  
- Compare PIO vs DMA across payload sizes
- Location: linux/src/ and bare_metal/src/
- Payloads: 1, 8, 16, 64, 128, 256 bytes

### Task C - Real Time Suitability
- Measure latency jitter under load
- Location: scripts/test/
- Metric: min/max/average/stddev latency

### Task D - System Hardening
- Secure boot implementation
- Location: bare_metal/src/
- Reference: BASE v3.0 HSM design

### Task E - Benchmarking Framework
- Unified test harness for both environments
- Location: scripts/test/
- Must run identical patterns on both targets

### Task F - OS Optimization
- Kernel configuration tuning
- Location: linux/src/
- Variables: preemption model, CPU scaling, interrupt handling

### Task G - Minimal Appliance
- Minimal Linux filesystem
- Location: linux/
- Requirements: secure boot, update mechanism, recovery

## Measurement Plan
| Metric          | Tool          | Location        |
|----------------|---------------|-----------------|
| Latency        | Logic analyzer| Hardware        |
| Throughput     | Custom C code | scripts/test/   |
| CPU utilization| top/perf      | linux/src/      |
| Jitter         | Custom C code | scripts/test/   |

## Monthly Milestones
- Month 1: Environment setup + repo structure ← YOU ARE HERE
- Month 2: Basic SPI benchmarks running on both targets
- Month 3: DMA implementation + comparative data
- Month 4: OS tuning + jitter analysis
- Month 5: Minimal appliance + secure boot
- Month 6: Final report + documentation

## Monthly Milestones
- Month 1: Environment setup + repo structure ← YOU ARE HERE
- Month 2: Basic SPI benchmarks on both targets
- Month 3: DMA implementation + comparative data
- Month 4: OS tuning + jitter analysis
- Month 5: Minimal appliance + secure boot
- Month 6: Final report + documentation

## Key Hypotheses to Prove

### Hypothesis 1 - OS Overhead
Linux 4-layer stack introduces measurable latency
vs bare-metal 2-layer direct register access.
Expected: bare-metal faster by significant margin.

### Hypothesis 2 - PIO vs DMA Crossover
PIO outperforms DMA below a certain payload threshold.
DMA outperforms PIO above that threshold.
Research goal: find exact crossover point in bytes
for Zynq ZC702 SPI controller.

### Hypothesis 3 - Jitter
Linux introduces non-deterministic jitter due to
kernel scheduling, interrupts, and context switching.
Bare-metal execution produces consistent, repeatable timing.

## Research Vision
Combine BASE v3.0 HSM silicon boot verification
with optimized SPI communication stack to create
a trusted embedded system with characterized
performance from boot to operation.

HSM verifies integrity → SPI communicates securely
Hardware root of trust + optimized secure channel

# DMA Benchmarking — Design Notes
## MSU-2 Task 2 | feature/dma-benchmarking

**SOW requirement:** Analyze PIO vs DMA data transfer mechanisms across varying payload sizes.
Map transfer sizes to the recommended software/DMA mode.

---

## Hardware

- **Board:** Xilinx ZCU102 (ZynqMP / Zynq UltraScale+ MPSoC)
- **SPI controller under test:** PS SPI1 (cadence_spi), EMIO-routed through PL fabric
- **Loopback:** Internal (MOSI → MISO, same as PIO baseline)
- **Clock:** ~0.9766 MHz SCK (62.5 MHz / 64) — must match PIO baseline exactly

## DMA engines available on ZynqMP

| Engine | Full name | Use case |
|--------|-----------|----------|
| ZDMA   | Zynq DMA (AXI DMA lite) | Bare-metal: simple scatter-gather, PS-only transfers |
| GDMA   | General-purpose DMA (FPD/LPD) | Linux: kernel DMAengine, used by cadence_spi driver |

## Two parallel paths

### Path A — Linux GDMA

The cadence_spi driver has DMA support via the ZynqMP GDMA engine.
Whether it is active depends on:

1. Kernel config: CONFIG_DMAENGINE, CONFIG_XILINX_DMA (or CONFIG_ZYNQMP_DMA)
2. Device tree: SPI1 node must have a `dmas` property binding to a GDMA channel
3. Payload threshold: the driver only uses DMA above a minimum transfer size

Audit checklist (Step 1.2 — to be filled from board):
- [ ] zcat /proc/config.gz | grep -E 'DMA|CADENCE|ZYNQMP'
- [ ] ls /sys/bus/dma/devices/
- [ ] grep -r dmas /proc/device-tree/amba/spi*/

### Path B — Bare-metal ZDMA

The ZynqMP ZDMA block (LPD-DMA, 8 channels) can move data between DDR and
PS peripheral FIFOs without CPU involvement during transfer.

- SPI1 TX FIFO address: 0xFF040000 + offset (to confirm from TRM)
- ZDMA base (LPD ch0): 0xFFA80000

Audit checklist (Step 3.1 — to be filled from TRM):
- [ ] Confirm SPI1 TX FIFO address from ZynqMP TRM Table 13-x
- [ ] Confirm ZDMA LPD channel base addresses
- [ ] Check if XZDma driver is in Vitis BSP or must be ported

---

## Baseline (from completed PIO work)

| Payload | BM PIO (µs) | Linux PIO (µs) | OS overhead |
|---------|------------|----------------|-------------|
| 1 B     | 10.3       | 38.5           | ~28 µs fixed |
| 1024 B  | 8,669.2    | 10,577.9       | ~1.22×      |
| 65536 B | 554,744.8  | 673,310.5      | ~1.21×      |

Fixed OS overhead: ~28 µs per transfer (payload-independent).
DMA hypothesis: large transfers should see CPU utilization drop significantly;
latency improvement modest but CPU freed for other work.

---

## New metric: CPU utilization

PIO baseline captured latency and jitter only.
DMA comparison adds:
- **Linux:** /proc/stat snapshots bracketing each transfer (idle delta -> CPU% busy)
- **Bare-metal:** cycle counter reads bracketing transfer (cycles burned vs. cycles idle)

---

## Git discipline for this branch

- Every step = one commit
- Commit message format: `dma: <path> — <what changed>`
- No benchmark results committed without the script that generated them
- Anchor-value validation required before trusting any new hardware read

---

## Audit findings (to be filled in board sessions)

### Step 1.2 — Kernel config (boot Linux, run on board as root)

```
# Commands:
# zcat /proc/config.gz | grep -E 'CONFIG_DMAENGINE|CONFIG_ZYNQMP_DMA|CONFIG_XILINX_DMA|CONFIG_DMA_ENGINE'
# zcat /proc/config.gz | grep -i cadence
# ls /sys/bus/dma/devices/

# Results:
# (paste here)
```

### Step 1.3 — Device tree SPI1 DMA binding (run on board as root)

```
# Commands:
# grep -r dmas /proc/device-tree/amba/ 2>/dev/null
# ls /proc/device-tree/amba/spi@ff0b0000/

# Results:
# (paste here)
```

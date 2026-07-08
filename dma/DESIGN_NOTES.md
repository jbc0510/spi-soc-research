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

---

## Step 1.2 — Kernel config audit (2026-07-08, board: newQspi, PetaLinux 2025.1)
cat >> dma/DESIGN_NOTES.md << 'EOF'

---

## Step 1.2 — Kernel config audit (2026-07-08, board: newQspi, PetaLinux 2025.1)
Kernel: $(uname -r) — PetaLinux 2025.1+release-S05180137
DMA drivers — all BUILT IN (=y):
CONFIG_XILINX_DMA=y
CONFIG_XILINX_ZYNQMP_DMA=y        ← ZynqMP GDMA driver present
CONFIG_XILINX_ZYNQMP_DPDMA=y
CONFIG_HAS_DMA=y
CONFIG_DMA_ENGINE=y  (implied by above)
CONFIG_DMA_CMA=y
CONFIG_IOMMU_DMA=y
CONFIG_NEED_SG_DMA_FLAGS=y
CONFIG_DMA_OPS_HELPERS=y
DMA test modules (=m, loadable):
CONFIG_XILINX_DMATEST=m
CONFIG_XILINX_VDMATEST=m
DMA devices at runtime:
/sys/bus/dma/devices/ — EMPTY (none registered)
Reason: no device tree node binds a GDMA channel to SPI1
SPI driver:
CONFIG_SPI_CADENCE=y              ← built in
CONFIG_SPI_CADENCE_QUADSPI=y
ZYNQMP platform:
CONFIG_XILINX_ZYNQMP_DMA=y
CONFIG_COMMON_CLK_ZYNQMP=y
CONFIG_RESET_ZYNQMP=y

## Step 1.3 — Device tree SPI1 DMA binding (2026-07-08)
/proc/device-tree/amba/spi@ff0b0000/ — node DOES NOT EXIST in base tree
/proc/device-tree/amba/spi@ff0b0000/dmas — NO dmas property
FINDING: DMA is not bound. The current overlay (spi_benchmark_pl.dts)
does not include a dmas property on the SPI1 node. The GDMA driver is
present and capable; the device tree is the only gap.
NEXT STEP (Phase 2, Step 2.1): Add dmas binding to the SPI1 node in
spi_benchmark_pl.dts and identify the correct GDMA channel for SPI1 RX/TX.
ZynqMP GDMA channels for SPI: LPD-DMA channels 0-7 (base 0xFFA80000).
SPI1 TX request line: confirm from ZynqMP TRM Table 13-2 (DMA request signals).

---

## Step 1.2 — Kernel config audit (2026-07-08, board: newQspi, PetaLinux 2025.1)

Kernel: 6.6.x (PetaLinux 2025.1+release-S05180137)

DMA drivers — all BUILT IN (=y):
  CONFIG_XILINX_DMA=y
  CONFIG_XILINX_ZYNQMP_DMA=y        (ZynqMP GDMA driver present)
  CONFIG_XILINX_ZYNQMP_DPDMA=y
  CONFIG_HAS_DMA=y
  CONFIG_DMA_ENGINE=y               (implied by above)
  CONFIG_DMA_CMA=y
  CONFIG_IOMMU_DMA=y
  CONFIG_NEED_SG_DMA_FLAGS=y
  CONFIG_DMA_OPS_HELPERS=y

DMA test modules (=m, loadable):
  CONFIG_XILINX_DMATEST=m
  CONFIG_XILINX_VDMATEST=m

DMA devices at runtime:
  /sys/bus/dma/devices/ — EMPTY (none registered)
  Reason: no device tree node binds a GDMA channel to SPI1

SPI driver:
  CONFIG_SPI_CADENCE=y              (built in)
  CONFIG_SPI_CADENCE_QUADSPI=y

ZynqMP platform:
  CONFIG_XILINX_ZYNQMP_DMA=y
  CONFIG_COMMON_CLK_ZYNQMP=y
  CONFIG_RESET_ZYNQMP=y

CONCLUSION: Kernel is fully capable. No rebuild needed.

---

## Step 1.3 — Device tree SPI1 DMA binding (2026-07-08)

  /proc/device-tree/amba/spi@ff0b0000/       — node DOES NOT EXIST in base tree
  /proc/device-tree/amba/spi@ff0b0000/dmas   — NO dmas property

FINDING: DMA is not bound. The current overlay (spi_benchmark_pl.dts)
does not include a dmas property on the SPI1 node. The GDMA driver is
present and capable in the kernel; the device tree binding is the only gap.

NEXT STEP (Phase 2, Step 2.1):
  Add dmas binding to the SPI1 node in spi_benchmark_pl.dts.
  Identify the correct GDMA channel for SPI1 RX/TX from ZynqMP TRM Table 13-2.
  ZynqMP LPD-DMA base: 0xFFA80000 (channels 0-7)
  SPI1 TX DMA request line: to be confirmed from TRM.

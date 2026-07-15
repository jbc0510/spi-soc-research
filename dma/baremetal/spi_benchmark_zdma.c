/*
 * spi_benchmark_zdma.c — ZynqMP bare-metal ZDMA SPI benchmark
 *
 * MSU-2 Task 2 — DMA vs PIO data transfer characterization
 * Cybersecurity Assurance & Policy (CAP) Center, Morgan State University
 *
 * PURPOSE:
 *   Measures SPI transfer latency using ZDMA (LPD-DMA) to move TX payload
 *   from DDR to PS SPI1 TX FIFO without CPU involvement during the transfer.
 *   Results are directly comparable to spi_benchmark_bare_zynqmp.c (PIO)
 *   since both use PS SPI1 at 0.9766 MHz SCK, same payload ladder, same
 *   1000-trial methodology.
 *
 * HARDWARE:
 *   - Controller : PS SPI1 (XPAR_XSPIPS_1), base 0xFF050000
 *   - TX FIFO    : 0xFF050000 + 0x1C = 0xFF05001C
 *   - ZDMA TX    : XPAR_XZDMA_8, base 0xFFA80000 (LPD-DMA ch0)
 *   - ZDMA RX    : XPAR_XZDMA_9, base 0xFFA90000 (LPD-DMA ch1)
 *   - SPI clock  : 62.5 MHz / 64 = 0.9766 MHz SCK (matches PIO baseline)
 *
 * DMA ARCHITECTURE:
 *   ZDMA Simple mode: src=DDR tx_buf, dst=SPI1 TX FIFO (0xFF05001C)
 *   CPU starts transfer, polls ZDMA done bit, measures wall-clock latency.
 *   CPU is NOT involved in moving bytes — only in setup and completion poll.
 *   This isolates DMA engine overhead vs PIO per-byte CPU cost.
 *
 * METHODOLOGY NOTE:
 *   The ZDMA cannot directly feed the SPI controller's shift register in
 *   hardware-flow-control mode (no DREQ line on PS SPI). Instead we use
 *   ZDMA to burst-fill the TX FIFO, then wait for SPI to drain. This
 *   removes per-byte CPU load but still requires SPI clock time.
 *   For payloads > FIFO depth (128 bytes), multiple ZDMA bursts are needed.
 *
 * RESULT STORAGE:
 *   Same JTAG-readable layout as PIO benchmark for direct comparison.
 *   g_done sentinel set after all results populated.
 *
 * COMPILE:
 *   Add to Vitis project alongside spi_benchmark_bare_zynqmp.c or as
 *   a separate application. Requires xzdma, xspips, xiltimer in BSP.
 */

#include <stdio.h>
#include <string.h>
#include "xparameters.h"
#include "xspips.h"
#include "xzdma.h"
#include "xzdma_hw.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "xtimer_config.h"   /* COUNTS_PER_SECOND */
#include "xil_io.h"
#include "xil_cache.h"
#include "xuartps.h"

/* ─────────────────────────────────────────
 * Hardware addresses — all verified from xparameters.h and TRM
 * ───────────────────────────────────────── */
#define SPI1_BASEADDR       XPAR_XSPIPS_1_BASEADDR      /* 0xFF050000 */
#define SPI1_REF_CTRL_ADDR  0xFF5E0080U                  /* CRL_APB SPI1_REF_CTRL */
#define SPI1_REF_CTRL_625   0x01001800U                  /* IOPLL/24 = 62.5 MHz */
#define SPI1_TXFIFO_ADDR    (SPI1_BASEADDR + XSPIPS_TXD_OFFSET)  /* 0xFF05001C */
#define SPI1_FIFO_DEPTH     128U                         /* TX FIFO depth in bytes */

#define ZDMA_TX_BASEADDR    XPAR_XZDMA_8_BASEADDR   /* 0xFFA80000, LPD-DMA ch0 */
#define ZDMA_RX_BASEADDR    XPAR_XZDMA_9_BASEADDR   /* 0xFFA90000, LPD-DMA ch1 */

/* ─────────────────────────────────────────
 * Benchmark configuration
 * ───────────────────────────────────────── */
#define NUM_TRIALS          1000
#define MAX_PAYLOAD         65536

static const int payload_sizes[] = {
    1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536
};
#define NUM_PAYLOADS (int)(sizeof(payload_sizes) / sizeof(payload_sizes[0]))

/* ─────────────────────────────────────────
 * Globals
 * ───────────────────────────────────────── */
static XSpiPs  Spi;
static XZDma   ZDmaTx;
static XZDma   ZDmaRx;

/* Aligned buffers — ZDMA requires cache-line alignment */
static u8 tx_buf[MAX_PAYLOAD] __attribute__((aligned(64)));
static u8 rx_buf[MAX_PAYLOAD] __attribute__((aligned(64)));

typedef struct {
    u64 min_ns;
    u64 max_ns;
    u64 avg_ns;
    u64 stddev_ns;
} benchmark_result_t;

benchmark_result_t results[NUM_PAYLOADS];
volatile u32 g_done = 0;
volatile u32 g_physics_fail = 0;   /* payloads with avg below wire floor */
volatile u32 g_rx_mismatch  = 0;   /* payloads whose RX != TX pattern    */

/* ─────────────────────────────────────────
 * Timing helpers — same as PIO benchmark
 * ───────────────────────────────────────── */
static inline u64 get_time_ns(void)
{
    u64 cnt;
    asm volatile("mrs %0, CNTPCT_EL0" : "=r"(cnt));
    return (cnt * 1000000000ULL) / COUNTS_PER_SECOND;
}

static u64 isqrt64(u64 n)
{
    if (n == 0) return 0;
    u64 x = n, y = 1;
    while (x > y) { x = (x + y) / 2; y = n / x; }
    return x;
}

/* ─────────────────────────────────────────
 * SPI1 initialisation — identical to PIO benchmark
 * ───────────────────────────────────────── */
static int spi_init(void)
{
    XSpiPs_Config *cfg;
    int status;

    cfg = XSpiPs_LookupConfig(SPI1_BASEADDR);
    if (!cfg) {
        xil_printf("SPI1 LookupConfig failed\r\n");
        return XST_FAILURE;
    }

    status = XSpiPs_CfgInitialize(&Spi, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("SPI1 CfgInitialize failed\r\n");
        return XST_FAILURE;
    }

    status = XSpiPs_SelfTest(&Spi);
    if (status != XST_SUCCESS) {
        xil_printf("SPI1 SelfTest failed\r\n");
        return XST_FAILURE;
    }

    XSpiPs_SetOptions(&Spi, XSPIPS_MASTER_OPTION | XSPIPS_FORCE_SSELECT_OPTION);
    XSpiPs_SetClkPrescaler(&Spi, XSPIPS_CLK_PRESCALE_64);

    /* Force SPI1_REF_CTRL to 62.5 MHz and verify */
    Xil_Out32(SPI1_REF_CTRL_ADDR, SPI1_REF_CTRL_625);
    u32 readback = Xil_In32(SPI1_REF_CTRL_ADDR);
    if (readback != SPI1_REF_CTRL_625) {
        xil_printf("SPI1_REF_CTRL verify FAILED: wrote 0x%08X read 0x%08X\r\n",
                   SPI1_REF_CTRL_625, readback);
        return XST_FAILURE;
    }

    XSpiPs_Enable(&Spi);
    XSpiPs_SetSlaveSelect(&Spi, 0x0);

    xil_printf("SPI1 init OK: SCK=0.9766 MHz, REF_CTRL=0x%08X\r\n", readback);
    return XST_SUCCESS;
}

/* ─────────────────────────────────────────
 * ZDMA initialisation
 * ───────────────────────────────────────── */
static int zdma_init(void)
{
    XZDma_Config *cfg;
    int status;

    /* TX channel (LPD-DMA ch0, 0xFFA80000) */
    cfg = XZDma_LookupConfig(ZDMA_TX_BASEADDR);
    if (!cfg) {
        xil_printf("ZDMA TX LookupConfig failed\r\n");
        return XST_FAILURE;
    }
    status = XZDma_CfgInitialize(&ZDmaTx, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("ZDMA TX CfgInitialize failed\r\n");
        return XST_FAILURE;
    }
    status = XZDma_SelfTest(&ZDmaTx);
    if (status != XST_SUCCESS) {
        xil_printf("ZDMA TX SelfTest failed\r\n");
        return XST_FAILURE;
    }
    /* Simple (non-scatter-gather) mode, write-only to peripheral */
    status = XZDma_SetMode(&ZDmaTx, FALSE, XZDMA_WRONLY_MODE);
    if (status != XST_SUCCESS) {
        xil_printf("ZDMA TX SetMode failed\r\n");
        return XST_FAILURE;
    }
/* TX burst config: destination is the SPI1 TXD register (0xFF05001C), a
     * SINGLE fixed address. Default DstBurstType is INCR -> DMA scatters bytes
     * across 0xFF05001C,1D,1E... and only byte 0 reaches the FIFO. This was the
     * root cause of anchor rounds 1-3 (bus-speed timing + first-byte-only RX).
     * Set destination FIXED; source (DDR tx_buf) stays INCR. */
    {
        XZDma_DataConfig TxCfg;
        XZDma_GetChDataConfig(&ZDmaTx, &TxCfg);
        TxCfg.SrcBurstType = XZDMA_INCR_BURST;
        TxCfg.DstBurstType = XZDMA_FIXED_BURST;
        XZDma_SetChDataConfig(&ZDmaTx, &TxCfg);
    }

    /* RX channel (LPD-DMA ch1, 0xFFA90000) */
    cfg = XZDma_LookupConfig(ZDMA_RX_BASEADDR);
    if (!cfg) {
        xil_printf("ZDMA RX LookupConfig failed\r\n");
        return XST_FAILURE;
    }
    status = XZDma_CfgInitialize(&ZDmaRx, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("ZDMA RX CfgInitialize failed\r\n");
        return XST_FAILURE;
    }
    status = XZDma_SetMode(&ZDmaRx, FALSE, XZDMA_RDONLY_MODE);
    if (status != XST_SUCCESS) {
        xil_printf("ZDMA RX SetMode failed\r\n");
        return XST_FAILURE;
    }

    xil_printf("ZDMA TX(ch8@0xFFA80000) RX(ch9@0xFFA90000) init OK\r\n");
    return XST_SUCCESS;
}

/* RX burst config: source is the SPI1 RXD register (0xFF050020), a SINGLE
     * fixed address. Default SrcBurstType is INCR -> DMA reads 0xFF050020,21...
     * instead of draining the one RXD register. Mirror of the TX fix:
     * source FIXED, destination (DDR rx_buf) INCR. */
    {
        XZDma_DataConfig RxCfg;
        XZDma_GetChDataConfig(&ZDmaRx, &RxCfg);
        RxCfg.SrcBurstType = XZDMA_FIXED_BURST;
        RxCfg.DstBurstType = XZDMA_INCR_BURST;
        XZDma_SetChDataConfig(&ZDmaRx, &RxCfg);
    }


/* ─────────────────────────────────────────
 * DMA-assisted SPI transfer
 *
 * Strategy for payloads > FIFO depth:
 *   Fill FIFO in ZDMA bursts of up to SPI1_FIFO_DEPTH bytes.
 *   Wait for TX FIFO not-full between bursts.
 *   CPU only polls DMA done and SPI status — not moving bytes.
 * ───────────────────────────────────────── */
static void zdma_spi_transfer(const u8 *src, u8 *dst, int len)
{
    int remaining = len;
    const u8 *src_ptr = src;
    u8 *dst_ptr = dst;
    XZDma_Transfer xfer;

    /* Flush TX buffer from cache before DMA reads it */
    Xil_DCacheFlushRange((UINTPTR)src, len);
    /* Invalidate RX buffer so CPU sees DMA-written data */
    Xil_DCacheInvalidateRange((UINTPTR)dst, len);

    /* Assert chip select */
    XSpiPs_SetSlaveSelect(&Spi, 0x0);

    while (remaining > 0) {
        int chunk = (remaining > (int)SPI1_FIFO_DEPTH) ?
                    (int)SPI1_FIFO_DEPTH : remaining;

        /* TX: DDR -> SPI1 TX FIFO */
        xfer.SrcAddr  = (UINTPTR)src_ptr;
        xfer.DstAddr  = SPI1_TXFIFO_ADDR;
        xfer.Size     = chunk;
        xfer.SrcCoherent = 0;
        xfer.DstCoherent = 0;
        xfer.Pause    = 0;

        XZDma_Start(&ZDmaTx, &xfer, 1);

        /* Poll TX DMA done */
        while (XZDma_ChannelState(&ZDmaTx) == XZDMA_BUSY) { /* spin */ }

        /* Clear sticky W1C TXOW NOW — FIFO holds chunk bytes, so the
         * below-threshold condition is FALSE and the clear sticks.
         * Clearing before the fill (round 2 bug) re-latched instantly
         * against an empty FIFO and the drain-wait was still a no-op. */
        Xil_Out32(SPI1_BASEADDR + XSPIPS_SR_OFFSET, XSPIPS_IXR_TXOW_MASK);

        /* Drain-wait: TXOW (cleared above) re-asserts only when FIFO
         * occupancy < TXWR threshold (reset default 1 = empty). Wire
         * time is spent HERE. RX DMA must run only after this drain —
         * chunk <= FIFO depth, so RX FIFO then holds all chunk bytes. */
        while (!(Xil_In32(SPI1_BASEADDR + XSPIPS_SR_OFFSET) &
                 XSPIPS_IXR_TXOW_MASK)) { /* spin */ }

        /* RX: SPI1 RX FIFO -> DDR */
        xfer.SrcAddr  = SPI1_BASEADDR + XSPIPS_RXD_OFFSET;
        xfer.DstAddr  = (UINTPTR)dst_ptr;
        xfer.Size     = chunk;

        XZDma_Start(&ZDmaRx, &xfer, 1);

        /* Poll RX DMA done */
        while (XZDma_ChannelState(&ZDmaRx) == XZDMA_BUSY) { /* spin */ }


        src_ptr   += chunk;
        dst_ptr   += chunk;
        remaining -= chunk;
    }

    /* Deassert chip select */
    XSpiPs_SetSlaveSelect(&Spi, 0xF);
}

/* ─────────────────────────────────────────
 * One payload benchmark sweep
 * ───────────────────────────────────────── */
static void run_benchmark(int payload_size, benchmark_result_t *result)
{
    u64 times[NUM_TRIALS];
    u64 sum = 0, sum_sq = 0;
    u64 min_t = UINT64_MAX, max_t = 0;
    int i;

    /* Fill TX buffer with known pattern */
    for (i = 0; i < payload_size; i++)
        tx_buf[i] = (u8)(i & 0xFF);

    /* Warm-up run (not timed) */
    zdma_spi_transfer(tx_buf, rx_buf, payload_size);

    /* Timed trials */
    for (i = 0; i < NUM_TRIALS; i++) {
        u64 t0 = get_time_ns();
        zdma_spi_transfer(tx_buf, rx_buf, payload_size);
        u64 t1 = get_time_ns();
        u64 elapsed = t1 - t0;
        times[i] = elapsed;
        sum += elapsed;
        if (elapsed < min_t) min_t = elapsed;
        if (elapsed > max_t) max_t = elapsed;
    }

    u64 avg = sum / NUM_TRIALS;

    for (i = 0; i < NUM_TRIALS; i++) {
        u64 diff = (times[i] > avg) ? (times[i] - avg) : (avg - times[i]);
        sum_sq += diff * diff;
    }
    u64 stddev = isqrt64(sum_sq / NUM_TRIALS);

    result->min_ns    = min_t;
    result->max_ns    = max_t;
    result->avg_ns    = avg;
    result->stddev_ns = stddev;

    /* ── Physics gate ──────────────────────────────────────────
     * At 0.9766 MHz SCK, one bit = 1024 ns exactly (62.5MHz/64),
     * so wire floor = payload * 8 * 1024 ns. Any average below
     * this is measuring the bus, not the wire (the failure mode
     * of the first anchor run). Machine-caught, not eyeballed. */
    {
        u64 wire_floor_ns = (u64)payload_size * 8192ULL;
        if (avg < wire_floor_ns) {
            xil_printf("  PHYSICS FAIL: %d B avg below wire floor\r\n",
                       payload_size);
            g_physics_fail++;
        }
    }

    /* ── Loopback data check (once per payload, untimed) ──────
     * rx_buf holds the last timed trial. Mismatch => wire did
     * not carry the data (or loopback path differs) — flagged,
     * not fatal, pending loopback wiring confirmation. */
    {
        int mism = 0;
        for (i = 0; i < payload_size; i++)
            if (rx_buf[i] != tx_buf[i]) { mism++; }
        if (mism) {
            xil_printf("  RX MISMATCH: %d B payload, %d bytes differ\r\n",
                       payload_size, mism);
            g_rx_mismatch++;
        }
    }
}

/* ─────────────────────────────────────────
 * Main
 * ───────────────────────────────────────── */
int main(void)
{
    int i, status;

    xil_printf("\r\n=== MSU-2 Bare-Metal ZDMA SPI Benchmark ===\r\n");
    xil_printf("Task 2: DMA vs PIO characterization\r\n");
    xil_printf("Payloads: %d sizes, %d trials each\r\n\r\n",
               NUM_PAYLOADS, NUM_TRIALS);

    status = spi_init();
    if (status != XST_SUCCESS) {
        xil_printf("SPI init FAILED — halting\r\n");
        return XST_FAILURE;
    }

    status = zdma_init();
    if (status != XST_SUCCESS) {
        xil_printf("ZDMA init FAILED — halting\r\n");
        return XST_FAILURE;
    }

    /* Anchor value for JTAG decimal/hex validation (same as PIO benchmark) */
    g_done = 0x0000D09E;
    xil_printf("Anchor: g_done=0x%08X (decimal %u)\r\n\r\n",
               (unsigned)g_done, (unsigned)g_done);

    xil_printf("%-10s %12s %12s %12s %12s\r\n",
               "Bytes", "Min(us)", "Max(us)", "Avg(us)", "Std(ns)");
    xil_printf("%-10s %12s %12s %12s %12s\r\n",
               "-----", "-------", "-------", "-------", "-------");

    for (i = 0; i < NUM_PAYLOADS; i++) {
        int sz = payload_sizes[i];
        run_benchmark(sz, &results[i]);

        xil_printf("%-10d %12llu %12llu %12llu %12llu\r\n",
                   sz,
                   results[i].min_ns / 1000,
                   results[i].max_ns / 1000,
                   results[i].avg_ns / 1000,
                   results[i].stddev_ns);
    }

    /* Sentinel — marks results[] fully populated for JTAG reader */
    /* ── Anchor verdict — the one line jeremiahc looks for ── */
    if (g_physics_fail == 0 && g_rx_mismatch == 0) {
        xil_printf("\r\nANCHOR VERDICT: PASS (all payloads >= wire floor, RX == TX)\r\n");
    } else {
        xil_printf("\r\nANCHOR VERDICT: FAIL — physics_fail=%u rx_mismatch=%u\r\n",
                   (unsigned)g_physics_fail, (unsigned)g_rx_mismatch);
    }

    g_done = 0xDEADBEEF;
    xil_printf("\r\nDone. g_done=0x%08X\r\n", (unsigned)g_done);

    return XST_SUCCESS;
}

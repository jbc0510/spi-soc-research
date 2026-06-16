/*
 * SPI Performance Benchmark - Bare-Metal Side (ZynqMP / ZCU102 port)
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZCU102 - Zynq UltraScale+ MPSoC (xczu9eg)
 *
 * Direct register/driver access via XSpiPs - no OS, no kernel, no Linux driver.
 * Counterpart to linux/src/spi_benchmark.c for the Task 2a/2e OS-vs-bare-metal
 * comparison. Measures SPI transaction LATENCY only (timing), matching the
 * methodology of results/emio_results.csv (which also measured timing, not
 * data integrity).
 *
 * PORTED FROM the Zynq-7000 version. Every hardware value below was read from
 * the generated BSP (xparameters.h / xspips_hw.h) or the live board, NOT
 * assumed:
 *   - Controller : PS SPI1, XPAR_XSPIPS_1, base 0xFF050000   (xparameters.h)
 *   - SPI ref clk: forced to 62.5 MHz via SPI1_REF_CTRL=0x01001800
 *                  (PS_CLOCK_VERIFICATION.md: IOPLL 1500 / 24 = 62.5 MHz)
 *   - Prescaler  : XSPIPS_CLK_PRESCALE_64 -> 62.5/64 = 0.9766 MHz SCK,
 *                  EXACTLY matching the Linux emio path (xspips.h enum = 0x05)
 *   - Timer freq : COUNTS_PER_SECOND (~99.99 MHz A53 generic timer)
 *                  (xparameters.h: XPAR_CPU_CORTEXA53_0_TIMESTAMP_CLK_FREQ)
 *
 * LOOPBACK NOTE: ZynqMP PS SPI (XSpiPs) has NO internal loopback bit
 * (confirmed: xspips_hw.h CR register has no LBK field). The XDC ties EMIO
 * SPI1 MISO input (F13/E13) to a PULLDOWN, so this is a TIMING-ONLY run; RX
 * data is undefined and intentionally NOT verified. A future Vivado rebuild
 * removing the pulldown + jumpering MOSI->MISO would enable a data-integrity
 * run (flagged, depends on Morgan workstation .xpr).
 *
 * Research Tasks: 2a (overhead vs direct HW), 2e (identical test patterns)
 */

#include <stdio.h>
#include <string.h>
#include "xparameters.h"
#include "xspips.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "xtimer_config.h"   /* COUNTS_PER_SECOND */
#include "xil_io.h"
#include "xuartps.h"

/* ─────────────────────────────────────────
 * Configuration
 * ───────────────────────────────────────── */
#define SPI_BASEADDR        XPAR_XSPIPS_1_BASEADDR    /* PS SPI1 (EMIO path), SDT base-addr lookup */
#define SPI1_REF_CTRL_ADDR  0xFF5E0080U               /* CRL_APB SPI1_REF_CTRL */
#define SPI1_REF_CTRL_625   0x01001800U               /* IOPLL/24 = 62.5 MHz  */

#define NUM_TRIALS          1000   /* publishable run */

/* Payload ladder - MUST match results/emio_results.csv exactly (Task 2e) */
static const int payload_sizes[] = {
    1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536
};
#define NUM_PAYLOADS (int)(sizeof(payload_sizes) / sizeof(payload_sizes[0]))

/* Largest payload drives the static buffer size */
#define MAX_PAYLOAD 65536

/* ─────────────────────────────────────────
 * Globals
 * ───────────────────────────────────────── */
static XSpiPs Spi;                 /* driver instance               */
static u8 tx_buf[MAX_PAYLOAD];     /* static - avoid heap on no-OS  */
static u8 rx_buf[MAX_PAYLOAD];     /* RX captured but NOT verified  */

typedef struct {
    u64 min_ns;
    u64 max_ns;
    u64 avg_ns;
    u64 stddev_ns;
} benchmark_result_t;

/* JTAG-readable capture: results[] at a fixed global address, and a
 * completion sentinel set AFTER the fill loop so a memory reader knows
 * the table is fully populated (avoids UART/baud entirely). */
benchmark_result_t results[NUM_PAYLOADS];
volatile u32 g_done = 0;

/* ─────────────────────────────────────────
 * Timing via the A53 generic timer (CNTPCT_EL0, read by XTime_GetTime).
 * COUNTS_PER_SECOND is provided by the BSP and equals the ~99.99 MHz
 * timestamp clock - NOT the CPU clock, and NOT the 7000-era 666 MHz
 * global timer from the original port. We work in integer nanoseconds
 * to avoid xil_printf's lack of %f.
 * ns = ticks * 1e9 / COUNTS_PER_SECOND, done in 64-bit.
 * ───────────────────────────────────────── */
static u64 get_ticks(void)
{
    XTime t;
    XTime_GetTime(&t);
    return (u64)t;
}
static u64 ticks_to_ns(u64 ticks)
{
    return (ticks * 1000000000ULL) / (u64)COUNTS_PER_SECOND;
}

/* ─────────────────────────────────────────
 * Force SPI1 reference clock to 62.5 MHz, then verify (RULE 1: re-read
 * after any clock write). This makes the driver's /64 prescaler land on
 * 0.9766 MHz, the exact SCK the Linux emio run used.
 * Returns 0 on success, -1 if the read-back does not confirm.
 * ───────────────────────────────────────── */
static int force_spi1_refclk_625(void)
{
    u32 readback;

    xil_printf("  SPI1_REF_CTRL before: 0x%08x\r\n",
               Xil_In32(SPI1_REF_CTRL_ADDR));

    Xil_Out32(SPI1_REF_CTRL_ADDR, SPI1_REF_CTRL_625);

    readback = Xil_In32(SPI1_REF_CTRL_ADDR);
    xil_printf("  SPI1_REF_CTRL after : 0x%08x (want 0x%08x)\r\n",
               readback, SPI1_REF_CTRL_625);

    if (readback != SPI1_REF_CTRL_625) {
        xil_printf("  ERROR: SPI1_REF_CTRL did not take - aborting.\r\n");
        return -1;
    }
    return 0;
}

/* ─────────────────────────────────────────
 * Initialize SPI1 as master, manual slave-select, /64 prescaler.
 * Uses the Xilinx driver init path (vendor-validated bring-up).
 * ───────────────────────────────────────── */
static int spi_init(void)
{
    XSpiPs_Config *cfg;
    int status;

    cfg = XSpiPs_LookupConfig(SPI_BASEADDR);
    if (cfg == NULL) {
        xil_printf("  ERROR: XSpiPs_LookupConfig failed for SPI1\r\n");
        return -1;
    }

    status = XSpiPs_CfgInitialize(&Spi, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("  ERROR: XSpiPs_CfgInitialize failed (%d)\r\n", status);
        return -1;
    }

    /* Confirm the controller responds before we trust any timing */
    status = XSpiPs_SelfTest(&Spi);
    if (status != XST_SUCCESS) {
        xil_printf("  ERROR: XSpiPs_SelfTest failed (%d)\r\n", status);
        return -1;
    }

    /* Master mode + drive slave-select manually from the controller */
    status = XSpiPs_SetOptions(&Spi,
                 XSPIPS_MASTER_OPTION | XSPIPS_FORCE_SSELECT_OPTION);
    if (status != XST_SUCCESS) {
        xil_printf("  ERROR: XSpiPs_SetOptions failed (%d)\r\n", status);
        return -1;
    }

    /* 62.5 MHz / 64 = 0.9766 MHz SCK - matches Linux emio path */
    status = XSpiPs_SetClkPrescaler(&Spi, XSPIPS_CLK_PRESCALE_64);
    if (status != XST_SUCCESS) {
        xil_printf("  ERROR: XSpiPs_SetClkPrescaler failed (%d)\r\n", status);
        return -1;
    }

    XSpiPs_SetSlaveSelect(&Spi, 0x00);   /* assert SS0 */
    return 0;
}

/* ─────────────────────────────────────────
 * One payload sweep. XSpiPs_PolledTransfer handles arbitrary length by
 * looping the 128-byte FIFO internally - the same "software manages a big
 * transfer over a small FIFO" cost the Linux spidev path incurred, which
 * is what makes the large-payload numbers comparable. RX is ignored.
 * ───────────────────────────────────────── */
static benchmark_result_t run_benchmark(int payload_size)
{
    benchmark_result_t result = {0};
    static u64 lat_ns[NUM_TRIALS];   /* static: keep off the stack */
    u64 sum = 0;
    int t, i;

    for (i = 0; i < payload_size; i++)
        tx_buf[i] = (u8)(i & 0xFF);   /* same pattern as Linux side */

    for (t = 0; t < NUM_TRIALS; t++) {
        u64 start = get_ticks();
        XSpiPs_PolledTransfer(&Spi, tx_buf, rx_buf, payload_size);
        u64 end = get_ticks();

        lat_ns[t] = ticks_to_ns(end - start);
        sum += lat_ns[t];
    }

    result.avg_ns = sum / (u64)NUM_TRIALS;
    result.min_ns = lat_ns[0];
    result.max_ns = lat_ns[0];

    /* Overflow-safe variance: divide each squared deviation by N BEFORE
     * accumulating, so the running sum stays ~3 orders below u64 max even
     * at the 64KB payload (where raw sum-of-squares would approach 1e19).
     * Per-term integer truncation is sub-ns on a ns^2 variance - negligible. */
    u64 variance = 0;
    for (t = 0; t < NUM_TRIALS; t++) {
        if (lat_ns[t] < result.min_ns) result.min_ns = lat_ns[t];
        if (lat_ns[t] > result.max_ns) result.max_ns = lat_ns[t];
        s64 diff = (s64)lat_ns[t] - (s64)result.avg_ns;
        variance += (u64)(diff * diff) / (u64)NUM_TRIALS;
    }
    /* integer sqrt of variance */
    u64 root = 0, bit = 1ULL << 62;
    while (bit > variance) bit >>= 2;
    while (bit != 0) {
        if (variance >= root + bit) { variance -= root + bit; root = (root >> 1) + bit; }
        else { root >>= 1; }
        bit >>= 2;
    }
    result.stddev_ns = root;

    return result;
}

/* ─────────────────────────────────────────
 * Main
 * ───────────────────────────────────────── */
int main(void)
{
    /* Console UART0 fix: psu_init left baud divisors assuming a 100 MHz
     * ref clock, but UART0_REF_CTRL runs at 166.67 MHz, so the default
     * xil_printf baud came out ~192k. Re-derive true 115200 from the
     * live clock via the driver before any output. */
    {
        XUartPs _con;
        XUartPs_Config *_uc = XUartPs_LookupConfig(XPAR_XUARTPS_0_BASEADDR);
        if (_uc) {
            XUartPs_CfgInitialize(&_con, _uc, _uc->BaseAddress);
            XUartPs_SetBaudRate(&_con, 115200);
        }
    }
    int p;

    xil_printf("\r\n========================================\r\n");
    xil_printf(" SPI Bare-Metal Benchmark - ZynqMP/ZCU102\r\n");
    xil_printf(" PS SPI1 @ 0.9766 MHz (62.5MHz/64), timing-only\r\n");
    xil_printf("========================================\r\n");

    if (force_spi1_refclk_625() != 0)
        return -1;

    if (spi_init() != 0)
        return -1;

    xil_printf("  SPI1 init + selftest OK. Prescaler=/64.\r\n\r\n");

    /* Live human-readable table (nanoseconds) */
    xil_printf("%-8s %12s %12s %12s %12s\r\n",
               "bytes", "min_ns", "avg_ns", "max_ns", "stddev_ns");
    xil_printf("-------- ------------ ------------ ------------ ------------\r\n");

    for (p = 0; p < NUM_PAYLOADS; p++) {
        results[p] = run_benchmark(payload_sizes[p]);
        xil_printf("%-8d %12lu %12lu %12lu %12lu\r\n",
            payload_sizes[p],
            results[p].min_ns, results[p].avg_ns,
            results[p].max_ns, results[p].stddev_ns);
    }
    /* table fully populated — signal JTAG reader */
    g_done = 0x0000D09E;
    __asm__ volatile ("dsb sy" ::: "memory");

    /* Machine-parseable CSV block, sentinel-bracketed. Columns in ns;
     * divide by 1000 in post to get us for diff against emio_results.csv. */
    xil_printf("\r\n---CSV-BEGIN---\r\n");
    xil_printf("bytes,avg_ns,stddev_ns\r\n");
    for (p = 0; p < NUM_PAYLOADS; p++) {
        xil_printf("%d,%lu,%lu\r\n",
            payload_sizes[p], results[p].avg_ns, results[p].stddev_ns);
    }
    xil_printf("---CSV-END---\r\n");

    xil_printf("\r\nBenchmark complete.\r\n");
    return 0;
}

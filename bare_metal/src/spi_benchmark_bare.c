/*
 * SPI Performance Benchmark - Bare-Metal Side
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZC702 (Zynq-7000 PS)
 *
 * Measures SPI transaction latency with direct
 * register access - no OS, no kernel, no drivers.
 *
 * Research Tasks: A, B, C, E
 */

#include <stdint.h>
#include <stdio.h>

/* ─────────────────────────────────────────
 * Zynq PS SPI Controller Register Map
 * Base address from Zynq TRM Table 16-1
 * ───────────────────────────────────────── */
#define SPI_BASE          0xE0006000

#define SPI_CR            (*(volatile uint32_t *)(SPI_BASE + 0x00))  /* Control    */
#define SPI_SR            (*(volatile uint32_t *)(SPI_BASE + 0x04))  /* Status     */
#define SPI_TXD           (*(volatile uint32_t *)(SPI_BASE + 0x1C))  /* TX FIFO    */
#define SPI_RXD           (*(volatile uint32_t *)(SPI_BASE + 0x20))  /* RX FIFO    */
#define SPI_ER            (*(volatile uint32_t *)(SPI_BASE + 0x14))  /* Enable     */

/* ─────────────────────────────────────────
 * SPI Control Register Bits
 * ───────────────────────────────────────── */
#define SPI_CR_MASTER     (1 << 2)   /* Master mode    */
#define SPI_CR_CS         (1 << 10)  /* Chip select    */
#define SPI_CR_BAUD_DIV4  (0x1 << 3) /* Clock div 4    */

/* ─────────────────────────────────────────
 * SPI Status Register Bits
 * ───────────────────────────────────────── */
#define SPI_SR_TXFULL     (1 << 3)   /* TX FIFO full   */
#define SPI_SR_RXNEMPTY   (1 << 4)   /* RX has data    */

/* ─────────────────────────────────────────
 * Global Timer - for measurement
 * Direct register access - no OS needed
 * ───────────────────────────────────────── */
#define GLOBAL_TIMER_BASE 0xF8F00200
#define GT_COUNT_L        (*(volatile uint32_t *)(GLOBAL_TIMER_BASE + 0x00))
#define GT_COUNT_H        (*(volatile uint32_t *)(GLOBAL_TIMER_BASE + 0x04))

/* ─────────────────────────────────────────
 * Configuration
 * ───────────────────────────────────────── */
#define NUM_TRIALS        1000
#define CPU_FREQ_HZ       666666687   /* Zynq PS CPU frequency */

static const int payload_sizes[] = {1, 8, 16, 64, 128, 256};
#define NUM_PAYLOADS (sizeof(payload_sizes) / sizeof(payload_sizes[0]))

/* ─────────────────────────────────────────
 * Timing structures - identical to Linux
 * version for direct comparison (Task E)
 * ───────────────────────────────────────── */
typedef struct {
    double min_us;
    double max_us;
    double avg_us;
    double stddev_us;
} benchmark_result_t;

/* ─────────────────────────────────────────
 * Read global timer - returns microseconds
 * ───────────────────────────────────────── */
static double get_time_us(void)
{
    uint32_t low  = GT_COUNT_L;
    uint32_t high = GT_COUNT_H;
    uint64_t ticks = ((uint64_t)high << 32) | low;
    return (double)ticks / (CPU_FREQ_HZ / 1e6);
}

/* ─────────────────────────────────────────
 * Initialize SPI controller directly
 * No kernel, no driver - just registers
 * ───────────────────────────────────────── */
static void spi_init(void)
{
    SPI_ER  = 0;                              /* disable first    */
    SPI_CR  = SPI_CR_MASTER                   /* master mode      */
            | SPI_CR_BAUD_DIV4                /* set clock speed  */
            | SPI_CR_CS;                      /* chip select high */
    SPI_ER  = 1;                              /* enable SPI       */
}

/* ─────────────────────────────────────────
 * Send and receive one byte directly
 * ───────────────────────────────────────── */
static uint8_t spi_transfer_byte(uint8_t data)
{
    while (SPI_SR & SPI_SR_TXFULL);  /* wait if TX full  */
    SPI_TXD = data;                  /* write to TX FIFO */
    while (!(SPI_SR & SPI_SR_RXNEMPTY)); /* wait for RX  */
    return (uint8_t)SPI_RXD;        /* read from RX FIFO */
}

/* ─────────────────────────────────────────
 * Transfer full payload - PIO mode
 * CPU moves every byte personally
 * ───────────────────────────────────────── */
static void spi_transfer_pio(uint8_t *tx, uint8_t *rx, int len)
{
    for (int i = 0; i < len; i++)
        rx[i] = spi_transfer_byte(tx[i]);
}

/* ─────────────────────────────────────────
 * Run benchmark for one payload size
 * Identical structure to Linux version
 * for direct comparison (Task E)
 * ───────────────────────────────────────── */
static benchmark_result_t run_benchmark(int payload_size)
{
    uint8_t tx[256];
    uint8_t rx[256];
    double latencies[NUM_TRIALS];
    double sum = 0.0;
    benchmark_result_t result = {0};

    /* Same test pattern as Linux version */
    for (int i = 0; i < payload_size; i++)
        tx[i] = (uint8_t)(i & 0xFF);

    /* ── Run trials ── */
    for (int t = 0; t < NUM_TRIALS; t++) {
        double start = get_time_us();
        spi_transfer_pio(tx, rx, payload_size);
        double end   = get_time_us();

        latencies[t] = end - start;
        sum += latencies[t];
    }

    /* ── Calculate statistics ── */
    result.avg_us = sum / NUM_TRIALS;
    result.min_us = latencies[0];
    result.max_us = latencies[0];

    double variance = 0.0;
    for (int t = 0; t < NUM_TRIALS; t++) {
        if (latencies[t] < result.min_us) result.min_us = latencies[t];
        if (latencies[t] > result.max_us) result.max_us = latencies[t];
        double diff = latencies[t] - result.avg_us;
        variance += diff * diff;
    }
    result.stddev_us = __builtin_sqrt(variance / NUM_TRIALS);

    return result;
}

/* ─────────────────────────────────────────
 * Main
 * ───────────────────────────────────────── */
int main(void)
{
    spi_init();

    printf("SPI Bare-Metal Benchmark Results\n");
    printf("=================================\n");
    printf("Mode:   PIO (direct register access)\n");
    printf("Trials: %d per payload size\n\n", NUM_TRIALS);
    printf("%-10s %-12s %-12s %-12s %-12s\n",
           "Bytes", "Min(us)", "Max(us)", "Avg(us)", "Stddev(us)");
    printf("─────────────────────────────────────────────────────\n");

    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(size);

        printf("%-10d %-12.2f %-12.2f %-12.2f %-12.2f\n",
               size, r.min_us, r.max_us, r.avg_us, r.stddev_us);
    }

    return 0;
}

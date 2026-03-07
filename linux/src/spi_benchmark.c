/*
 * SPI Performance Benchmark - Linux OS Side
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZC702 (Zynq-7000 PS)
 * 
 * Measures SPI transaction latency across varying
 * payload sizes using Linux spidev driver interface.
 * 
 * Research Tasks: A, B, C, E
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

/* ─────────────────────────────────────────
 * Configuration
 * ───────────────────────────────────────── */
#define SPI_DEVICE      "/dev/spidev0.0"
#define SPI_SPEED_HZ    1000000          /* 1MHz clock */
#define SPI_BITS        8                /* bits per word */
#define NUM_TRIALS      1000             /* iterations per test */

/* Payload sizes to test (Task B) */
static const int payload_sizes[] = {1, 8, 16, 64, 128, 256};
#define NUM_PAYLOADS (sizeof(payload_sizes) / sizeof(payload_sizes[0]))

/* ─────────────────────────────────────────
 * Timing structures
 * ───────────────────────────────────────── */
typedef struct {
    double min_us;      /* minimum latency microseconds */
    double max_us;      /* maximum latency microseconds */
    double avg_us;      /* average latency microseconds */
    double stddev_us;   /* jitter measurement */
} benchmark_result_t;

/* ─────────────────────────────────────────
 * Get current time in microseconds
 * ───────────────────────────────────────── */
static double get_time_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (ts.tv_sec * 1e6) + (ts.tv_nsec / 1e3);
}

/* ─────────────────────────────────────────
 * Run single SPI transaction
 * ───────────────────────────────────────── */
static int spi_transfer(int fd, uint8_t *tx, uint8_t *rx, int len)
{
    struct spi_ioc_transfer transfer = {
        .tx_buf        = (unsigned long)tx,
        .rx_buf        = (unsigned long)rx,
        .len           = len,
        .speed_hz      = SPI_SPEED_HZ,
        .bits_per_word = SPI_BITS,
    };
    return ioctl(fd, SPI_IOC_MESSAGE(1), &transfer);
}

/* ─────────────────────────────────────────
 * Run benchmark for one payload size
 * ───────────────────────────────────────── */
static benchmark_result_t run_benchmark(int fd, int payload_size)
{
    uint8_t tx[256] = {0};
    uint8_t rx[256] = {0};
    double latencies[NUM_TRIALS];
    double sum = 0.0;
    benchmark_result_t result = {0};

    /* Fill tx buffer with test pattern */
    for (int i = 0; i < payload_size; i++)
        tx[i] = (uint8_t)(i & 0xFF);

    /* ── Run trials ── */
    for (int t = 0; t < NUM_TRIALS; t++) {
        double start = get_time_us();
        spi_transfer(fd, tx, rx, payload_size);
        double end = get_time_us();

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
    int fd;

    /* Open SPI device */
    fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) {
        perror("Failed to open SPI device");
        return 1;
    }

    printf("SPI Linux Benchmark Results\n");
    printf("============================\n");
    printf("Device: %s\n", SPI_DEVICE);
    printf("Speed:  %d Hz\n", SPI_SPEED_HZ);
    printf("Trials: %d per payload size\n\n", NUM_TRIALS);
    printf("%-10s %-12s %-12s %-12s %-12s\n",
           "Bytes", "Min(us)", "Max(us)", "Avg(us)", "Stddev(us)");
    printf("──────────────────────────────────────────────────────\n");

    /* Run benchmark for each payload size */
    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(fd, size);

        printf("%-10d %-12.2f %-12.2f %-12.2f %-12.2f\n",
               size, r.min_us, r.max_us, r.avg_us, r.stddev_us);
    }

    close(fd);
    return 0;
}

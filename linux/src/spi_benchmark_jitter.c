/*
 * SPI Performance Benchmark - Linux OS Side (jitter re-capture build)
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZCU102 (ZynqMP PS), spidev
 *
 * Internal-loopback latency + REAL per-trial jitter (stddev) capture.
 * Matched to paper method: CLOCK_MONOTONIC_RAW, SCHED_FIFO, CPU0 pin, mlockall.
 * Writes a proper CSV (bytes,min_us,max_us,avg_us,stddev_us).
 */
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sched.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

#define CSV_PATH "/tmp/emio_internal_results.csv"

/* ─────────────────────────────────────────
 * Configuration
 * ───────────────────────────────────────── */
#define SPI_DEVICE      "/dev/spidev0.0"
#define SPI_SPEED_HZ    1000000          /* 1MHz clock */
#define SPI_BITS        8                /* bits per word */
#define NUM_TRIALS_LARGE 10
#define NUM_TRIALS_MED   100
#define NUM_TRIALS      1000             /* iterations per test */

/* Payload sizes to test (Task B) */
static const int payload_sizes[] = {1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536};
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
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
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
    uint8_t *tx = calloc(payload_size, 1);
    uint8_t *rx = calloc(payload_size, 1);
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

    /* Pin to CPU 0, real-time priority, lock memory: suppress scheduling jitter
       so the measured stddev reflects driver/PIO service, not preemption noise. */
    cpu_set_t set; CPU_ZERO(&set); CPU_SET(0, &set);
    if (sched_setaffinity(0, sizeof(set), &set) != 0)
        perror("warning: sched_setaffinity failed (continuing)");
    struct sched_param sp = { .sched_priority = 80 };
    if (sched_setscheduler(0, SCHED_FIFO, &sp) != 0)
        perror("warning: SCHED_FIFO failed (run as root for RT priority; continuing)");
    if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0)
        perror("warning: mlockall failed (continuing)");

    /* Open SPI device */
    fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) {
        perror("Failed to open SPI device");
        return 1;
    }

    /* Internal loopback: controller loops TX->RX, no header wiring needed. */
    uint8_t mode = 0;
    if (ioctl(fd, SPI_IOC_RD_MODE, &mode) == 0) {
        mode |= SPI_LOOP;
        if (ioctl(fd, SPI_IOC_WR_MODE, &mode) != 0)
            perror("warning: could not set SPI_LOOP (continuing)");
    }
    uint32_t spd = SPI_SPEED_HZ;
    if (ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &spd) != 0)
        perror("warning: could not set max speed (continuing)");

    printf("SPI Linux Benchmark Results\n");
    printf("============================\n");
    printf("Device: %s\n", SPI_DEVICE);
    printf("Speed:  %d Hz\n", SPI_SPEED_HZ);
    printf("Trials: %d per payload size\n\n", NUM_TRIALS);
    printf("%-10s %-12s %-12s %-12s %-12s\n",
           "Bytes", "Min(us)", "Max(us)", "Avg(us)", "Stddev(us)");
    printf("──────────────────────────────────────────────────────\n");

    FILE *csv = fopen(CSV_PATH, "w");
    if (csv) fprintf(csv, "bytes,min_us,max_us,avg_us,stddev_us\n");
    else perror("warning: could not open CSV (stdout only)");

    /* Run benchmark for each payload size */
    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(fd, size);

        printf("%-10d %-12.2f %-12.2f %-12.2f %-12.2f\n",
               size, r.min_us, r.max_us, r.avg_us, r.stddev_us);
        if (csv) {
            fprintf(csv, "%d,%.3f,%.3f,%.3f,%.3f\n",
                    size, r.min_us, r.max_us, r.avg_us, r.stddev_us);
            fflush(csv);
        }
    }

    if (csv) fclose(csv);
    close(fd);
    return 0;
}

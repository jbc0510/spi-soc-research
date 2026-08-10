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

/* CSV path is DERIVED FROM THE DEVICE at runtime -- see main().
 * It was previously hardcoded to "emio_internal_results.csv", which asserted
 * a controller the code never verified. That literal is the root cause of the
 * retraction in commit 0dc3d8f: an AXI-path capture was labeled EMIO. */
static char csv_path[256];

/* ─────────────────────────────────────────
 * Configuration
 * ───────────────────────────────────────── */
#define SPI_DEVICE_DEFAULT "/dev/spidev0.0"   /* override with argv[1] */
#define SPI_SPEED_HZ    1000000          /* 1MHz clock */
#define SPI_BITS        8                /* bits per word */
/* NUM_TRIALS_LARGE/MED removed: declared but never referenced.
 * run_benchmark uses NUM_TRIALS (1000) for the loop, the mean, AND the
 * variance divisor, so all stddevs are over the same n. */
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
int main(int argc, char **argv)
{
    int fd;
    const char *dev = (argc > 1) ? argv[1] : SPI_DEVICE_DEFAULT;
    const char *base = strrchr(dev, '/');
    snprintf(csv_path, sizeof(csv_path), "/tmp/jitter_%s.csv",
             base ? base + 1 : dev);

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
    fd = open(dev, O_RDWR);
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
    /* REQUEST, THEN READ BACK. The xilinx_spi driver ACKNOWLEDGES and IGNORES
     * speed requests (C_SCK_RATIO fixed at synthesis). Printing the request as
     * if it were the achieved rate is what produced the false "SCK: 1 MHz" in
     * commit 86bd14c while the wire actually ran near 15.6 MHz. */
    uint32_t spd_req = SPI_SPEED_HZ, spd_rb = 0;
    if (ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &spd_req) != 0)
        perror("warning: could not set max speed (continuing)");
    if (ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &spd_rb) != 0)
        perror("warning: could not read back max speed (continuing)");
    uint8_t mode_rb = 0;
    if (ioctl(fd, SPI_IOC_RD_MODE, &mode_rb) != 0)
        perror("warning: could not read back mode (continuing)");

    printf("SPI Linux Benchmark Results\n");
    printf("============================\n");
    printf("Device: %s\n", dev);
    printf("Speed requested: %u Hz\n", (unsigned)SPI_SPEED_HZ);
    printf("Speed readback:  %u Hz%s\n", (unsigned)spd_rb,
           (spd_rb != (uint32_t)SPI_SPEED_HZ) ? "   <-- DIFFERS FROM REQUEST" : "");
    printf("Mode readback:   0x%02x (SPI_LOOP %s)\n", mode_rb,
           (mode_rb & SPI_LOOP) ? "SET" : "NOT SET -- loopback must be in hardware");
    printf("NOTE: the authoritative rate is the achieved Mbps printed at the end,\n");
    printf("      NOT the request and NOT the ioctl readback.\n");
    printf("Trials: %d per payload size\n\n", NUM_TRIALS);
    printf("%-10s %-12s %-12s %-12s %-12s\n",
           "Bytes", "Min(us)", "Max(us)", "Avg(us)", "Stddev(us)");
    printf("──────────────────────────────────────────────────────\n");

    FILE *csv = fopen(csv_path, "w");
    if (csv) {
        fprintf(csv, "# device=%s\n", dev);
        fprintf(csv, "# speed_requested_hz=%u\n", (unsigned)SPI_SPEED_HZ);
        fprintf(csv, "# speed_readback_hz=%u\n", (unsigned)spd_rb);
        fprintf(csv, "# mode_readback=0x%02x spi_loop=%d\n",
                mode_rb, (mode_rb & SPI_LOOP) ? 1 : 0);
        fprintf(csv, "# CONTROLLER NOT ASSERTED BY THIS FILE. Verify which\n");
        fprintf(csv, "# controller this spidev node maps to before labeling.\n");
        fprintf(csv, "bytes,min_us,max_us,avg_us,stddev_us\n");
    }
    else perror("warning: could not open CSV (stdout only)");

    double big_avg_us = 0.0;   /* captured in the sweep for the achieved-rate check */

    /* Run benchmark for each payload size */
    for (size_t p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(fd, size);

        printf("%-10d %-12.2f %-12.2f %-12.2f %-12.2f\n",
               size, r.min_us, r.max_us, r.avg_us, r.stddev_us);
        if (csv) {
            fprintf(csv, "%d,%.3f,%.3f,%.3f,%.3f\n",
                    size, r.min_us, r.max_us, r.avg_us, r.stddev_us);
            fflush(csv);
        }
        if (p == NUM_PAYLOADS - 1) big_avg_us = r.avg_us;
    }

    /* Achieved rate from the largest payload: measured wire time cannot lie,
     * unlike the request or the ioctl readback. This is the check that would
     * have caught the July mislabeling on the day it happened. */
    {
        int big = payload_sizes[NUM_PAYLOADS - 1];
        if (big_avg_us <= 0.0) {
            printf("\nACHIEVED: unavailable (sweep did not complete)\n");
        } else {
        double mbps = (big * 8.0) / big_avg_us;
        printf("\nACHIEVED: %d B in %.2f us = %.2f Mbps\n", big, big_avg_us, mbps);
        printf("  (Mbps is payload throughput, NOT SCK. Per-word framing and\n");
        printf("   driver overhead make the ratio non-obvious -- e.g. 10.88 Mbps\n");
        printf("   was measured on a 15.6 MHz SCK. Compare Mbps between captures;\n");
        printf("   read SCK from CRL_APB or a scope if you need the clock.)\n");
        if (csv) fprintf(csv, "# achieved_mbps_at_%dB=%.2f\n", big, mbps);
        if (mbps > (SPI_SPEED_HZ / 1e6) * 1.5)
            printf("WARNING: achieved rate FAR EXCEEDS request -- the driver ignored\n"
                   "         the speed request. Do NOT label this capture with the\n"
                   "         requested rate.\n");
        }
    }
    if (csv) fclose(csv);
    close(fd);
    return 0;
}

/*
 * SPI Performance Benchmark - Linux spidev
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZCU102 (Zynq UltraScale+)
 *
 * Measures SPI transaction latency via spidev ioctl.
 * Isolates syscall overhead with 1-byte baseline test.
 * Exports results to CSV for Phase 6 comparison.
 *
 * Devices: /dev/spidev1.0 (PS SPI1 EMIO)
 *          /dev/spidev2.0 (PL AXI Quad SPI)
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
#include <math.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

/*===========================================================
 * Configuration
 *===========================================================*/
#define SPI_SPEED_HZ        10000000    /* 10 MHz                 */
#define SPI_BITS_PER_WORD   8
#define NUM_TRIALS          1000
#define MAX_PAYLOAD         4096
#define BASELINE_REPS       10000       /* for syscall overhead   */

static const int payload_sizes[] = {1, 4, 16, 64, 256, 1024, 4096};
#define NUM_PAYLOADS (sizeof(payload_sizes) / sizeof(payload_sizes[0]))

/*===========================================================
 * Result structure
 *===========================================================*/
typedef struct {
    double min_ns;
    double max_ns;
    double avg_ns;
    double stddev_ns;
    double throughput_kbps;
    double syscall_overhead_ns;
} benchmark_result_t;

/*===========================================================
 * High-resolution timer — CLOCK_MONOTONIC_RAW
 * Avoids NTP adjustments affecting measurements
 *===========================================================*/
static inline double get_time_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/*===========================================================
 * Single SPI ioctl transfer
 *===========================================================*/
static int spi_transfer(int fd, const uint8_t *tx, uint8_t *rx, int len)
{
    struct spi_ioc_transfer tr = {
        .tx_buf        = (unsigned long)tx,
        .rx_buf        = (unsigned long)rx,
        .len           = (uint32_t)len,
        .speed_hz      = SPI_SPEED_HZ,
        .bits_per_word = SPI_BITS_PER_WORD,
        .delay_usecs   = 0,
        .cs_change     = 0,
    };
    return ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
}

/*===========================================================
 * Open and configure spidev device
 *===========================================================*/
static int spi_open(const char *dev)
{
    int fd = open(dev, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", dev, strerror(errno));
        return -1;
    }

    uint8_t mode  = SPI_MODE_0;
    uint8_t bits  = SPI_BITS_PER_WORD;
    uint32_t speed = SPI_SPEED_HZ;

    if (ioctl(fd, SPI_IOC_WR_MODE, &mode)         < 0 ||
        ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
        ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0) {
        fprintf(stderr, "SPI config failed: %s\n", strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

/*===========================================================
 * Measure syscall overhead — 1-byte baseline
 * Isolates ioctl() + kernel SPI driver overhead
 *===========================================================*/
static double measure_syscall_overhead(int fd)
{
    uint8_t tx = 0xAA;
    uint8_t rx = 0;
    double total = 0.0;

    /* Warm up */
    for (int i = 0; i < 100; i++)
        spi_transfer(fd, &tx, &rx, 1);

    for (int i = 0; i < BASELINE_REPS; i++) {
        double t0 = get_time_ns();
        spi_transfer(fd, &tx, &rx, 1);
        double t1 = get_time_ns();
        total += (t1 - t0);
    }
    return total / BASELINE_REPS;
}

/*===========================================================
 * Run benchmark — one payload size
 *===========================================================*/
static benchmark_result_t run_benchmark(int fd, int payload_size,
                                         double syscall_overhead_ns)
{
    static uint8_t tx[MAX_PAYLOAD];
    static uint8_t rx[MAX_PAYLOAD];
    static double  latencies[NUM_TRIALS];

    benchmark_result_t result = {0};
    double sum = 0.0;

    /* Test pattern */
    for (int i = 0; i < payload_size; i++)
        tx[i] = (uint8_t)(i & 0xFF);

    /* Warm up */
    for (int w = 0; w < 10; w++)
        spi_transfer(fd, tx, rx, payload_size);

    /* Timed trials */
    for (int t = 0; t < NUM_TRIALS; t++) {
        double t0 = get_time_ns();
        if (spi_transfer(fd, tx, rx, payload_size) < 0) {
            fprintf(stderr, "Transfer failed at trial %d: %s\n",
                    t, strerror(errno));
        }
        double t1 = get_time_ns();
        latencies[t] = t1 - t0;
        sum += latencies[t];
    }

    /* Statistics */
    result.avg_ns = sum / NUM_TRIALS;
    result.min_ns = latencies[0];
    result.max_ns = latencies[0];
    result.syscall_overhead_ns = syscall_overhead_ns;

    double variance = 0.0;
    for (int t = 0; t < NUM_TRIALS; t++) {
        if (latencies[t] < result.min_ns) result.min_ns = latencies[t];
        if (latencies[t] > result.max_ns) result.max_ns = latencies[t];
        double diff = latencies[t] - result.avg_ns;
        variance += diff * diff;
    }
    result.stddev_ns = sqrt(variance / NUM_TRIALS);

    /* Throughput */
    double avg_sec = result.avg_ns / 1e9;
    result.throughput_kbps = ((double)payload_size * 8.0) / avg_sec / 1000.0;

    return result;
}

/*===========================================================
 * Benchmark one device and write CSV
 *===========================================================*/
static void benchmark_device(const char *dev, const char *label,
                              FILE *csv)
{
    int fd = spi_open(dev);
    if (fd < 0) {
        fprintf(stderr, "Skipping %s\n", dev);
        return;
    }

    fprintf(stderr, "Benchmarking %s (%s)...\n", dev, label);

    /* Syscall overhead baseline */
    double overhead_ns = measure_syscall_overhead(fd);
    fprintf(stderr, "  Syscall overhead (1-byte avg): %.1f ns\n",
            overhead_ns);

    /* Write overhead row */
    fprintf(csv, "%s,overhead,1,%.2f,%.2f,%.2f,%.2f,0.00\n",
            label, overhead_ns, overhead_ns, overhead_ns, 0.0);

    /* Payload sweep */
    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(fd, size, overhead_ns);

        fprintf(csv, "%s,transfer,%d,%.2f,%.2f,%.2f,%.2f,%.2f\n",
                label, size,
                r.min_ns, r.max_ns, r.avg_ns,
                r.stddev_ns, r.throughput_kbps);

        fprintf(stderr, "  [%s] %4d bytes: avg=%.0f ns  "
                "tput=%.1f Kbps  jitter=%.0f ns\n",
                label, size, r.avg_ns,
                r.throughput_kbps, r.stddev_ns);
    }

    close(fd);
}

/*===========================================================
 * Main
 *===========================================================*/
int main(int argc, char *argv[])
{
    const char *outfile = "linux_spi_benchmark.csv";
    if (argc > 1) outfile = argv[1];

    FILE *csv = fopen(outfile, "w");
    if (!csv) {
        perror("Cannot open output CSV");
        return 1;
    }

    /* CSV header */
    fprintf(csv, "device,type,bytes,min_ns,max_ns,avg_ns,"
                 "stddev_ns,throughput_kbps\n");

    /* Benchmark PS SPI1 via EMIO → /dev/spidev1.0 */
    benchmark_device("/dev/spidev1.0", "ps_spi1_emio", csv);

    /* Benchmark PL AXI Quad SPI → /dev/spidev2.0 */
    benchmark_device("/dev/spidev2.0", "pl_axi_spi",   csv);

    fclose(csv);

    printf("Results written to %s\n", outfile);
    return 0;
}

/*
 * spi_benchmark_clean.c
 * ---------------------------------------------------------------------------
 * Instrumented spidev throughput/latency benchmark for the ZCU102 SPI study.
 *
 * Fixes vs. the earlier harness (the ones that produced the ~11.1 MHz artifact):
 *
 *   1. ACHIEVED RATE READBACK.  After setting SPI_IOC_WR_MAX_SPEED_HZ we read
 *      SPI_IOC_RD_MAX_SPEED_HZ back.  The Cadence PS controllers report the
 *      clamped baud rate; the AXI Quad SPI reports its request but its real
 *      SCK is fixed by C_SCK_RATIO (ext_spi_clk/16 = 6.25 MHz) regardless.
 *      This number is what goes in the paper, NOT a back-calculation.
 *
 *   2. CORRECT FULL-DUPLEX ACCOUNTING.  SPI clocks MOSI and MISO on the same
 *      edges, so an N-byte exchange is N byte-times on the wire, i.e. N*8 bits
 *      at one bit/clock (standard single-lane mode, C_SPI_MODE=0).  We do NOT
 *      count tx+rx = 2N.  Counting 2N is the classic ~2x inflation that, minus
 *      protocol overhead, lands near the bogus 1.78x.
 *
 *   3. HONEST TIMING.  We time only the synchronous ioctl(SPI_IOC_MESSAGE),
 *      which blocks until the transfer completes, with warmup-and-discard and
 *      min/median/max over N trials.  No FIFO-fill-only window.
 *
 * Build (on the host, for the board):
 *   aarch64-linux-gnu-gcc -O2 -static spi_benchmark_clean.c -o spi_benchmark_clean
 *
 * Run (on the board):
 *   ./spi_benchmark_clean /dev/spidevB.0 [requested_hz]
 *   (find B via:  ls /dev/spidev*  and cross-check  dmesg | grep -i spi )
 *
 * Output: CSV to stdout.  Redirect per device, e.g.:
 *   ./spi_benchmark_clean /dev/spidev1.0 50000000 > emio_50mhz.csv
 *   ./spi_benchmark_clean /dev/spidev2.0 50000000 > axi_50mhz.csv
 * ---------------------------------------------------------------------------
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>

#define BITS_PER_WORD   8
#define DEFAULT_HZ      50000000u   /* matches the committed device tree */
#define WARMUP          50          /* discarded before timing           */
#define TRIALS          1000        /* timed iterations per payload size  */

/* Payload sweep, 1 B to 64 KiB (commit said "1B-65KB"). */
static const int payload_sizes[] = {
    1, 4, 16, 64, 256, 1024, 4096, 16384, 65536,
    262144, 1048576, 4194304, 16777216
};
#define NUM_PAYLOADS (int)(sizeof(payload_sizes)/sizeof(payload_sizes[0]))

static inline double now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static int cmp_double(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}

/* One synchronous full-duplex exchange of len bytes. */
static int spi_xfer(int fd, const uint8_t *tx, uint8_t *rx, int len, uint32_t hz)
{
    struct spi_ioc_transfer tr;
    memset(&tr, 0, sizeof(tr));
    tr.tx_buf        = (unsigned long)tx;
    tr.rx_buf        = (unsigned long)rx;
    tr.len           = (uint32_t)len;
    tr.speed_hz      = hz;
    tr.bits_per_word = BITS_PER_WORD;
    tr.delay_usecs   = 0;
    tr.cs_change     = 0;
    return ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s /dev/spidevB.0 [requested_hz]\n", argv[0]);
        return 2;
    }
    const char *dev = argv[1];
    uint32_t req_hz = (argc >= 3) ? (uint32_t)strtoul(argv[2], NULL, 0)
                                  : DEFAULT_HZ;

    int fd = open(dev, O_RDWR);
    if (fd < 0) { fprintf(stderr, "open %s: %s\n", dev, strerror(errno)); return 1; }

    uint8_t  mode = SPI_MODE_0;
    uint8_t  bits = BITS_PER_WORD;
    uint32_t wr_hz = req_hz, rd_hz = 0;

    if (ioctl(fd, SPI_IOC_WR_MODE, &mode) < 0)          { perror("WR_MODE"); }
    if (ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0) { perror("WR_BITS"); }
    if (ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &wr_hz) < 0) { perror("WR_SPEED"); }

    /* The number that settles the rate debate, per device, in software. */
    if (ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &rd_hz) < 0) { perror("RD_SPEED"); rd_hz = 0; }

    fprintf(stderr,
        "# device=%s  requested_hz=%u  driver_reported_hz=%u\n"
        "# NOTE: AXI Quad SPI driver reports the request but real SCK is fixed\n"
        "#       at ext_spi_clk/C_SCK_RATIO = 6.25 MHz. PS Cadence cores report\n"
        "#       the clamped baud divisor (the true achieved rate).\n",
        dev, req_hz, rd_hz);

    /* CSV header */
    printf("device,requested_hz,driver_reported_hz,size_bytes,trials,"
           "min_ns,median_ns,max_ns,throughput_Mbps_1lane\n");

    int max_len = payload_sizes[NUM_PAYLOADS - 1];
    uint8_t *tx = malloc(max_len), *rx = malloc(max_len);
    double  *t  = malloc(sizeof(double) * TRIALS);
    if (!tx || !rx || !t) { fprintf(stderr, "alloc failed\n"); return 1; }
    for (int i = 0; i < max_len; i++) tx[i] = (uint8_t)(i & 0xff);

    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int len = payload_sizes[p];

        for (int w = 0; w < WARMUP; w++)
            spi_xfer(fd, tx, rx, len, req_hz);

        for (int n = 0; n < TRIALS; n++) {
            double a = now_ns();
            if (spi_xfer(fd, tx, rx, len, req_hz) < 0) {
                fprintf(stderr, "xfer failed at len=%d: %s\n", len, strerror(errno));
                return 1;
            }
            double b = now_ns();
            t[n] = b - a;
        }
        qsort(t, TRIALS, sizeof(double), cmp_double);
        double tmin = t[0];
        double tmed = t[TRIALS / 2];
        double tmax = t[TRIALS - 1];

        /* Single-lane full-duplex: len bytes * 8 bits across the wire. */
        double mbps = (double)len * 8.0 / (tmed / 1e9) / 1e6;

        printf("%s,%u,%u,%d,%d,%.0f,%.0f,%.0f,%.3f\n",
               dev, req_hz, rd_hz, len, TRIALS, tmin, tmed, tmax, mbps);
        fflush(stdout);
    }

    free(tx); free(rx); free(t);
    close(fd);
    return 0;
}

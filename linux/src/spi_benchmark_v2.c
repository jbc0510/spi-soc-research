/*
 * SPI Performance Benchmark - Linux OS Side (v2, hardened harness)
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZCU102 (ZynqMP PS), spidev
 *
 * THIS IS THE HARNESS. Renamed from spi_benchmark_jitter.c 2026-08-14 --
 * the name understated it: this is the general Linux benchmark, not a
 * jitter-only build. Supersedes spi_benchmark.c (hardcoded device, no
 * speed readback, no achieved-rate check), which is retired.
 *
 * Internal-loopback latency + REAL per-trial jitter (stddev) capture.
 * Matched to paper method: CLOCK_MONOTONIC_RAW, SCHED_FIFO, CPU0 pin, mlockall.
 *
 * CSV: bytes,min_us,max_us,avg_us,stddev_us,
 *      cpu_us,wall_us,cpu_pct,nvcsw,nivcsw,err_count,first_errno
 * err_count/first_errno added 2026-08-14 (D1). Failed ioctls are excluded
 * from the timing stats; a row with err_count==NUM_TRIALS carries -1 in
 * every timing column. first_errno 0 means no failure observed.
 * CPU columns added 2026-08-14 for SOW 2.e (never previously
 * measured). cpu_pct is THREAD CPU over the trial loop only.
 * Device selection is argv[1]; CSV path is derived from it. Neither
 * asserts a controller -- verify the node mapping before labeling.
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
#include <sys/resource.h>
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
    /* SOW 2.e CPU utilisation. Measured across the TRIAL LOOP ONLY --
     * not the calloc/fill/variance work, which is not part of what
     * avg_us measures. cpu_pct is THREAD CPU (CLOCK_THREAD_CPUTIME_ID),
     * NOT process CPU -- a change of meaning, not just resolution. The
     * harness is single-threaded so the two are identical today, but a
     * future thread's work will not leak into this column.
     * Hardirq and softirq time are never charged to the task by either
     * interface, so this still UNDER-COUNTS true system cost. Label
     * accordingly. */
    double cpu_us;      /* CLOCK_THREAD_CPUTIME_ID delta, microseconds */
    double wall_us;     /* CLOCK_MONOTONIC_RAW delta over same interval */
    double cpu_pct;     /* 100 * cpu_us / wall_us */
    long   nvcsw;       /* voluntary context switches */
    long   nivcsw;      /* involuntary -- the OS-jitter mechanism */
    /* D1: ioctl outcome accounting. A failed SPI_IOC_MESSAGE returns fast
     * and would otherwise be timed as a plausible short latency. Failed
     * trials are EXCLUDED from min/max/avg/stddev. first_errno is the only
     * column where 0 legitimately means "none observed" -- errno is never
     * 0 on failure, so no sentinel is needed. */
    int    err_count;   /* trials where ioctl returned < 0 */
    int    first_errno; /* errno of the first failure; 0 = no failure */
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

    /* D2: allocation can fail at 65536 B, more readily with mlockall
     * active. Unchecked, the fill loop below would write through NULL.
     * Emit a visibly NOT-MEASURED row rather than a plausible one. */
    if (!tx || !rx) {
        free(tx); free(rx);        /* free(NULL) is defined */
        result.avg_us = result.min_us = result.max_us = result.stddev_us = -1.0;
        result.cpu_pct = -1.0;
        result.nvcsw = result.nivcsw = -1;
        result.first_errno = ENOMEM;
        return result;
    }

    /* Fill tx buffer with test pattern */
    for (int i = 0; i < payload_size; i++)
        tx[i] = (uint8_t)(i & 0xFF);

    /* D2: PRE-FAULT rx. tx is faulted in by the fill loop above; rx's
     * first write would otherwise be inside trial 0 -- 16 pages at 64 KB,
     * charged to ru_stime and inflating max_us, a published jitter stat.
     * mlockall(MCL_FUTURE) may cover this, but it perror()s and continues
     * on failure and fails outright when not run as root, which would
     * make the jitter numbers depend on privilege level.
     * DELIBERATE MEASUREMENT CHOICE: first-touch faulting is a real cost
     * a naive Linux program pays, but the comparison target is bare-metal,
     * which has no demand paging at all. SOW 2.a asks for the KERNEL SPI
     * STACK overhead, not the allocator's. Faults are excluded on purpose. */
    memset(rx, 0, payload_size);

    /* ── Run trials ── */
    struct rusage ru0, ru1;
    struct timespec c0, c1;
    /* D3: getrusage's ru_utime/ru_stime are TICK-QUANTIZED unless the
     * kernel has CONFIG_VIRT_CPU_ACCOUNTING_GEN. At 250 Hz that is a 4 ms
     * floor; the 1 B payload runs ~38.5 ms of loop, about 10 ticks, so
     * +/-10% quantization on the smallest and most interesting payload.
     * CLOCK_THREAD_CPUTIME_ID reads task_sched_runtime at ns resolution.
     * getrusage is RETAINED for nvcsw/nivcsw -- no other API supplies
     * them. Read order is rusage-outermost so its own cost falls outside
     * the CPU interval, not inside it. */
    getrusage(RUSAGE_SELF, &ru0);
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &c0);
    double wall0 = get_time_us();
    int n_ok = 0;
    for (int t = 0; t < NUM_TRIALS; t++) {
        double start = get_time_us();
        int rc = spi_transfer(fd, tx, rx, payload_size);
        double end = get_time_us();

        if (rc < 0) {
            if (result.err_count == 0) result.first_errno = errno;
            result.err_count++;
            continue;   /* a failed ioctl's elapsed time is not a latency */
        }
        /* COMPACTED index: n_ok, not t. The stats loop below reads
         * latencies[0 .. n_ok-1]; indexing by t would leave holes. */
        latencies[n_ok] = end - start;
        sum += latencies[n_ok];
        n_ok++;
    }
    double wall1 = get_time_us();
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &c1);
    getrusage(RUSAGE_SELF, &ru1);

    result.wall_us = wall1 - wall0;
    result.cpu_us =
        ((double)(c1.tv_sec - c0.tv_sec) * 1e6) +
        ((double)(c1.tv_nsec - c0.tv_nsec) / 1e3);
    result.cpu_pct = (result.wall_us > 0.0)
                   ? (100.0 * result.cpu_us / result.wall_us) : -1.0;
    result.nvcsw  = ru1.ru_nvcsw  - ru0.ru_nvcsw;
    result.nivcsw = ru1.ru_nivcsw - ru0.ru_nivcsw;

    /* ── Calculate statistics ──
     * Divisor is n_ok, NOT NUM_TRIALS. On a clean run they are equal, so
     * no previously published number moves; if any trial failed, dividing
     * by NUM_TRIALS would average real values over a phantom count. */
    if (n_ok > 0) {
        result.avg_us = sum / n_ok;
        result.min_us = latencies[0];
        result.max_us = latencies[0];

        double variance = 0.0;
        for (int i = 0; i < n_ok; i++) {
            if (latencies[i] < result.min_us) result.min_us = latencies[i];
            if (latencies[i] > result.max_us) result.max_us = latencies[i];
            double diff = latencies[i] - result.avg_us;
            variance += diff * diff;
        }
        result.stddev_us = __builtin_sqrt(variance / n_ok);
    } else {
        /* Every trial failed. Timing columns get the -1 sentinel, per the
         * nvcsw convention: -1 means NOT MEASURED, 0 would read as
         * "measured, and it was zero". The CPU/rusage columns above are
         * NOT sentinelled -- they are a true measurement of what the
         * process did, even though every transfer failed. */
        result.avg_us = result.min_us = result.max_us = result.stddev_us = -1.0;
    }

    free(tx);
    free(rx);
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

    /* D5: the old path was /tmp/jitter_<dev>.csv. Two problems: the name
     * said "jitter" after the harness was renamed away from jitter-only
     * (f4e8237), and a re-run SILENTLY DESTROYED the previous capture --
     * no trace, no backup. The timestamp makes every run a distinct file
     * and is ALSO written into the header, so a file that is later
     * renamed by hand still carries its own origin. */
    time_t now = time(NULL);
    struct tm tm_utc;
    char stamp[32] = "unknown";
    if (gmtime_r(&now, &tm_utc))
        strftime(stamp, sizeof(stamp), "%Y%m%d_%H%M%S", &tm_utc);
    snprintf(csv_path, sizeof(csv_path), "/tmp/spi_bench_%s_%s.csv",
             base ? base + 1 : dev, stamp);

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
        fprintf(csv, "# capture_utc=%s\n", stamp);
        fprintf(csv, "# device=%s\n", dev);
        fprintf(csv, "# speed_requested_hz=%u\n", (unsigned)SPI_SPEED_HZ);
        fprintf(csv, "# speed_readback_hz=%u\n", (unsigned)spd_rb);
        fprintf(csv, "# mode_readback=0x%02x spi_loop=%d\n",
                mode_rb, (mode_rb & SPI_LOOP) ? 1 : 0);
        fprintf(csv, "# CONTROLLER NOT ASSERTED BY THIS FILE. Verify which\n");
        fprintf(csv, "# controller this spidev node maps to before labeling.\n");
        fprintf(csv, "# cpu_pct is THREAD CPU over the trial loop only\n");
        fprintf(csv, "# (CLOCK_THREAD_CPUTIME_ID, ns resolution -- NOT the\n");
        fprintf(csv, "# tick-quantized getrusage utime/stime). Hardirq and\n");
        fprintf(csv, "# softirq time are never charged to the task, so this\n");
        fprintf(csv, "# under-counts true system cost.\n");
        fprintf(csv, "# err_count = trials whose ioctl returned < 0; those\n");
        fprintf(csv, "# trials are EXCLUDED from min/max/avg/stddev. A row\n");
        fprintf(csv, "# with -1 timing columns means every trial failed.\n");
        fprintf(csv, "# first_errno: 0 means NO FAILURE (errno is never 0 on\n");
        fprintf(csv, "# failure), so 0 needs no sentinel here.\n");
        fprintf(csv, "bytes,min_us,max_us,avg_us,stddev_us,cpu_us,wall_us,cpu_pct,nvcsw,nivcsw,err_count,first_errno\n");
    }
    else perror("warning: could not open CSV (stdout only)");

    double big_avg_us = 0.0;   /* captured in the sweep for the achieved-rate check */
    int total_errs = 0;        /* summed err_count across the whole sweep */
    int first_errno_seen = 0;  /* 0 = no failure anywhere; errno is never 0 */

    /* Run benchmark for each payload size */
    for (size_t p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(fd, size);

        printf("%-10d %-12.2f %-12.2f %-12.2f %-12.2f  cpu=%6.2f%% ivcsw=%ld err=%d\n",
               size, r.min_us, r.max_us, r.avg_us, r.stddev_us,
               r.cpu_pct, r.nivcsw, r.err_count);
        total_errs += r.err_count;
        if (first_errno_seen == 0 && r.first_errno != 0)
            first_errno_seen = r.first_errno;
        if (csv) {
            fprintf(csv, "%d,%.3f,%.3f,%.3f,%.3f,%.1f,%.1f,%.2f,%ld,%ld,%d,%d\n",
                    size, r.min_us, r.max_us, r.avg_us, r.stddev_us,
                    r.cpu_us, r.wall_us, r.cpu_pct, r.nvcsw, r.nivcsw,
                    r.err_count, r.first_errno);
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
    /* D1: ioctl failures are invisible in the timing columns by design --
     * failed trials are excluded from them. Surface the count here so a
     * partial-failure sweep is not mistaken for a clean one. */
    if (total_errs > 0)
        printf("\nWARNING: %d ioctl failure(s) across the sweep"
               " (first errno %d: %s).\n"
               "         Failed trials were EXCLUDED from the timing"
               " statistics.\n"
               "         Per-payload counts are in the err_count column"
               " of %s.\n",
               total_errs, first_errno_seen, strerror(first_errno_seen),
               csv_path);

    if (csv) fclose(csv);
    close(fd);
    return 0;
}

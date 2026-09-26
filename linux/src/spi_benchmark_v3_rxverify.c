/* Fresh AXI experiment; never overwrites v2 binaries or historical captures. */
#define _GNU_SOURCE
#include "spi_benchmark_contract.h"
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/spi/spidev.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

static uint8_t tx[SPI_BENCH_MAX_PAYLOAD], rx[SPI_BENCH_MAX_PAYLOAD];

static int now_ns(clockid_t clock, uint64_t *ns)
{
    struct timespec ts;
    if (clock_gettime(clock, &ts)) return -1;
    *ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
    return 0;
}

int main(int argc, char **argv)
{
    const char *device = argc > 1 ? argv[1] : "/dev/spidev1.0";
    uint32_t speed = 15623438U; /* request only; NOT a physical SCK claim */
    if (argc > 3) {
        fprintf(stderr, "usage: %s [device [requested_speed_hz]]\n", argv[0]);
        return 2;
    }
    if (argc > 2) {
        char *end;
        errno = 0;
        unsigned long v = strtoul(argv[2], &end, 10);
        if (errno || end == argv[2] || *end || v == 0 || v > UINT32_MAX) return 2;
        speed = (uint32_t)v;
    }
    int fd = open(device, O_RDWR);
    if (fd < 0) { perror("open SPI device"); return 2; }
    uint32_t mode = SPI_MODE_0, mode_rb = UINT32_MAX, speed_rb = 0;
    uint8_t bits = 8, bits_rb = 0;
    if (ioctl(fd, SPI_IOC_WR_MODE32, &mode) < 0 ||
        ioctl(fd, SPI_IOC_RD_MODE32, &mode_rb) < 0 ||
        ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
        ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &bits_rb) < 0 ||
        ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0 ||
        ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed_rb) < 0) {
        perror("SPI configuration/readback"); close(fd); return 2;
    }
    if (mode_rb != mode || bits_rb != bits) {
        fprintf(stderr, "configuration mismatch: mode=0x%x bits=%u\n", mode_rb, bits_rb);
        close(fd); return 2;
    }
    struct utsname uts;
    puts("# MSU-2 Linux RX verification Phase 1; hardware_validation=NOT_PERFORMED");
    if (uname(&uts) == 0) printf("# kernel=%s version=%s\n", uts.release, uts.version);
    printf("# device=%s controller_identity=UNVERIFIED uid=%u\n", device, (unsigned)getuid());
    printf("# mode_requested=0x%x mode_readback=0x%x bits_readback=%u\n", mode, mode_rb, bits_rb);
    printf("# speed_requested_hz=%u speed_readback_hz=%u physical_sck_hz=UNKNOWN\n", speed, speed_rb);
    puts("# topology=UNVERIFIED intended_topology=external_MOSI_to_MISO spi_loop_requested=0");
    puts("# timer=CLOCK_MONOTONIC_RAW unit=ns frequency_conversion=POSIX_timespec");
    puts("# samples=API_full_length_success_AND_RX_verified_AND_valid_timer population_stddev=1");
    puts("# trial_indices=zero_based invalid_timing=-1_ns timeout_handling=kernel_dependent_no_userspace_deadline");
    puts("# cpu_scope=whole_trial_loop_including_poison_verification_accounting excludes_IRQ_cost");
    puts("# scheduling=unchanged affinity=unchanged memory_lock=not_requested");
    FILE *bf = fopen("/sys/module/spidev/parameters/bufsiz", "r");
    unsigned long bufsiz;
    if (bf && fscanf(bf, "%lu", &bufsiz) == 1) printf("# spidev_bufsiz=%lu\n", bufsiz);
    else puts("# spidev_bufsiz=UNKNOWN");
    if (bf) fclose(bf);
    puts("---CSV-BEGIN---");
    spi_bench_header();
    unsigned failures = 0;
    for (unsigned p = 0; p < SPI_BENCH_PAYLOAD_COUNT; ++p) {
        unsigned n = spi_bench_payloads[p];
        SpiBenchResult r = spi_bench_result();
        long timeouts = 0; /* only ioctl errors explicitly reported as ETIMEDOUT */
        struct rusage ru0, ru1;
        uint64_t c0 = 0, c1 = 0, w0 = 0, w1 = 0;
        int ru_ok = getrusage(RUSAGE_SELF, &ru0) == 0;
        int cpu_ok = now_ns(CLOCK_THREAD_CPUTIME_ID, &c0) == 0;
        int wall_ok = now_ns(CLOCK_MONOTONIC_RAW, &w0) == 0;
        for (unsigned t = 0; t < SPI_BENCH_ATTEMPTS; ++t) {
            spi_bench_prepare(tx, rx, n);
            struct spi_ioc_transfer tr = {
                .tx_buf = (uintptr_t)tx, .rx_buf = (uintptr_t)rx, .len = n,
                .speed_hz = speed, .bits_per_word = 8, .cs_change = 0,
            };
            uint64_t start = 0, end = 0;
            ++r.attempts;
            int start_ok = now_ns(CLOCK_MONOTONIC_RAW, &start) == 0;
            int rc = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
            int saved_errno = errno;
            int end_ok = now_ns(CLOCK_MONOTONIC_RAW, &end) == 0;
            if (rc < 0) {
                ++r.api_errors;
                if (saved_errno == ETIMEDOUT) ++timeouts;
                spi_bench_failure(&r, -saved_errno, "ioctl_errno", t);
                continue;
            }
            if ((unsigned)rc != n) {
                ++r.api_errors;
                ++r.short_returns;
                spi_bench_failure(&r, SPI_BENCH_SHORT_TRANSFER, "nonfull_return", t);
                printf("# nonfull_return payload=%u trial=%u rc=%d expected=%u\n", n, t, rc, n);
                continue;
            }
            ++r.api_success;
            int valid_rx = spi_bench_verify(&r, tx, rx, n, t);
            if (!start_ok || !end_ok || end < start) {
                ++r.timer_errors;
                spi_bench_failure(&r, SPI_BENCH_TIMER_ERROR, "timer", t);
            } else if (valid_rx) spi_bench_sample(&r, (double)(end - start));
        }
        wall_ok = (now_ns(CLOCK_MONOTONIC_RAW, &w1) == 0) && wall_ok;
        cpu_ok = (now_ns(CLOCK_THREAD_CPUTIME_ID, &c1) == 0) && cpu_ok;
        ru_ok = (getrusage(RUSAGE_SELF, &ru1) == 0) && ru_ok;
        spi_bench_row(n, &r, timeouts);
        printf("# loop_metrics payload_bytes=%u cpu_ns=%.0f wall_ns=%.0f nvcsw=%ld nivcsw=%ld\n",
               n, cpu_ok && c1 >= c0 ? (double)(c1 - c0) : -1.0,
               wall_ok && w1 >= w0 ? (double)(w1 - w0) : -1.0,
               ru_ok ? ru1.ru_nvcsw - ru0.ru_nvcsw : -1L,
               ru_ok ? ru1.ru_nivcsw - ru0.ru_nivcsw : -1L);
        failures += r.api_errors + r.mismatches + r.timer_errors;
    }
    puts("---CSV-END---");
    puts("# timeout_count=reported_ETIMEDOUT_subset_of_api_error_count_not_a_deadline_guarantee");
    printf("# sweep_complete=1 failures=%u topology=UNVERIFIED\n", failures);
    close(fd);
    return failures ? 1 : 0;
}

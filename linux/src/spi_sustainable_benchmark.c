/*
 * MSU-2 Task 2e sustained SPI loopback measurement.
 * Run exactly one payload and one repetition per invocation so a failed point
 * is preserved independently and can be diagnosed before another attempt.
 * Throughput includes pattern preparation and RX verification in the measured
 * wall window. The per-transfer maximum covers only the SPI ioctl interval.
 */
#define _GNU_SOURCE
#include "../../common/spi_benchmark_contract.h"
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/spi/spidev.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

static uint8_t tx[SPI_BENCH_MAX_PAYLOAD];
static uint8_t rx[SPI_BENCH_MAX_PAYLOAD];

static int clock_ns(clockid_t id, uint64_t *out)
{
    struct timespec ts;
    if (clock_gettime(id, &ts) != 0) return -1;
    *out = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
    return 0;
}

static int parse_uint(const char *s, unsigned long min, unsigned long max,
                      unsigned long *value)
{
    char *end = NULL;
    errno = 0;
    unsigned long n = strtoul(s, &end, 10);
    if (errno || end == s || *end || n < min || n > max) return -1;
    *value = n;
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 5) {
        fprintf(stderr, "usage: %s DEVICE PAYLOAD_BYTES [WINDOW_SECONDS [REQUESTED_SCK_HZ]]\n", argv[0]);
        return 2;
    }
    unsigned long payload_ul, window_s_ul = 60, speed_ul = 15623438;
    if (parse_uint(argv[2], 1, SPI_BENCH_MAX_PAYLOAD, &payload_ul) != 0) return 2;
    int supported = 0;
    for (unsigned i = 0; i < SPI_BENCH_PAYLOAD_COUNT; ++i)
        if (payload_ul == spi_bench_payloads[i]) supported = 1;
    if (!supported) {
        fprintf(stderr, "payload must be one of the shared contract sizes\n");
        return 2;
    }
    if (argc >= 4 && parse_uint(argv[3], 1, 3600, &window_s_ul) != 0) return 2;
    if (argc >= 5 && parse_uint(argv[4], 1, UINT32_MAX, &speed_ul) != 0) return 2;
    unsigned payload = (unsigned)payload_ul;
    uint64_t window_ns = (uint64_t)window_s_ul * 1000000000ULL;
    uint32_t speed = (uint32_t)speed_ul;

    int fd = open(argv[1], O_RDWR);
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
        fprintf(stderr, "SPI readback mismatch: mode=0x%x bits=%u\n", mode_rb, bits_rb);
        close(fd); return 2;
    }

    uint64_t wall_start, wall_end, cpu_start, cpu_end;
    uint64_t successes = 0, bytes_ok = 0, errors = 0, mismatches = 0;
    uint64_t max_ioctl_ns = 0;
    int64_t first_error = 0;
    if (clock_ns(CLOCK_MONOTONIC_RAW, &wall_start) ||
        clock_ns(CLOCK_THREAD_CPUTIME_ID, &cpu_start)) {
        perror("clock_gettime"); close(fd); return 2;
    }
    wall_end = wall_start;
    while (wall_end - wall_start < window_ns) {
        spi_bench_prepare(tx, rx, payload);
        struct spi_ioc_transfer tr = {
            .tx_buf = (uintptr_t)tx, .rx_buf = (uintptr_t)rx,
            .len = payload, .speed_hz = speed, .bits_per_word = 8,
            .cs_change = 0,
        };
        uint64_t t0, t1;
        if (clock_ns(CLOCK_MONOTONIC_RAW, &t0) != 0) { ++errors; first_error = SPI_BENCH_TIMER_ERROR; break; }
        int rc = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
        int saved_errno = errno;
        if (clock_ns(CLOCK_MONOTONIC_RAW, &t1) != 0 || t1 < t0) {
            ++errors; first_error = SPI_BENCH_TIMER_ERROR; break;
        }
        wall_end = t1;
        uint64_t elapsed = t1 - t0;
        if (elapsed > max_ioctl_ns) max_ioctl_ns = elapsed;
        if (rc < 0) {
            ++errors; first_error = saved_errno ? saved_errno : EIO; break;
        }
        if ((unsigned)rc != payload) {
            ++errors; first_error = SPI_BENCH_SHORT_TRANSFER; break;
        }
        ++successes;
        if (!spi_bench_verify(&(SpiBenchResult){0}, tx, rx, payload, (unsigned)successes - 1)) {
            ++mismatches; first_error = SPI_BENCH_RX_MISMATCH; break;
        }
        bytes_ok += payload;
        if (clock_ns(CLOCK_MONOTONIC_RAW, &wall_end) != 0 || wall_end < wall_start) {
            ++errors; first_error = SPI_BENCH_TIMER_ERROR; break;
        }
    }
    if (clock_ns(CLOCK_MONOTONIC_RAW, &wall_end) != 0 || wall_end < wall_start ||
        clock_ns(CLOCK_THREAD_CPUTIME_ID, &cpu_end) != 0 || cpu_end < cpu_start) {
        ++errors; first_error = SPI_BENCH_TIMER_ERROR;
        wall_end = wall_start;
        cpu_end = cpu_start;
    }
    close(fd);
    double actual_s = (double)(wall_end - wall_start) / 1e9;
    double cpu_s = (double)(cpu_end - cpu_start) / 1e9;
    double mb_s = actual_s > 0 ? (double)bytes_ok / actual_s / 1e6 : 0.0;
    double cpu_share = actual_s > 0 ? 100.0 * cpu_s / actual_s : 0.0;
    printf("# device=%s mode=0 bits=%u speed_requested_hz=%u speed_readback_hz=%u physical_sck_hz=NOT_MEASURED\n",
           argv[1], bits_rb, speed, speed_rb);
    printf("# timer=CLOCK_MONOTONIC_RAW cpu_timer=CLOCK_THREAD_CPUTIME_ID window_target_s=%lu\n", window_s_ul);
    puts("payload_bytes,window_s,attempts,verified_transfers,verified_bytes,application_MBps,thread_cpu_s,thread_cpu_share_pct,max_ioctl_us,api_errors,mismatches,first_error_code");
    printf("%u,%.9f,%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%.9f,%.9f,%.6f,%.3f,%" PRIu64 ",%" PRIu64 ",%" PRId64 "\n",
           payload, actual_s, successes + errors, successes, bytes_ok, mb_s,
           cpu_s, cpu_share, (double)max_ioctl_ns / 1000.0, errors, mismatches, first_error);
    return errors || mismatches || actual_s < (double)window_s_ul * 0.99 ? 1 : 0;
}

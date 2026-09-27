/* Shared experiment contract. No controller or operating-system code here. */
#ifndef SPI_BENCHMARK_CONTRACT_H
#define SPI_BENCHMARK_CONTRACT_H

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define SPI_BENCH_ATTEMPTS 1000U
#define SPI_BENCH_MAX_PAYLOAD 65536U
static const unsigned spi_bench_payloads[] = {
    1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384, 65536
};
#define SPI_BENCH_PAYLOAD_COUNT \
    (sizeof(spi_bench_payloads) / sizeof(spi_bench_payloads[0]))

/* Negative harness statuses cannot be confused with positive Xilinx statuses.
 * Linux syscall errors use -errno in first_status; first_failure_kind disambiguates.
 */
#define SPI_BENCH_RX_MISMATCH (-10001)
#define SPI_BENCH_SHORT_TRANSFER (-10002)
#define SPI_BENCH_TIMER_ERROR (-10003)
#define SPI_BENCH_TIMEOUT (-10004)

typedef struct {
    unsigned attempts, api_success, api_errors, short_returns, mismatches;
    unsigned timer_errors, samples;
    int first_status;
    const char *first_kind;
    int first_trial, first_mismatch_trial, first_mismatch_offset;
    int first_expected, first_actual;
    double minimum, maximum, mean, m2;
} SpiBenchResult;

static inline SpiBenchResult spi_bench_result(void)
{
    SpiBenchResult r = {0};
    r.first_kind = "none";
    r.first_trial = r.first_mismatch_trial = r.first_mismatch_offset = -1;
    r.first_expected = r.first_actual = -1;
    return r;
}

static inline void spi_bench_failure(SpiBenchResult *r, int status,
                                     const char *kind, unsigned trial)
{
    if (r->first_trial < 0) {
        r->first_status = status;
        r->first_kind = kind;
        r->first_trial = (int)trial;
    }
}

static inline void spi_bench_prepare(uint8_t *tx, uint8_t *rx, unsigned n)
{
    for (unsigned i = 0; i < n; ++i) {
        tx[i] = (uint8_t)(i & 0xffU);
        /* Every byte differs from its expected value, including payload 1. */
        rx[i] = (uint8_t)(tx[i] ^ 0xffU);
    }
}

static inline int spi_bench_verify(SpiBenchResult *r, const uint8_t *tx,
                                    const uint8_t *rx, unsigned n, unsigned trial)
{
    int first = -1;
    for (unsigned i = 0; i < n; ++i)
        if (rx[i] != tx[i] && first < 0) first = (int)i;
    if (first < 0) return 1;
    ++r->mismatches;
    if (r->first_mismatch_trial < 0) {
        r->first_mismatch_trial = (int)trial;
        r->first_mismatch_offset = first;
        r->first_expected = tx[first];
        r->first_actual = rx[first];
    }
    spi_bench_failure(r, SPI_BENCH_RX_MISMATCH, "rx_mismatch", trial);
    return 0;
}

/* Welford population variance avoids integer squared-deviation overflow. */
static inline void spi_bench_sample(SpiBenchResult *r, double ns)
{
    if (r->samples == 0 || ns < r->minimum) r->minimum = ns;
    if (r->samples == 0 || ns > r->maximum) r->maximum = ns;
    ++r->samples;
    double delta = ns - r->mean;
    r->mean += delta / r->samples;
    r->m2 += delta * (ns - r->mean);
}

static inline void spi_bench_header(void)
{
    puts("payload_bytes,attempt_count,timed_success_count,api_success_count,"
         "api_error_count,timeout_count,rx_mismatch_count,first_status,"
         "min_ns,avg_ns,max_ns,stddev_ns,short_return_count,timer_error_count,"
         "first_failure_kind,first_failure_trial,first_mismatch_trial,"
         "first_mismatch_offset,first_expected,first_actual");
}

static inline void spi_bench_row(unsigned bytes, const SpiBenchResult *r,
                                 long timeout_count)
{
    double sd = r->samples ? sqrt(fmax(0.0, r->m2 / r->samples)) : -1.0;
    printf("%u,%u,%u,%u,%u,%ld,%u,%d,%.3f,%.3f,%.3f,%.3f,%u,%u,%s,%d,%d,%d,%d,%d\n",
           bytes, r->attempts, r->samples, r->api_success, r->api_errors,
           timeout_count, r->mismatches, r->first_status,
           r->samples ? r->minimum : -1.0, r->samples ? r->mean : -1.0,
           r->samples ? r->maximum : -1.0, sd, r->short_returns, r->timer_errors,
           r->first_kind, r->first_trial, r->first_mismatch_trial,
           r->first_mismatch_offset, r->first_expected, r->first_actual);
}
#endif

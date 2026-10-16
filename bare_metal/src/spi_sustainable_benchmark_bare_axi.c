/*
 * MSU-2 Task 2e sustained AXI Quad SPI loopback test.
 * Build against the existing Vitis 2025.1 SDT AXI SPI platform. This program
 * runs 3 repetitions of each shared-contract payload, 60 seconds per point.
 * The application deliberately stops on the first transfer or RX failure.
 */
#include "spi_benchmark_contract.h"
#include "xparameters.h"
#include "xspi.h"
#include "xinterrupt_wrap.h"
#include "xil_exception.h"
#include "xiltimer.h"
#include "xtimer_config.h"
#include "xil_io.h"
#include <inttypes.h>

#ifndef SDT
#error "This application requires the validated Vitis SDT platform"
#endif
#if !defined(XPAR_XSPI_0_BASEADDR) || XPAR_XSPI_0_BASEADDR != 0xA0000000
#error "Expected AXI Quad SPI at 0xA0000000"
#endif
#if !defined(XPAR_FABRIC_XSPI_0_INTR) || XPAR_FABRIC_XSPI_0_INTR != 89
#error "Expected validated AXI Quad SPI interrupt ID"
#endif

#ifndef SPI_SUSTAIN_WINDOW_SECONDS
#define SPI_SUSTAIN_WINDOW_SECONDS 60U
#endif
#ifndef SPI_SUSTAIN_REPETITIONS
#define SPI_SUSTAIN_REPETITIONS 3U
#endif
#define SPI_AXI_TRANSFER_TIMEOUT_MS 2000U

static XSpi spi;
static uint8_t tx[SPI_BENCH_MAX_PAYLOAD], rx[SPI_BENCH_MAX_PAYLOAD];
typedef struct { volatile unsigned terminal; volatile u32 event; volatile unsigned bytes; } SpiIrqState;
static SpiIrqState irq_state;

static uint64_t ticks(void)
{
    XTime t;
    XTime_GetTime(&t);
    return (uint64_t)t;
}

static void spi_status_handler(void *ref, u32 event, unsigned byte_count)
{
    SpiIrqState *state = (SpiIrqState *)ref;
    state->event = event;
    state->bytes = byte_count;
    state->terminal = 1U;
}

static int configure_spi(void)
{
    int s = XSpi_SetOptions(&spi, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION);
    if (s != XST_SUCCESS) return s;
    s = XSpi_SetSlaveSelect(&spi, 1U);
    if (s != XST_SUCCESS) return s;
    XSpi_SetStatusHandler(&spi, &irq_state, spi_status_handler);
    s = XSpi_Start(&spi);
    if (s != XST_SUCCESS) return s;
    XSpi_IntrGlobalEnable(&spi);
    return XST_SUCCESS;
}

static int initialize(void)
{
    XSpi_Config *cfg = XSpi_LookupConfig(XPAR_XSPI_0_BASEADDR);
    if (!cfg || cfg->BaseAddress != 0xA0000000U || cfg->SlaveOnly ||
        cfg->SpiMode != 0 || cfg->DataWidth != 8 || cfg->NumSlaveBits != 1 ||
        cfg->AxiInterface != 0 || cfg->XipMode || !cfg->HasFifos || cfg->FifosDepth != 256)
        return XST_FAILURE;
    int s = XSpi_CfgInitialize(&spi, cfg, cfg->BaseAddress);
    if (s != XST_SUCCESS) return s;
    s = XSpi_SelfTest(&spi);
    if (s != XST_SUCCESS) return s;
    s = XSetupInterruptSystem(&spi, &XSpi_InterruptHandler,
                              cfg->IntrId, cfg->IntrParent,
                              XINTERRUPT_DEFAULT_PRIORITY);
    if (s != XST_SUCCESS) return s;
    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;
    return configure_spi();
}

static int transfer_bounded(unsigned n, uint64_t *start, uint64_t *end,
                            u32 *event, unsigned *bytes)
{
    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;
    *start = ticks();
    int s = XSpi_Transfer(&spi, tx, rx, n);
    if (s != XST_SUCCESS) { *end = ticks(); return s; }
    const uint64_t limit = ((uint64_t)COUNTS_PER_SECOND * SPI_AXI_TRANSFER_TIMEOUT_MS) / 1000U;
    while (!irq_state.terminal) {
        uint64_t now = ticks();
        if (now - *start >= limit) { *end = now; return SPI_BENCH_TIMEOUT; }
    }
    *end = ticks();
    *event = irq_state.event;
    *bytes = irq_state.bytes;
    return XST_SUCCESS;
}

static void output_record(unsigned repetition, unsigned payload, uint64_t start,
                          uint64_t end, uint64_t attempts, uint64_t verified,
                          uint64_t errors, uint64_t mismatches, int64_t first_error,
                          uint64_t max_transfer_ticks)
{
    double elapsed = end >= start ? (double)(end - start) / (double)COUNTS_PER_SECOND : 0.0;
    double rate = elapsed > 0.0 ? (double)(verified * payload) / elapsed / 1e6 : 0.0;
    double max_us = (double)max_transfer_ticks * 1e6 / (double)COUNTS_PER_SECOND;
    printf("%u,%u,%.9f,%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%.9f,busy_wait_core_occupancy,100.0,-1,-1,100.0,%.3f,%" PRIu64 ",%" PRIu64 ",%" PRId64 "\n",
           repetition, payload, elapsed, attempts, verified, verified * payload,
           rate, max_us, errors, mismatches, first_error);
}

int main(void)
{
    puts("# MSU-2 AXI sustained benchmark; hardware_validation=NOT_PERFORMED");
    puts("# controller=axi_quad_spi_0 base=0xa0000000 driver=XSpi mode=0 bits=8 chip_select=0");
    puts("# topology=UNVERIFIED intended_topology=external_MOSI_to_MISO physical_sck_hz=NOT_MEASURED");
    puts("# timer=XTime_GetTime frequency_source=BSP_COUNTS_PER_SECOND");
    printf("# timer_hz=%lu window_target_s=%u repetitions=%u cpu_metric=bm_busy_wait_core_occupancy_not_PMU\n",
           (unsigned long)COUNTS_PER_SECOND, SPI_SUSTAIN_WINDOW_SECONDS, SPI_SUSTAIN_REPETITIONS);
    if (COUNTS_PER_SECOND == 0 || SPI_SUSTAIN_WINDOW_SECONDS == 0 || SPI_SUSTAIN_REPETITIONS == 0) return 3;
    printf("# IOPLL_CTRL=0x%08x PL0_REF_CTRL=0x%08x\n",
           (unsigned)Xil_In32(0xFF5E0020U), (unsigned)Xil_In32(0xFF5E00C0U));
    int status = initialize();
    if (status != XST_SUCCESS) { printf("# initialization_failed status=%d\n", status); return 4; }
    puts("repetition,payload_bytes,window_s,attempts,verified_transfers,verified_bytes,application_MBps,cpu_metric_kind,cpu_metric_pct,thread_cpu_s,thread_cpu_share_pct,busy_wait_core_occupancy_pct,max_transfer_us,api_errors,mismatches,first_error_code");

    uint64_t window_ticks = (uint64_t)SPI_SUSTAIN_WINDOW_SECONDS * (uint64_t)COUNTS_PER_SECOND;
    for (unsigned repetition = 1; repetition <= SPI_SUSTAIN_REPETITIONS; ++repetition) {
        for (unsigned p = 0; p < SPI_BENCH_PAYLOAD_COUNT; ++p) {
            unsigned n = spi_bench_payloads[p];
            uint64_t start = ticks(), end = start, attempts = 0, verified = 0;
            uint64_t errors = 0, mismatches = 0, max_transfer_ticks = 0;
            int64_t first_error = 0;
            while (end - start < window_ticks) {
                spi_bench_prepare(tx, rx, n);
                uint64_t tx_start = 0, tx_end = 0;
                u32 event = 0;
                unsigned completed_bytes = 0;
                ++attempts;
                status = transfer_bounded(n, &tx_start, &tx_end, &event, &completed_bytes);
                if (tx_end >= tx_start && tx_end - tx_start > max_transfer_ticks)
                    max_transfer_ticks = tx_end - tx_start;
                if (status != XST_SUCCESS) { ++errors; first_error = status; end = ticks(); break; }
                if (event != XST_SPI_TRANSFER_DONE) { ++errors; first_error = event; end = ticks(); break; }
                if (completed_bytes != n) { ++errors; first_error = SPI_BENCH_SHORT_TRANSFER; end = ticks(); break; }
                if (!spi_bench_verify(&(SpiBenchResult){0}, tx, rx, n, (unsigned)attempts - 1U)) {
                    ++mismatches; first_error = SPI_BENCH_RX_MISMATCH; end = ticks(); break;
                }
                ++verified;
                end = ticks();
                if (end < start) { ++errors; first_error = SPI_BENCH_TIMER_ERROR; break; }
            }
            if (end < start) { end = start; ++errors; first_error = SPI_BENCH_TIMER_ERROR; }
            output_record(repetition, n, start, end, attempts, verified, errors,
                          mismatches, first_error, max_transfer_ticks);
            if (errors || mismatches || (double)(end-start)/(double)COUNTS_PER_SECOND < (double)SPI_SUSTAIN_WINDOW_SECONDS * 0.99) {
                printf("# point_failed repetition=%u payload_bytes=%u; stopping without retry\n", repetition, n);
                XSpi_IntrGlobalDisable(&spi);
                XDisableIntrId(XPAR_XSPI_0_INTERRUPTS, XPAR_XSPI_0_INTERRUPT_PARENT);
                XSpi_Stop(&spi);
                return 1;
            }
        }
    }
    XSpi_IntrGlobalDisable(&spi);
    XDisableIntrId(XPAR_XSPI_0_INTERRUPTS, XPAR_XSPI_0_INTERRUPT_PARENT);
    XDisconnectInterruptCntrl(XPAR_XSPI_0_INTERRUPTS, XPAR_XSPI_0_INTERRUPT_PARENT);
    XSpi_Stop(&spi);
    puts("# sustained_sweep_complete=1 topology=UNVERIFIED");
    return 0;
}

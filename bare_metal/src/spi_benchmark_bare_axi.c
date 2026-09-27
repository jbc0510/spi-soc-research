/* MSU-2 Task 2: AXI Quad SPI only. Phase 1 software; NOT board validated. */
#include "spi_benchmark_contract.h"
#include "xparameters.h"
#include "xspi.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "xiltimer.h"
#include "xtimer_config.h"
#include "xil_io.h"

#ifndef SDT
#error "This application requires the pinned Vitis 2025.1 SDT platform"
#endif
#ifndef XPAR_XSPI_0_BASEADDR
#error "Generated BSP must contain AXI Quad SPI / XSpi"
#endif
#if XPAR_XSPI_0_BASEADDR != 0xA0000000
#error "Unexpected XSpi base address"
#endif
#ifndef XPAR_XSCUGIC_0_BASEADDR
#error "Generated BSP must contain the ZynqMP GIC"
#endif
#ifndef XPAR_FABRIC_XSPI_0_INTR
#error "Generated BSP must contain the AXI Quad SPI interrupt"
#endif
#if XPAR_FABRIC_XSPI_0_INTR != 89
#error "Unexpected AXI Quad SPI interrupt ID"
#endif

#define SPI_AXI_TRANSFER_TIMEOUT_MS 2000U

static XSpi spi;
static XScuGic gic;
static uint8_t tx[SPI_BENCH_MAX_PAYLOAD], rx[SPI_BENCH_MAX_PAYLOAD];
SpiBenchResult axi_results[SPI_BENCH_PAYLOAD_COUNT];
volatile uint32_t axi_done;

typedef struct {
    volatile unsigned terminal;
    volatile u32 event;
    volatile unsigned bytes;
} SpiIrqState;

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
    if (event == XST_SPI_TRANSFER_DONE) {
        state->event = event;
        state->bytes = byte_count;
        state->terminal = 1U;
        return;
    }

    /* Any reported SPI error/event other than successful completion is
     * terminal for this benchmark attempt. Recovery occurs at task level. */
    state->event = event;
    state->bytes = byte_count;
    state->terminal = 1U;
}

static int configure_spi_after_reset(void)
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

static int recover_spi(void)
{
    /*
     * Mask the GIC source before resetting driver/controller state so a pending
     * SPI interrupt cannot race recovery. Re-enable only after restart succeeds.
     */
    XScuGic_Disable(&gic, XPAR_FABRIC_XSPI_0_INTR);
    XSpi_IntrGlobalDisable(&spi);
    XSpi_Reset(&spi);

    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;

    int s = configure_spi_after_reset();
    if (s != XST_SUCCESS) return s;

    XScuGic_Enable(&gic, XPAR_FABRIC_XSPI_0_INTR);
    return XST_SUCCESS;
}

static int initialize(void)
{
    XSpi_Config *cfg = XSpi_LookupConfig(XPAR_XSPI_0_BASEADDR);
    if (!cfg || cfg->BaseAddress != 0xA0000000U || cfg->SlaveOnly ||
        cfg->SpiMode != 0 || cfg->DataWidth != 8 || cfg->NumSlaveBits != 1 ||
        cfg->AxiInterface != 0 || cfg->XipMode || !cfg->HasFifos ||
        cfg->FifosDepth != 256) return XST_FAILURE;

    int s = XSpi_CfgInitialize(&spi, cfg, cfg->BaseAddress);
    if (s != XST_SUCCESS) return s;

    s = XSpi_SelfTest(&spi);
    if (s != XST_SUCCESS) return s;

    XScuGic_Config *gcfg = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (!gcfg) return XST_FAILURE;

    s = XScuGic_CfgInitialize(&gic, gcfg, (u32)gcfg->CpuBaseAddress);
    if (s != XST_SUCCESS) return s;

    s = XScuGic_Connect(&gic, XPAR_FABRIC_XSPI_0_INTR,
                        (Xil_InterruptHandler)XSpi_InterruptHandler, &spi);
    if (s != XST_SUCCESS) return s;

    XScuGic_Enable(&gic, XPAR_FABRIC_XSPI_0_INTR);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 &gic);
    Xil_ExceptionEnable();

    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;

    return configure_spi_after_reset();
}

static int transfer_bounded(unsigned n, uint64_t *start, uint64_t *end,
                            u32 *event, unsigned *bytes)
{
    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;

    *start = ticks();
    int s = XSpi_Transfer(&spi, tx, rx, n);
    if (s != XST_SUCCESS) {
        *end = ticks();
        return s;
    }

    const uint64_t timeout_ticks =
        ((uint64_t)COUNTS_PER_SECOND * SPI_AXI_TRANSFER_TIMEOUT_MS) / 1000U;

    while (!irq_state.terminal) {
        uint64_t now = ticks();
        if ((now - *start) >= timeout_ticks) {
            *end = now;
            return SPI_BENCH_TIMEOUT;
        }
    }

    *end = ticks();
    *event = irq_state.event;
    *bytes = irq_state.bytes;
    return XST_SUCCESS;
}

int main(void)
{
    puts("# MSU-2 AXI standalone Phase 1; hardware_validation=NOT_PERFORMED");
    puts("# controller=axi_quad_spi_0 base=0xa0000000 driver=XSpi mode=0 bits=8 ss=0");
    puts("# topology=UNVERIFIED intended_topology=external_MOSI_to_MISO");
    puts("# clock_pair=UNRECONCILED sck_physical_hz=UNKNOWN");
    puts("# timer=XTime_GetTime frequency_source=BSP_COUNTS_PER_SECOND");
    printf("# timer_hz=%llu\n", (unsigned long long)COUNTS_PER_SECOND);
    puts("# samples=API_success_AND_RX_verified_AND_valid_timer population_stddev=1");
    printf("# timeout_handling=bounded_interrupt deadline_ms=%u recovery=XSpi_Reset_reconfigure timeout_count=measured\n",
           SPI_AXI_TRANSFER_TIMEOUT_MS);
    puts("# trial_indices=zero_based invalid_timing=-1_ns");
    if (COUNTS_PER_SECOND == 0) return 3;
    /* Observations only: no PS clock writes, no inferred physical frequency. */
    printf("# IOPLL_CTRL=0x%08x PL0_REF_CTRL=0x%08x\n",
           (unsigned)Xil_In32(0xFF5E0020U), (unsigned)Xil_In32(0xFF5E00C0U));
    int status = initialize();
    if (status != XST_SUCCESS) {
        printf("# initialization_failed status=%d\n", status);
        return 4;
    }
    printf("# control_readback=0x%08x\n", (unsigned)XSpi_GetControlReg(&spi));
    puts("---CSV-BEGIN---");
    spi_bench_header();
    unsigned failures = 0;
    for (unsigned p = 0; p < SPI_BENCH_PAYLOAD_COUNT; ++p) {
        unsigned n = spi_bench_payloads[p];
        SpiBenchResult *r = &axi_results[p];
        *r = spi_bench_result();
        long timeout_count = 0;
        for (unsigned t = 0; t < SPI_BENCH_ATTEMPTS; ++t) {
            spi_bench_prepare(tx, rx, n);
            ++r->attempts;
            uint64_t start = 0, end = 0;
            u32 event = 0;
            unsigned completed_bytes = 0;
            status = transfer_bounded(n, &start, &end, &event, &completed_bytes);
            if (status == SPI_BENCH_TIMEOUT) {
                ++r->api_errors;
                ++timeout_count;
                spi_bench_failure(r, SPI_BENCH_TIMEOUT, "timeout", t);
                if (recover_spi() != XST_SUCCESS) {
                    puts("# FATAL: SPI recovery failed after timeout");
                    return 3;
                }
                continue;
            }
            if (status != XST_SUCCESS) {
                ++r->api_errors;
                spi_bench_failure(r, status, "driver", t);
                if (recover_spi() != XST_SUCCESS) {
                    puts("# FATAL: SPI recovery failed after transfer-start error");
                    return 3;
                }
                continue;
            }
            if (event != XST_SPI_TRANSFER_DONE) {
                ++r->api_errors;
                spi_bench_failure(r, (int)event, "irq_event", t);
                if (recover_spi() != XST_SUCCESS) {
                    puts("# FATAL: SPI recovery failed after interrupt error");
                    return 3;
                }
                continue;
            }
            if (completed_bytes != n) {
                ++r->api_errors;
                ++r->short_returns;
                spi_bench_failure(r, SPI_BENCH_SHORT_TRANSFER, "short_transfer", t);
                if (recover_spi() != XST_SUCCESS) {
                    puts("# FATAL: SPI recovery failed after short transfer");
                    return 3;
                }
                continue;
            }
            ++r->api_success;
            int valid_rx = spi_bench_verify(r, tx, rx, n, t);
            if (end < start) {
                ++r->timer_errors;
                spi_bench_failure(r, SPI_BENCH_TIMER_ERROR, "timer", t);
            } else if (valid_rx) {
                spi_bench_sample(r, (double)(end - start) * 1e9 /
                                   (double)COUNTS_PER_SECOND);
            }
        }
        /* Timeout count is measured by the bounded interrupt wait path. */
        spi_bench_row(n, r, timeout_count);
        failures += r->api_errors + r->mismatches + r->timer_errors;
    }
    puts("---CSV-END---");
    XSpi_IntrGlobalDisable(&spi);
    XScuGic_Disable(&gic, XPAR_FABRIC_XSPI_0_INTR);
    XScuGic_Disconnect(&gic, XPAR_FABRIC_XSPI_0_INTR);
    XSpi_Stop(&spi);
    axi_done = failures ? 2U : 1U; /* completion, never topology certification */
    __asm__ volatile ("dsb sy" ::: "memory");
    printf("# sweep_complete=1 failures=%u topology=UNVERIFIED\n", failures);
    return failures ? 1 : 0;
}

/* MSU-2 Task 2: AXI Quad SPI only. Phase 1 software; NOT board validated. */
#include "spi_benchmark_contract.h"
#include "xparameters.h"
#include "xspi.h"
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
#ifndef SPI_AXI_ALLOW_UNBOUNDED_POLLING
#define SPI_AXI_ALLOW_UNBOUNDED_POLLING 0
#endif

static XSpi spi;
static uint8_t tx[SPI_BENCH_MAX_PAYLOAD], rx[SPI_BENCH_MAX_PAYLOAD];
/* New symbols/ABI; never reuse the historical PS benchmark's result layout. */
SpiBenchResult axi_results[SPI_BENCH_PAYLOAD_COUNT];
volatile uint32_t axi_done;
/* Retain/link the transfer path even in the default blocked ELF, so a default
 * build validates actual XSpi symbols. This is not a runtime arming API. */
static const volatile unsigned allow_unbounded = SPI_AXI_ALLOW_UNBOUNDED_POLLING;

static uint64_t ticks(void)
{
    XTime t;
    XTime_GetTime(&t);
    return (uint64_t)t;
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
    /* CPOL=0, CPHA=0, MSB first; local loopback deliberately disabled. */
    s = XSpi_SetOptions(&spi, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION);
    if (s != XST_SUCCESS) return s;
    s = XSpi_SetSlaveSelect(&spi, 1U); /* XSpi bitmask: bit 0 selects SS0. */
    if (s != XST_SUCCESS) return s;
    s = XSpi_Start(&spi);
    if (s != XST_SUCCESS) return s;
    XSpi_IntrGlobalDisable(&spi);
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
    puts("# timeout_handling=BLOCKER_UNBOUNDED_XSpi_Transfer timeout_count=-1_means_UNAVAILABLE");
    puts("# trial_indices=zero_based invalid_timing=-1_ns");
    if (!allow_unbounded) {
        puts("# BLOCKED: default build refuses transfers; bounded polling/recovery unresolved");
        return 2;
    }
    puts("# WARNING: explicit unbounded polling opt-in; a hung attempt prevents row/completion output");
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
        for (unsigned t = 0; t < SPI_BENCH_ATTEMPTS; ++t) {
            spi_bench_prepare(tx, rx, n);
            ++r->attempts;
            uint64_t start = ticks();
            /* BLOCKER: the vendor function itself has unbounded polling loops.
             * Do not add an outer deadline and claim it can interrupt this call. */
            status = XSpi_Transfer(&spi, tx, rx, n);
            uint64_t end = ticks();
            if (status != XST_SUCCESS) {
                ++r->api_errors;
                spi_bench_failure(r, status, "driver", t);
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
        /* A zero timeout count would falsely imply timeouts were monitored. */
        spi_bench_row(n, r, -1);
        failures += r->api_errors + r->mismatches + r->timer_errors;
    }
    puts("---CSV-END---");
    XSpi_Stop(&spi);
    axi_done = failures ? 2U : 1U; /* completion, never topology certification */
    __asm__ volatile ("dsb sy" ::: "memory");
    printf("# sweep_complete=1 failures=%u topology=UNVERIFIED\n", failures);
    return failures ? 1 : 0;
}

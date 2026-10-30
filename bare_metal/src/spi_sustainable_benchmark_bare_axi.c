/*
 * MSU-2 AXI Quad SPI bare-metal operator menu.
 * Build against the existing Vitis 2025.1 SDT AXI SPI platform. The operator
 * chooses RX-integrity/latency, configurable sustained, baseline, or smoke
 * mode over the shared payload contract. Long runs require explicit RUN.
 * Sustained mode stops on the first transfer or RX failure.
 */
#include "spi_benchmark_contract.h"
#include "xparameters.h"
#include "xspi.h"
#include "xinterrupt_wrap.h"
#include "xil_exception.h"
#include "xiltimer.h"
#include "xtimer_config.h"
#include "xil_io.h"
#include "xil_printf.h"
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

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

/*
 * One-shot Linux->bare-metal handoff entry. U-Boot launches this ELF with
 * `go <entry>`, which performs the complete EL2->EL1 switch (clean SCTLR_EL1,
 * migrated SP, VBAR, FP enabled) with the dcache disabled. We then install our
 * OWN flat identity MMU and jump straight to _startup, deliberately bypassing
 * the Xilinx boot.S / _boot MMU bring-up: that translation table only maps
 * correctly in the EL3 FSBL regime and faults the instant the MMU is enabled
 * at EL1 under U-Boot (validated on ZCU102 2026-10-29: enabling SCTLR_EL1.M
 * wedges the core before even the EL1 exception vector can fetch).
 *
 * Identity map, 4KB granule, 1GB L1 block descriptors (32-bit VA / TTBR0 only):
 *   0x00000000-0x7FFFFFFF  DDR            Normal write-back cacheable, AF, RW
 *   0x80000000-0xFFFFFFFF  PS/PL MMIO     Device-nGnRnE, AF, RW
 * (AXI Quad SPI @0xA0000000 and PS UART0 @0xFF000000 both fall in Device.)
 */
unsigned long long msu2_mmu_table[4]
    __attribute__((aligned(4096), used)) = {
    0x0000000000000705ULL, /* 0x00000000  DDR    Normal WB */
    0x0000000040000705ULL, /* 0x40000000  DDR    Normal WB */
    0x0000000080000401ULL, /* 0x80000000  Device */
    0x00000000C0000401ULL, /* 0xC0000000  Device */
};

__attribute__((naked, used, noreturn, section(".boot")))
void msu2_el2_entry(void)
{
    __asm__ volatile(
        /* `go` already dropped us to EL1; tolerate an EL2 entry just in case. */
        "mrs x0, CurrentEL\n"
        "and x0, x0, #0xc\n"
        "cmp x0, #0x8\n"
        "b.ne 1f\n"
        "mrs x0, hcr_el2\n"
        "orr x0, x0, #(1 << 31)\n"      /* HCR_EL2.RW: EL1 is AArch64 */
        "msr hcr_el2, x0\n"
        "mov x0, #0x3c5\n"              /* SPSR: EL1h, DAIF masked */
        "msr spsr_el2, x0\n"
        "adr x0, 1f\n"
        "msr elr_el2, x0\n"
        "isb\n"
        "eret\n"
        "1:\n"
        /* ---- at EL1, MMU off; set up our own identity translation ---- */
        "adrp x0, __el1_stack\n"
        "add  x0, x0, #:lo12:__el1_stack\n"
        "mov  sp, x0\n"
        "mov  x0, #0xff00\n"            /* MAIR: idx0 Device, idx1 Normal WB */
        "msr  mair_el1, x0\n"
        "movz x0, #0x3520\n"           /* TCR_EL1 = 0x0000000200803520 */
        "movk x0, #0x0080, lsl #16\n"  /*  T0SZ=32, WB/WA, inner-shareable, */
        "movk x0, #0x0002, lsl #32\n"  /*  4KB granule, EPD1, IPS=40-bit */
        "msr  tcr_el1, x0\n"
        "adrp x0, msu2_mmu_table\n"
        "add  x0, x0, #:lo12:msu2_mmu_table\n"
        "msr  ttbr0_el1, x0\n"
        "isb\n"
        "tlbi vmalle1\n"
        "ic   iallu\n"
        "dsb  sy\n"
        "isb\n"
        "adrp x0, _vector_table\n"
        "add  x0, x0, #:lo12:_vector_table\n"
        "msr  vbar_el1, x0\n"
        "mov  x0, #(3 << 20)\n"         /* CPACR_EL1.FPEN=11: FP/SIMD at EL1 */
        "msr  cpacr_el1, x0\n"
        "isb\n"
        "mrs  x0, sctlr_el1\n"          /* keep go's clean base + RES1 bits */
        "movz x1, #0x1005\n"            /* add SCTLR.M | C | I */
        "orr  x0, x0, x1\n"
        "msr  sctlr_el1, x0\n"
        "isb\n"
        "b    _startup\n");             /* BSS clear, libc init, PMCR, main */
}

static XSpi spi;
static uint8_t tx[SPI_BENCH_MAX_PAYLOAD], rx[SPI_BENCH_MAX_PAYLOAD];
typedef struct { volatile unsigned terminal; volatile u32 event; volatile unsigned bytes; } SpiIrqState;
static SpiIrqState irq_state;
static unsigned run_payloads[SPI_BENCH_PAYLOAD_COUNT];
static unsigned run_payload_count;
static unsigned run_window_seconds;
static unsigned run_repetitions;
static int run_integrity;

static void read_line(char *buffer, unsigned capacity)
{
    unsigned used = 0;
    while (used + 1U < capacity) {
        char c = inbyte();
        if (c == '\r' || c == '\n') {
            outbyte('\r');
            outbyte('\n');
            break;
        }
        if (c == '\b' || c == 0x7f) {
            if (used) {
                --used;
                outbyte('\b'); outbyte(' '); outbyte('\b');
            }
            continue;
        }
        buffer[used++] = c;
        outbyte(c);
    }
    buffer[used] = '\0';
}

static unsigned prompt_uint(const char *label, unsigned minimum,
                            unsigned maximum, unsigned default_value)
{
    char line[32];
    char *end;
    while (1) {
        xil_printf("%s [%u..%u, default %u]: ", label, minimum, maximum, default_value);
        read_line(line, sizeof(line));
        if (!line[0]) return default_value;
        unsigned long value = strtoul(line, &end, 10);
        if (end != line && *end == '\0' && value >= minimum && value <= maximum)
            return (unsigned)value;
        xil_printf("Invalid value. Enter a decimal number in range.\r\n");
    }
}

static int add_payload(unsigned value)
{
    for (unsigned i = 0; i < SPI_BENCH_PAYLOAD_COUNT; ++i) {
        if (spi_bench_payloads[i] != value) continue;
        for (unsigned j = 0; j < run_payload_count; ++j)
            if (run_payloads[j] == value) return 0;
        if (run_payload_count >= SPI_BENCH_PAYLOAD_COUNT) return 0;
        run_payloads[run_payload_count++] = value;
        return 1;
    }
    return 0;
}

static int prompt_payload_list(void)
{
    char line[160];
    xil_printf("Payload bytes (comma-separated shared sizes; blank=all): ");
    read_line(line, sizeof(line));
    char *write = line;
    for (char *read = line; *read; ++read)
        if (*read != ' ' && *read != '\t' && *read != '\r' && *read != '\n')
            *write++ = *read;
    *write = '\0';
    if (!line[0]) {
        for (unsigned i = 0; i < SPI_BENCH_PAYLOAD_COUNT; ++i)
            run_payloads[run_payload_count++] = spi_bench_payloads[i];
        return 1;
    }

    char *cursor = line;
    while (*cursor) {
        char *end;
        unsigned long value = strtoul(cursor, &end, 10);
        if (end == cursor || value > SPI_BENCH_MAX_PAYLOAD || !add_payload((unsigned)value))
            return 0;
        if (*end == '\0') break;
        if (*end != ',') return 0;
        cursor = end + 1;
        if (!*cursor) return 0;
    }
    return run_payload_count > 0;
}

static int select_run(void)
{
    xil_printf("\r\nMSU-2 AXI SPI bare-metal test menu\r\n");
    xil_printf("  1) RX integrity and latency: 11 payloads x 1,000 trials\r\n");
    xil_printf("  2) Sustained throughput: choose payloads, duration, repetitions\r\n");
    xil_printf("  3) Full sustained baseline: 11 payloads, 60 s x 3 repetitions\r\n");
    xil_printf("  4) One-byte smoke: 1 second\r\n");
    xil_printf("  q) Do not run a test\r\nSelect: ");
    char choice = inbyte();
    outbyte(choice); outbyte('\r'); outbyte('\n');
    run_payload_count = 0;
    run_integrity = 0;
    if (choice == 'q' || choice == 'Q') return 0;
    if (choice == '1') {
        run_integrity = 1;
        for (unsigned i = 0; i < SPI_BENCH_PAYLOAD_COUNT; ++i)
            run_payloads[run_payload_count++] = spi_bench_payloads[i];
        run_window_seconds = 0;
        run_repetitions = 1;
    } else if (choice == '2') {
        if (!prompt_payload_list()) {
            xil_printf("Invalid list. Use unique shared sizes: 1,8,16,64,128,256,512,1024,4096,16384,65536.\r\n");
            return -1;
        }
        run_window_seconds = prompt_uint("Seconds per payload", 1, 3600, 60);
        run_repetitions = prompt_uint("Repetitions", 1, 3, 3);
    } else if (choice == '3') {
        for (unsigned i = 0; i < SPI_BENCH_PAYLOAD_COUNT; ++i)
            run_payloads[run_payload_count++] = spi_bench_payloads[i];
        run_window_seconds = SPI_SUSTAIN_WINDOW_SECONDS;
        run_repetitions = SPI_SUSTAIN_REPETITIONS;
    } else if (choice == '4') {
        run_payloads[run_payload_count++] = 1U;
        run_window_seconds = 1;
        run_repetitions = 1;
    } else {
        xil_printf("Unknown selection; returning to menu.\r\n");
        return -1;
    }
    xil_printf("\r\nSelected payloads:");
    for (unsigned i = 0; i < run_payload_count; ++i)
        xil_printf(" %u", run_payloads[i]);
    if (run_integrity)
        xil_printf(" bytes; %u integrity trials per payload.\r\n", SPI_BENCH_ATTEMPTS);
    else
        xil_printf(" bytes; %u seconds per point; %u repetition(s).\r\n",
                   run_window_seconds, run_repetitions);
    xil_printf("Type RUN to begin; any other text cancels: ");
    char confirm[16];
    read_line(confirm, sizeof(confirm));
    if (strcmp(confirm, "RUN") != 0) {
        xil_printf("Cancelled; no transfers started.\r\n");
        return -1;
    }
    return 1;
}

static int configure_spi(void);

static int recover_spi(void)
{
    /* Polled mode (EL1 launch): no GIC interrupt id to disable/enable. */
    XSpi_IntrGlobalDisable(&spi);
    XSpi_Reset(&spi);
    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;
    return configure_spi();
}

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
    xil_printf("# init: selftest\r\n");
    s = XSpi_SelfTest(&spi);
    if (s != XST_SUCCESS) return s;
    /* Launched at EL1 non-secure from U-Boot: do NOT attach to the GIC.
     * transfer_bounded()/polled_transfer() drive the controller directly from
     * its status register, so no CPU interrupt is needed. XSetupInterruptSystem()
     * hangs at EL1 (the app cannot own the secure GIC, and unmasking storms on
     * Linux's leftover interrupts), so it is intentionally omitted here. */
    xil_printf("# init: polled mode (GIC attach skipped)\r\n");
    irq_state.terminal = 0U;
    irq_state.event = 0U;
    irq_state.bytes = 0U;
    return configure_spi();
}

/* Deterministic register-level polled full-duplex master transfer.
 * Launched from U-Boot we run at EL1 non-secure and cannot own the GIC, so the
 * interrupt-driven XSpi_Transfer path is unusable. This drives the AXI Quad SPI
 * directly: load TX FIFO, release the transaction, then drain the RX FIFO as
 * bytes arrive. CR bit0 (internal LOOPBACK) is left clear so RX is exercised
 * through the EXTERNAL physical MOSI->MISO loopback (hardware proof intact). */
static int polled_transfer(const uint8_t *txb, uint8_t *rxb, unsigned n)
{
    const u32 base = XPAR_XSPI_0_BASEADDR;
    const u32 cr_idle = XSP_CR_ENABLE_MASK | XSP_CR_MASTER_MODE_MASK |
                        XSP_CR_MANUAL_SS_MASK | XSP_CR_TRANS_INHIBIT_MASK;
    /* Inhibit transaction, reset both FIFOs, master/manual-SS, mode 0, no loopback. */
    XSpi_WriteReg(base, XSP_CR_OFFSET,
                  cr_idle | XSP_CR_TXFIFO_RESET_MASK | XSP_CR_RXFIFO_RESET_MASK);
    XSpi_WriteReg(base, XSP_SSR_OFFSET, 0xFFFFFFFFU);        /* deassert all SS */
    for (unsigned i = 0; i < n; ++i)
        XSpi_WriteReg(base, XSP_DTR_OFFSET, txb[i]);
    XSpi_WriteReg(base, XSP_SSR_OFFSET, ~0x1U);             /* select slave 0 (active low) */
    XSpi_WriteReg(base, XSP_CR_OFFSET, cr_idle & ~XSP_CR_TRANS_INHIBIT_MASK); /* run */
    const uint64_t limit = ((uint64_t)COUNTS_PER_SECOND * SPI_AXI_TRANSFER_TIMEOUT_MS) / 1000U;
    uint64_t t0 = ticks();
    unsigned r = 0;
    while (r < n) {
        if (!(XSpi_ReadReg(base, XSP_SR_OFFSET) & XSP_SR_RX_EMPTY_MASK))
            rxb[r++] = (uint8_t)XSpi_ReadReg(base, XSP_DRR_OFFSET);
        else if (ticks() - t0 >= limit)
            break;
    }
    XSpi_WriteReg(base, XSP_CR_OFFSET, cr_idle);            /* inhibit again */
    XSpi_WriteReg(base, XSP_SSR_OFFSET, 0xFFFFFFFFU);       /* deassert SS */
    return (r == n) ? (int)r : -1;
}

static int transfer_bounded(unsigned n, uint64_t *start, uint64_t *end,
                            u32 *event, unsigned *bytes)
{
    *start = ticks();
    int r = polled_transfer(tx, rx, n);
    *end = ticks();
    if (r < 0) { *bytes = 0; return SPI_BENCH_TIMEOUT; }
    *event = XST_SPI_TRANSFER_DONE;
    *bytes = (unsigned)r;
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

/* Run one operator-selected test, then return so main() redisplays the menu.
 * The machine-readable "# ..."/CSV lines are kept as evidence; a plain
 * human-readable summary is printed after each so the console is legible. */
static void run_test(void)
{
    puts(run_integrity ? "# MSU-2 AXI RX integrity sweep; hardware_validation=NOT_PERFORMED" :
                         "# MSU-2 AXI sustained benchmark; hardware_validation=NOT_PERFORMED");
    puts("# controller=axi_quad_spi_0 base=0xa0000000 driver=XSpi mode=0 bits=8 chip_select=0");
    puts("# topology=UNVERIFIED intended_topology=external_MOSI_to_MISO physical_sck_hz=NOT_MEASURED");
    puts("# timer=XTime_GetTime frequency_source=BSP_COUNTS_PER_SECOND");
    printf("# timer_hz=%lu integrity_trials=%u window_target_s=%u repetitions=%u cpu_metric=bm_busy_wait_core_occupancy_not_PMU\n",
           (unsigned long)COUNTS_PER_SECOND, SPI_BENCH_ATTEMPTS,
           run_window_seconds, run_repetitions);
    if (COUNTS_PER_SECOND == 0 || (!run_integrity &&
        (run_window_seconds == 0 || run_repetitions == 0))) return;
    printf("# IOPLL_CTRL=0x%08x PL0_REF_CTRL=0x%08x\n",
           (unsigned)Xil_In32(0xFF5E0020U), (unsigned)Xil_In32(0xFF5E00C0U));
    int status = initialize();
    if (status != XST_SUCCESS) {
        printf("# initialization_failed status=%d\n", status);
        xil_printf("SPI initialization failed (status %d).\r\n", status);
        return;
    }
    if (run_integrity) {
        puts("---CSV-BEGIN---");
        spi_bench_header();
        unsigned failures = 0;
        for (unsigned p = 0; p < run_payload_count; ++p) {
            unsigned n = run_payloads[p];
            SpiBenchResult result = spi_bench_result();
            long timeout_count = 0;
            for (unsigned trial = 0; trial < SPI_BENCH_ATTEMPTS; ++trial) {
                spi_bench_prepare(tx, rx, n);
                ++result.attempts;
                uint64_t start = 0, end = 0;
                u32 event = 0;
                unsigned completed_bytes = 0;
                status = transfer_bounded(n, &start, &end, &event, &completed_bytes);
                if (status == SPI_BENCH_TIMEOUT) {
                    ++result.api_errors; ++timeout_count;
                    spi_bench_failure(&result, status, "timeout", trial);
                    if (recover_spi() != XST_SUCCESS) { xil_printf("SPI recovery failed.\r\n"); return; }
                    continue;
                }
                if (status != XST_SUCCESS || event != XST_SPI_TRANSFER_DONE) {
                    ++result.api_errors;
                    spi_bench_failure(&result, status != XST_SUCCESS ? status : (int)event,
                                      status != XST_SUCCESS ? "driver" : "irq_event", trial);
                    if (recover_spi() != XST_SUCCESS) { xil_printf("SPI recovery failed.\r\n"); return; }
                    continue;
                }
                if (completed_bytes != n) {
                    ++result.api_errors; ++result.short_returns;
                    spi_bench_failure(&result, SPI_BENCH_SHORT_TRANSFER, "short_transfer", trial);
                    if (recover_spi() != XST_SUCCESS) { xil_printf("SPI recovery failed.\r\n"); return; }
                    continue;
                }
                ++result.api_success;
                int valid_rx = spi_bench_verify(&result, tx, rx, n, trial);
                if (end < start) {
                    ++result.timer_errors;
                    spi_bench_failure(&result, SPI_BENCH_TIMER_ERROR, "timer", trial);
                } else if (valid_rx) {
                    spi_bench_sample(&result, (double)(end - start) * 1e9 /
                                      (double)COUNTS_PER_SECOND);
                }
            }
            spi_bench_row(n, &result, timeout_count);
            failures += result.api_errors + result.mismatches + result.timer_errors;
        }
        puts("---CSV-END---");
        puts("# cpu_metric=busy_wait_core_occupancy (100% of one core while active)");
        printf("# sweep_complete=1 failures=%u topology=UNVERIFIED\n", failures);
        XSpi_IntrGlobalDisable(&spi);
        XSpi_Stop(&spi);
        xil_printf("\r\nIntegrity sweep complete: %u failure(s) across %u payload(s).\r\n",
                   failures, run_payload_count);
        return;
    }

    puts("repetition,payload_bytes,window_s,attempts,verified_transfers,verified_bytes,application_MBps,cpu_metric_kind,cpu_metric_pct,thread_cpu_s,thread_cpu_share_pct,busy_wait_core_occupancy_pct,max_transfer_us,api_errors,mismatches,first_error_code");

    uint64_t window_ticks = (uint64_t)run_window_seconds * (uint64_t)COUNTS_PER_SECOND;
    for (unsigned repetition = 1; repetition <= run_repetitions; ++repetition) {
        for (unsigned p = 0; p < run_payload_count; ++p) {
            unsigned n = run_payloads[p];
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
            double secs = end >= start ? (double)(end - start) / (double)COUNTS_PER_SECOND : 0.0;
            double rate = secs > 0.0 ? (double)(verified * n) / secs / 1e6 : 0.0;
            double max_us = (double)max_transfer_ticks * 1e6 / (double)COUNTS_PER_SECOND;
            printf("  rep %u, %u-byte payload: %" PRIu64 " transfers in %.3f s | %" PRIu64 " errors, %" PRIu64 " mismatches | %.3f MB/s | max %.3f us\r\n",
                   repetition, n, verified, secs, errors, mismatches, rate, max_us);
            if (errors || mismatches || (double)(end-start)/(double)COUNTS_PER_SECOND < (double)run_window_seconds * 0.99) {
                printf("# point_failed repetition=%u payload_bytes=%u; stopping without retry\n", repetition, n);
                xil_printf("  -> point FAILED; stopping this run.\r\n");
                XSpi_IntrGlobalDisable(&spi);
                XSpi_Stop(&spi);
                return;
            }
        }
    }
    XSpi_IntrGlobalDisable(&spi);
    XSpi_Stop(&spi);
    puts("# sustained_sweep_complete=1 topology=UNVERIFIED");
    xil_printf("\r\nSustained benchmark complete: no errors.\r\n");
}

int main(void)
{
    for (;;) {
        int selected;
        do {
            selected = select_run();
        } while (selected < 0);
        if (selected == 0) {
            xil_printf("Returning to the Linux default with PSCI SYSTEM_RESET.\r\n");
            __asm__ volatile(
                "movz x0, #0x0009\n"
                "movk x0, #0x8400, lsl #16\n"
                "smc #0\n"
                "1: wfe\n"
                "b 1b\n" ::: "x0", "memory");
        }
        run_test();
        xil_printf("\r\n-- test complete; press Enter for the menu --\r\n");
        (void)inbyte();
    }
}

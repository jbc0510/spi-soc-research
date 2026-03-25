/*
 * SPI Performance Benchmark - Bare-Metal
 * Author: Jerry Conway (jbc0510)
 * Hardware: Xilinx ZCU102 (Zynq UltraScale+ PS)
 * Target:   xczu9eg-ffvb1156-2-e
 *
 * Measures SPI transaction latency using:
 *   - XSpiPs driver (polled + interrupt mode)
 *   - IOU Timestamp Counter (10ns resolution)
 *   - Payload sweep: 1,4,16,64,256,1024,4096 bytes
 *
 * UART output on /dev/ttyUSB1 at 115200 baud
 * Results exported as CSV for Phase 6 comparison
 *
 * Research Tasks: A, B, C, E
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

/*===========================================================
 * ZCU102 UltraScale+ Register Map
 * All addresses from Zynq UltraScale+ TRM (UG1085)
 *===========================================================*/

/* PS SPI0 — MIO 38-43 */
#define XSPIPS_BASEADDR         0xFF040000UL

/* SPI Register offsets (from Zynq UltraScale+ TRM Table 19-3) */
#define XSPIPS_CR_OFFSET        0x00    /* Config register        */
#define XSPIPS_SR_OFFSET        0x04    /* Interrupt status       */
#define XSPIPS_IER_OFFSET       0x08    /* Interrupt enable       */
#define XSPIPS_IDR_OFFSET       0x0C    /* Interrupt disable      */
#define XSPIPS_IMR_OFFSET       0x10    /* Interrupt mask         */
#define XSPIPS_ER_OFFSET        0x14    /* SPI enable             */
#define XSPIPS_DR_OFFSET        0x18    /* Delay register         */
#define XSPIPS_TXD_OFFSET       0x1C    /* TX data                */
#define XSPIPS_RXD_OFFSET       0x20    /* RX data                */
#define XSPIPS_SICR_OFFSET      0x24    /* Slave idle count       */
#define XSPIPS_TXWR_OFFSET      0x28    /* TX FIFO watermark      */
#define XSPIPS_RXWR_OFFSET      0x2C    /* RX FIFO watermark      */

/* Config register bits */
#define XSPIPS_CR_MODF_GEN_EN   0x00000020UL
#define XSPIPS_CR_MANSTRT_EN    0x00008000UL
#define XSPIPS_CR_MANSTRT       0x00010000UL
#define XSPIPS_CR_CPHA          0x00000004UL
#define XSPIPS_CR_CPOL          0x00000002UL
#define XSPIPS_CR_SSCTRL        0x00003C00UL  /* CS bits            */
#define XSPIPS_CR_PRESC_MASK    0x00000038UL  /* Baud rate divider  */
#define XSPIPS_CR_MSTREN        0x00000001UL  /* Master enable      */

/* Prescaler values — SPI clock = ref_clk / (2 ^ (N+1)) */
/* ref_clk = 125MHz on ZCU102                             */
/* BAUD_DIV_4  → 31.25 MHz                               */
/* BAUD_DIV_8  → 15.625 MHz                              */
/* BAUD_DIV_32 →  3.906 MHz                              */
#define XSPIPS_CR_PRESC_DIV_4   (0x1 << 3)
#define XSPIPS_CR_PRESC_DIV_8   (0x2 << 3)
#define XSPIPS_CR_PRESC_DIV_32  (0x4 << 3)

/* Status register bits */
#define XSPIPS_SR_TXFULL        0x00000008UL
#define XSPIPS_SR_RXNEMPTY      0x00000010UL
#define XSPIPS_SR_TXOW          0x00000004UL  /* TX FIFO not full   */
#define XSPIPS_IXR_TXOW         0x00000004UL
#define XSPIPS_IXR_MODF         0x00000002UL
#define XSPIPS_IXR_RXOVR        0x00000001UL

/* Register access macros */
#define SPI_REG(offset) \
    (*(volatile uint32_t *)(XSPIPS_BASEADDR + (offset)))

/*===========================================================
 * IOU Timestamp Counter — 10ns resolution
 * ZCU102 TRM UG1085 Section "IOU Timestamper"
 * Base: 0xFF260000, counter increments at 100MHz
 *===========================================================*/
#define IOU_TSTAMP_BASE         0xFF260000UL
#define IOU_TSTAMP_CTR_L        (*(volatile uint32_t *)(IOU_TSTAMP_BASE + 0x00))
#define IOU_TSTAMP_CTR_H        (*(volatile uint32_t *)(IOU_TSTAMP_BASE + 0x04))
#define IOU_TSTAMP_CTRL         (*(volatile uint32_t *)(IOU_TSTAMP_BASE + 0x08))

/* Timestamp counter runs at 100MHz = 10ns per tick */
#define TSTAMP_FREQ_HZ          100000000ULL
#define TSTAMP_NS_PER_TICK      10ULL

/*===========================================================
 * GIC — Interrupt controller (for interrupt mode)
 * ZCU102: SPI0 IRQ = 49 (SPI interrupt in GICv2)
 *===========================================================*/
#define GIC_DIST_BASE           0xF9010000UL
#define GIC_CPU_BASE            0xF9020000UL
#define GICD_ISENABLER(n)       (*(volatile uint32_t *)(GIC_DIST_BASE + 0x100 + (n)*4))
#define GICC_EOIR               (*(volatile uint32_t *)(GIC_CPU_BASE  + 0x010))
#define GICC_IAR                (*(volatile uint32_t *)(GIC_CPU_BASE  + 0x00C))
#define GICC_CTLR               (*(volatile uint32_t *)(GIC_CPU_BASE  + 0x000))
#define GICD_CTLR               (*(volatile uint32_t *)(GIC_DIST_BASE + 0x000))
#define SPI0_IRQ_ID             49

/*===========================================================
 * Benchmark Configuration
 *===========================================================*/
#define NUM_TRIALS              1000
#define MAX_PAYLOAD             4096

static const int payload_sizes[] = {1, 4, 16, 64, 256, 1024, 4096};
#define NUM_PAYLOADS (sizeof(payload_sizes) / sizeof(payload_sizes[0]))

/*===========================================================
 * Result structures
 *===========================================================*/
typedef struct {
    double min_ns;
    double max_ns;
    double avg_ns;
    double stddev_ns;
    double throughput_kbps;
} benchmark_result_t;

typedef enum {
    MODE_POLLED    = 0,
    MODE_INTERRUPT = 1
} spi_mode_t;

/*===========================================================
 * Volatile flag set by interrupt handler
 *===========================================================*/
static volatile int spi_irq_done = 0;

/*===========================================================
 * Timestamp counter functions
 *===========================================================*/
static inline uint64_t tstamp_read(void)
{
    uint32_t lo, hi, hi2;
    /* Double-read high word to handle rollover */
    do {
        hi  = IOU_TSTAMP_CTR_H;
        lo  = IOU_TSTAMP_CTR_L;
        hi2 = IOU_TSTAMP_CTR_H;
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

static inline double ticks_to_ns(uint64_t ticks)
{
    return (double)ticks * TSTAMP_NS_PER_TICK;
}

/*===========================================================
 * SPI Controller Init
 *===========================================================*/
static void spi_init(void)
{
    /* Disable SPI */
    SPI_REG(XSPIPS_ER_OFFSET) = 0x0;

    /* Configure:
     *   Master mode | CS = none (0xF<<10) | BAUD/8 | CPOL=0 | CPHA=0
     *   Manual CS control | Manual start enable
     */
    SPI_REG(XSPIPS_CR_OFFSET) =
        XSPIPS_CR_MSTREN        |   /* master          */
        (0xFUL << 10)           |   /* CS deasserted   */
        XSPIPS_CR_PRESC_DIV_8   |   /* 15.625 MHz      */
        XSPIPS_CR_MANSTRT_EN;       /* manual start    */

    /* Disable all interrupts */
    SPI_REG(XSPIPS_IDR_OFFSET) = 0x7F;

    /* Enable SPI */
    SPI_REG(XSPIPS_ER_OFFSET) = 0x1;
}

/*===========================================================
 * Assert / Deassert CS (loopback — CS0)
 *===========================================================*/
static inline void spi_cs_assert(void)
{
    uint32_t cr = SPI_REG(XSPIPS_CR_OFFSET);
    cr &= ~XSPIPS_CR_SSCTRL;       /* clear CS field  */
    cr |= (0xEUL << 10);           /* CS0 active low  */
    SPI_REG(XSPIPS_CR_OFFSET) = cr;
}

static inline void spi_cs_deassert(void)
{
    uint32_t cr = SPI_REG(XSPIPS_CR_OFFSET);
    cr |= XSPIPS_CR_SSCTRL;        /* all CS high     */
    SPI_REG(XSPIPS_CR_OFFSET) = cr;
}

/*===========================================================
 * Polled Transfer
 *===========================================================*/
static void spi_transfer_polled(const uint8_t *tx, uint8_t *rx, int len)
{
    int tx_count = 0;
    int rx_count = 0;

    spi_cs_assert();

    while (rx_count < len) {
        /* Fill TX FIFO */
        while (tx_count < len &&
               !(SPI_REG(XSPIPS_SR_OFFSET) & XSPIPS_SR_TXFULL)) {
            SPI_REG(XSPIPS_TXD_OFFSET) = tx ? tx[tx_count] : 0xFF;
            tx_count++;
        }

        /* Trigger transmission */
        SPI_REG(XSPIPS_CR_OFFSET) |= XSPIPS_CR_MANSTRT;

        /* Drain RX FIFO */
        while (rx_count < tx_count) {
            while (!(SPI_REG(XSPIPS_SR_OFFSET) & XSPIPS_SR_RXNEMPTY));
            uint8_t byte = (uint8_t)SPI_REG(XSPIPS_RXD_OFFSET);
            if (rx) rx[rx_count] = byte;
            rx_count++;
        }
    }

    spi_cs_deassert();
}

/*===========================================================
 * Interrupt-driven Transfer
 * Uses TXOW (TX FIFO not full) interrupt
 *===========================================================*/
static uint8_t  irq_tx_buf[MAX_PAYLOAD];
static uint8_t  irq_rx_buf[MAX_PAYLOAD];
static volatile int irq_tx_idx;
static volatile int irq_rx_idx;
static volatile int irq_total_len;

/* Called from IRQ handler */
static void spi_irq_handler(void)
{
    uint32_t isr = SPI_REG(XSPIPS_SR_OFFSET);

    /* Drain RX */
    while (SPI_REG(XSPIPS_SR_OFFSET) & XSPIPS_SR_RXNEMPTY) {
        uint8_t b = (uint8_t)SPI_REG(XSPIPS_RXD_OFFSET);
        if (irq_rx_idx < irq_total_len)
            irq_rx_buf[irq_rx_idx++] = b;
    }

    /* Fill TX if more to send */
    while (irq_tx_idx < irq_total_len &&
           !(SPI_REG(XSPIPS_SR_OFFSET) & XSPIPS_SR_TXFULL)) {
        SPI_REG(XSPIPS_TXD_OFFSET) = irq_tx_buf[irq_tx_idx++];
    }

    /* Trigger */
    SPI_REG(XSPIPS_CR_OFFSET) |= XSPIPS_CR_MANSTRT;

    /* Done? */
    if (irq_rx_idx >= irq_total_len) {
        /* Disable TX interrupt */
        SPI_REG(XSPIPS_IDR_OFFSET) = XSPIPS_IXR_TXOW;
        spi_cs_deassert();
        spi_irq_done = 1;
    }

    /* Clear status */
    SPI_REG(XSPIPS_SR_OFFSET) = isr;
}

/*
 * Minimal GIC setup for SPI0 interrupt (IRQ 49)
 * In a real Vitis project this is handled by XScuGic driver.
 * For standalone bare-metal we configure directly.
 */
static void gic_enable_spi0_irq(void)
{
    /* Enable GIC distributor and CPU interface */
    GICD_CTLR = 1;
    GICC_CTLR = 1;

    /* Enable SPI0 IRQ (49) in distributor */
    GICD_ISENABLER(49 / 32) = (1U << (49 % 32));
}

static void spi_transfer_interrupt(const uint8_t *tx, uint8_t *rx, int len)
{
    /* Set up IRQ transfer state */
    memcpy(irq_tx_buf, tx, len);
    memset(irq_rx_buf, 0, len);
    irq_tx_idx   = 0;
    irq_rx_idx   = 0;
    irq_total_len = len;
    spi_irq_done  = 0;

    spi_cs_assert();

    /* Enable TXOW interrupt */
    SPI_REG(XSPIPS_IER_OFFSET) = XSPIPS_IXR_TXOW;

    /* Seed TX FIFO */
    while (irq_tx_idx < len &&
           !(SPI_REG(XSPIPS_SR_OFFSET) & XSPIPS_SR_TXFULL)) {
        SPI_REG(XSPIPS_TXD_OFFSET) = irq_tx_buf[irq_tx_idx++];
    }

    /* Trigger first burst */
    SPI_REG(XSPIPS_CR_OFFSET) |= XSPIPS_CR_MANSTRT;

    /* Wait for completion (IRQ handler sets flag) */
    while (!spi_irq_done) {
        /* In real Vitis standalone app, WFI would go here.
         * For benchmark accuracy we spin to avoid WFI latency. */
    }

    if (rx) memcpy(rx, irq_rx_buf, len);
}

/*===========================================================
 * Run Benchmark — one payload size, one mode
 *===========================================================*/
static benchmark_result_t run_benchmark(int payload_size, spi_mode_t mode)
{
    static uint8_t tx[MAX_PAYLOAD];
    static uint8_t rx[MAX_PAYLOAD];
    static double  latencies[NUM_TRIALS];

    benchmark_result_t result = {0};
    double sum = 0.0;

    /* Fill TX with incrementing pattern */
    for (int i = 0; i < payload_size; i++)
        tx[i] = (uint8_t)(i & 0xFF);

    /* Warm up — 10 transfers not counted */
    for (int w = 0; w < 10; w++) {
        if (mode == MODE_POLLED)
            spi_transfer_polled(tx, rx, payload_size);
        else
            spi_transfer_interrupt(tx, rx, payload_size);
    }

    /* Timed trials */
    for (int t = 0; t < NUM_TRIALS; t++) {
        uint64_t t0, t1;

        t0 = tstamp_read();
        if (mode == MODE_POLLED)
            spi_transfer_polled(tx, rx, payload_size);
        else
            spi_transfer_interrupt(tx, rx, payload_size);
        t1 = tstamp_read();

        latencies[t] = ticks_to_ns(t1 - t0);
        sum += latencies[t];
    }

    /* Statistics */
    result.avg_ns = sum / NUM_TRIALS;
    result.min_ns = latencies[0];
    result.max_ns = latencies[0];

    double variance = 0.0;
    for (int t = 0; t < NUM_TRIALS; t++) {
        if (latencies[t] < result.min_ns) result.min_ns = latencies[t];
        if (latencies[t] > result.max_ns) result.max_ns = latencies[t];
        double diff = latencies[t] - result.avg_ns;
        variance += diff * diff;
    }
    result.stddev_ns = __builtin_sqrt(variance / NUM_TRIALS);

    /* Throughput: payload_bytes * 8 bits / avg_time_seconds */
    double avg_sec = result.avg_ns / 1e9;
    result.throughput_kbps = ((double)payload_size * 8.0) / avg_sec / 1000.0;

    return result;
}

/*===========================================================
 * Print CSV row
 *===========================================================*/
static void print_csv_row(const char *mode_str, int size,
                           const benchmark_result_t *r)
{
    printf("%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f\n",
           mode_str, size,
           r->min_ns, r->max_ns, r->avg_ns,
           r->stddev_ns, r->throughput_kbps);
}

/*===========================================================
 * Main
 *===========================================================*/
int main(void)
{
    /* Enable IOU timestamp counter */
    IOU_TSTAMP_CTRL = 0x1;

    spi_init();
    gic_enable_spi0_irq();

    /* CSV header */
    printf("# ZCU102 Bare-Metal SPI Benchmark\n");
    printf("# mode,payload_bytes,min_ns,max_ns,avg_ns,stddev_ns,"
           "throughput_kbps\n");
    printf("mode,bytes,min_ns,max_ns,avg_ns,stddev_ns,kbps\n");

    /* ── Polled mode ── */
    printf("\n# --- Polled Mode ---\n");
    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(size, MODE_POLLED);
        print_csv_row("polled", size, &r);
    }

    /* ── Interrupt mode ── */
    printf("\n# --- Interrupt Mode ---\n");
    for (int p = 0; p < NUM_PAYLOADS; p++) {
        int size = payload_sizes[p];
        benchmark_result_t r = run_benchmark(size, MODE_INTERRUPT);
        print_csv_row("interrupt", size, &r);
    }

    printf("\n# Benchmark complete\n");

    /* Halt */
    while (1);
    return 0;
}

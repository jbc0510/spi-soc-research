#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <time.h>

#ifndef SPI_DEVICE
#define SPI_DEVICE "/dev/spidev0.0"
#endif

#define SPI_SPEED_HZ  1000000
#define SPI_BITS      8

static double get_time_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (ts.tv_sec * 1e6) + (ts.tv_nsec / 1e3);
}

static int spi_transfer(int fd, uint8_t *tx, uint8_t *rx, int len) {
    struct spi_ioc_transfer tr = {
        .tx_buf = (unsigned long)tx,
        .rx_buf = (unsigned long)rx,
        .len    = len,
        .speed_hz = SPI_SPEED_HZ,
        .bits_per_word = SPI_BITS,
    };
    return ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
}

int main(void) {
    int fd = open(SPI_DEVICE, O_RDWR);
    if (fd < 0) { perror("open"); return 1; }

    uint32_t mode = SPI_MODE_0;
    uint8_t bits = SPI_BITS;
    uint32_t speed = SPI_SPEED_HZ;
    ioctl(fd, SPI_IOC_WR_MODE32, &mode);
    ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits);
    ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed);

    printf("SPI Loopback Integrity Test\n");
    printf("============================\n");
    printf("Device: %s\n", SPI_DEVICE);
    printf("Speed:  %d Hz\n\n", SPI_SPEED_HZ);
    printf("%-10s %-10s %-12s %-10s %s\n",
           "Bytes", "Trials", "Avg(us)", "Errors", "Status");
    printf("%-10s %-10s %-12s %-10s %s\n",
           "----------", "----------", "------------", "----------", "------");

    int payload_sizes[] = {1, 8, 16, 64, 128, 256, 512, 1024, 4096, 16384,
                           65536, 131072, 262144, 524288, 1048576};
    int num_payloads = sizeof(payload_sizes) / sizeof(payload_sizes[0]);

    for (int p = 0; p < num_payloads; p++) {
        int size = payload_sizes[p];
        int trials = (size <= 256) ? 1000 : (size <= 4096) ? 100 : (size <= 65536) ? 10 : 3;

        uint8_t *tx = calloc(size, 1);
        uint8_t *rx = calloc(size, 1);
        if (!tx || !rx) { printf("OOM at %d bytes\n", size); break; }

        /* Fill with known pattern */
        for (int i = 0; i < size; i++)
            tx[i] = (uint8_t)((i * 37 + 13) & 0xFF);

        double sum = 0;
        int errors = 0;
        int failed_trial = -1;
        int first_bad_byte = -1;

        for (int t = 0; t < trials; t++) {
            memset(rx, 0, size);
            double start = get_time_us();
            int ret = spi_transfer(fd, tx, rx, size);
            double end = get_time_us();

            if (ret < 0) {
                errors++;
                if (failed_trial < 0) failed_trial = t;
                continue;
            }

            sum += (end - start);

            /* Verify received data matches sent */
            for (int i = 0; i < size; i++) {
                if (rx[i] != tx[i]) {
                    errors++;
                    if (first_bad_byte < 0) first_bad_byte = i;
                    break;
                }
            }
        }

        double avg = (trials - errors > 0) ? sum / (trials - errors) : 0;
        const char *status = (errors == 0) ? "PASS" :
                             (errors == trials) ? "FAIL" : "PARTIAL";

        printf("%-10d %-10d %-12.2f %-10d %s",
               size, trials, avg, errors, status);

        if (first_bad_byte >= 0)
            printf(" (first corrupt byte: %d)", first_bad_byte);
        if (failed_trial >= 0 && first_bad_byte < 0)
            printf(" (ioctl error on trial %d)", failed_trial);
        printf("\n");

        free(tx);
        free(rx);

        /* Stop if complete failure */
        if (errors == trials && size > 256) {
            printf("\nStopping — complete transfer failure at %d bytes.\n", size);
            break;
        }
    }

    close(fd);
    return 0;
}

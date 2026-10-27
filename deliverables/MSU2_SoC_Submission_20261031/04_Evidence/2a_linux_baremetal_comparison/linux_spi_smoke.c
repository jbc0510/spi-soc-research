#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/spi/spidev.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    if (argc != 2) { fprintf(stderr, "usage: %s /dev/spidevN.0\n", argv[0]); return 2; }
    int fd = open(argv[1], O_RDWR);
    if (fd < 0) { perror("open"); return 2; }
    uint32_t mode = SPI_MODE_0, speed = 1000000, mode_rb = ~0U, speed_rb = 0;
    uint8_t bits = 8, bits_rb = 0;
    if (ioctl(fd, SPI_IOC_WR_MODE32, &mode) || ioctl(fd, SPI_IOC_RD_MODE32, &mode_rb) ||
        ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) || ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &bits_rb) ||
        ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) || ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &speed_rb)) {
        perror("SPI config"); close(fd); return 2;
    }
    uint8_t tx = 0xA5, rx = 0x5A;
    struct spi_ioc_transfer tr = { .tx_buf=(uintptr_t)&tx, .rx_buf=(uintptr_t)&rx,
        .len=1, .speed_hz=speed, .bits_per_word=8, .cs_change=0 };
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC_RAW, &a);
    int rc = ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
    int saved = errno;
    clock_gettime(CLOCK_MONOTONIC_RAW, &b);
    uint64_t ns = (uint64_t)(b.tv_sec-a.tv_sec)*1000000000ULL + b.tv_nsec-a.tv_nsec;
    printf("device=%s mode=0x%x mode_readback=0x%x bits=%u speed_requested_hz=%u speed_readback_hz=%u tx=%02x rx=%02x ioctl_rc=%d errno=%d elapsed_ns=%" PRIu64 "\n",
           argv[1], mode_rb, mode_rb, bits_rb, speed, speed_rb, tx, rx, rc, saved, ns);
    close(fd);
    return rc == 1 && rx == tx ? 0 : 1;
}

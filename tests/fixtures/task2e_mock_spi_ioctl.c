#define _GNU_SOURCE
#include <errno.h>
#include <linux/spi/spidev.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>

static uint32_t mock_mode;
static uint32_t mock_speed;
static uint8_t mock_bits;
static int transferred;

int ioctl(int fd, unsigned long request, ...)
{
    (void)fd;
    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    if (request == SPI_IOC_WR_MODE32) mock_mode = *(uint32_t *)arg;
    else if (request == SPI_IOC_RD_MODE32) *(uint32_t *)arg = mock_mode;
    else if (request == SPI_IOC_WR_BITS_PER_WORD) mock_bits = *(uint8_t *)arg;
    else if (request == SPI_IOC_RD_BITS_PER_WORD) *(uint8_t *)arg = mock_bits;
    else if (request == SPI_IOC_WR_MAX_SPEED_HZ) mock_speed = *(uint32_t *)arg;
    else if (request == SPI_IOC_RD_MAX_SPEED_HZ) *(uint32_t *)arg = mock_speed;
    else if (request == SPI_IOC_MESSAGE(1)) {
        const char *failure = getenv("MSU2_MOCK_SPI_FAILURE");
        if (failure && strcmp(failure, "api") == 0) { errno = EIO; return -1; }
        struct spi_ioc_transfer *tr = arg;
        uint8_t *rx = (uint8_t *)(uintptr_t)tr->rx_buf;
        memcpy(rx, (const void *)(uintptr_t)tr->tx_buf, tr->len);
        if (failure && strcmp(failure, "mismatch") == 0 && !transferred && tr->len)
            rx[0] ^= 0xffU;
        transferred = 1;
        return (int)tr->len;
    }
    else { errno = ENOTTY; return -1; }
    return 0;
}

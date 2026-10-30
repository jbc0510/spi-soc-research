.text
.global _start
_start:
    movz x1, #0xff00, lsl #16     /* UART0 base 0xFF000000 */
    adr  x2, msg
    mov  x3, #16                  /* 16 bytes (fits empty 64-deep FIFO) */
1:  ldrb w0, [x2], #1
    strb w0, [x1, #0x30]          /* write TX FIFO, no poll */
    subs x3, x3, #1
    b.ne 1b
2:  wfe
    b    2b
msg:
    .ascii "\r\nMSU2-GO-REACH\r\n"

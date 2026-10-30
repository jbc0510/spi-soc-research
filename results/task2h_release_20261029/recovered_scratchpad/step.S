.text
.global _start
.macro PUTC c
    mov  w0, #\c
9:  ldrb w2, [x1, #0x2c]      /* channel_sts */
    tbnz w2, #4, 9b           /* TXFULL -> wait */
    strb w0, [x1, #0x30]      /* TX FIFO */
.endm
_start:
    movz x1, #0xff00, lsl #16 /* UART0 */
    PUTC 0x41                 /* 'A' reached at EL1 */
    mrs  x5, pmcr_el0         /* suspect: PMCR read (MDCR trap?) */
    PUTC 0x42                 /* 'B' */
    orr  x5, x5, #0x1
    msr  pmcr_el0, x5         /* suspect: PMCR write */
    PUTC 0x43                 /* 'C' */
    ldr  x2, =0x00117000
    msr  ttbr0_el1, x2
    ldr  x2, =0x000000bb0400ff44
    msr  mair_el1, x2
    ldr  x2, =0x0000000285800518
    msr  tcr_el1, x2
    isb
    PUTC 0x44                 /* 'D' MMU regs set */
    movz x2, #0x0
    orr  x2, x2, #0x40000
    orr  x2, x2, #0x20000
    orr  x2, x2, #0x20
    orr  x2, x2, #0x1000
    orr  x2, x2, #0x4
    orr  x2, x2, #0x1
    msr  sctlr_el1, x2        /* suspect: enable MMU + I/D cache */
    isb
    PUTC 0x45                 /* 'E' MMU enabled */
    PUTC 0x0d
    PUTC 0x0a
0:  wfe
    b 0b

.text
.macro TX reg
9:  ldrb w7,[x1,#0x2c]
    tbnz w7,#4,9b
    strb \reg,[x1,#0x30]
.endm
/* ---- code @ 0x02000000 ---- */
_start:
    movz x1,#0xff00,lsl #16          /* UART0 */
    movz x0,#0x0200,lsl #16
    movk x0,#0x2000                  /* VBAR = 0x02002000 */
    msr  vbar_el1,x0
    isb
    mov  w0,#0x41
    TX   w0                          /* 'A' */
    ldr  x2,=0x00117000
    msr  ttbr0_el1,x2
    ldr  x2,=0x000000bb0400ff44
    msr  mair_el1,x2
    ldr  x2,=0x0000000285800518
    msr  tcr_el1,x2
    isb
    mov  w0,#0x44
    TX   w0                          /* 'D' */
    mov  x2,#0
    orr  x2,x2,#0x40000
    orr  x2,x2,#0x20000
    orr  x2,x2,#0x20
    orr  x2,x2,#0x1000
    orr  x2,x2,#0x4
    orr  x2,x2,#0x1
    msr  sctlr_el1,x2                /* enable MMU+caches  <-- expected fault */
    isb
    mov  w0,#0x45
    TX   w0                          /* 'E' (survived) */
    b    do_reset

/* print x0 as 16 hex nibbles; x1=uart; clobbers x4,x5,x7 */
puthex:
    mov  x4,#60
1:  lsr  x5,x0,x4
    and  x5,x5,#0xf
    cmp  x5,#10
    b.lt 2f
    add  x5,x5,#('a'-10)
    b    3f
2:  add  x5,x5,#'0'
3:  ldrb w7,[x1,#0x2c]
    tbnz w7,#4,3b
    strb w5,[x1,#0x30]
    subs x4,x4,#4
    b.ge 1b
    ret

do_reset:
    movz x0,#0x0009
    movk x0,#0x8400,lsl #16
    smc  #0
8:  wfe
    b 8b

/* ---- handler @ 0x02001000 ---- */
.org 0x1000
handler:
    movz x1,#0xff00,lsl #16
    mov  w0,#0x3e
    TX   w0                          /* '>' fault entered */
    mov  w0,#0x3a                    /* ':' sep later */
    mrs  x0,esr_el1
    bl   puthex
    mov  w0,#0x2f
    TX   w0                          /* '/' */
    mrs  x0,far_el1
    bl   puthex
    mov  w0,#0x0d
    TX   w0
    mov  w0,#0x0a
    TX   w0
    b    do_reset

/* ---- vectors @ 0x02002000 ---- */
.org 0x2000
    b handler                        /* curEL SP0 sync */
.org 0x2200
    b handler                        /* curEL SPx sync */

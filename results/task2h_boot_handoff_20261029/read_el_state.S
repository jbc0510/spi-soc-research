.text
.global _start
_start:
 adr x1, snapshot
 mrs x0, CurrentEL
 str x0, [x1], #8
 mrs x0, hcr_el2
 str x0, [x1], #8
 mrs x0, sctlr_el1
 str x0, [x1], #8
 mrs x0, cptr_el2
 str x0, [x1], #8
 mrs x0, cnthctl_el2
 str x0, [x1], #8
 mrs x0, vbar_el2
 str x0, [x1], #8
 mrs x0, sctlr_el2
 str x0, [x1], #8
 mov x0, #0
 ret
.balign 8
snapshot:
 .space 56

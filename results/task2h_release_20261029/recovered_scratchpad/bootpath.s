0000000000100988 <_boot>:
  100988:	d2800000 	mov	x0, #0x0                   	// #0
  10098c:	d2800001 	mov	x1, #0x0                   	// #0
  100990:	d2800002 	mov	x2, #0x0                   	// #0
  100994:	d2800003 	mov	x3, #0x0                   	// #0
  100998:	d2800004 	mov	x4, #0x0                   	// #0
  10099c:	d2800005 	mov	x5, #0x0                   	// #0
  1009a0:	d2800006 	mov	x6, #0x0                   	// #0
  1009a4:	d2800007 	mov	x7, #0x0                   	// #0
  1009a8:	d2800008 	mov	x8, #0x0                   	// #0
  1009ac:	d2800009 	mov	x9, #0x0                   	// #0
  1009b0:	d280000a 	mov	x10, #0x0                   	// #0
  1009b4:	d280000b 	mov	x11, #0x0                   	// #0
  1009b8:	d280000c 	mov	x12, #0x0                   	// #0
  1009bc:	d280000d 	mov	x13, #0x0                   	// #0
  1009c0:	d280000e 	mov	x14, #0x0                   	// #0
  1009c4:	d280000f 	mov	x15, #0x0                   	// #0
  1009c8:	d2800010 	mov	x16, #0x0                   	// #0
  1009cc:	d2800011 	mov	x17, #0x0                   	// #0
  1009d0:	d2800012 	mov	x18, #0x0                   	// #0
  1009d4:	d2800013 	mov	x19, #0x0                   	// #0
  1009d8:	d2800014 	mov	x20, #0x0                   	// #0
  1009dc:	d2800015 	mov	x21, #0x0                   	// #0
  1009e0:	d2800016 	mov	x22, #0x0                   	// #0
  1009e4:	d2800017 	mov	x23, #0x0                   	// #0
  1009e8:	d2800018 	mov	x24, #0x0                   	// #0
  1009ec:	d2800019 	mov	x25, #0x0                   	// #0
  1009f0:	d280001a 	mov	x26, #0x0                   	// #0
  1009f4:	d280001b 	mov	x27, #0x0                   	// #0
  1009f8:	d280001c 	mov	x28, #0x0                   	// #0
  1009fc:	d280001d 	mov	x29, #0x0                   	// #0
  100a00:	d280001e 	mov	x30, #0x0                   	// #0

0000000000100a04 <OKToRun>:
  100a04:	d5384240 	mrs	x0, currentel
  100a08:	f100301f 	cmp	x0, #0xc
  100a0c:	54000080 	b.eq	100a1c <InitEL3>  // b.none
  100a10:	f100101f 	cmp	x0, #0x4
  100a14:	54000060 	b.eq	100a20 <InitEL1>  // b.none
  100a18:	14000028 	b	100ab8 <error>

0000000000100a1c <InitEL3>:
  100a1c:	14000027 	b	100ab8 <error>

0000000000100a20 <InitEL1>:
  100a20:	58000941 	ldr	x1, 100b48 <invalidateCaches_end+0x4>
  100a24:	d518c001 	msr	vbar_el1, x1
  100a28:	d5381040 	mrs	x0, cpacr_el1
  100a2c:	926af400 	and	x0, x0, #0xffffffffffcfffff
  100a30:	d5181040 	msr	cpacr_el1, x0
  100a34:	d5033fdf 	isb
  100a38:	580008c0 	ldr	x0, 100b50 <invalidateCaches_end+0xc>
  100a3c:	f900001f 	str	xzr, [x0]
  100a40:	580008c2 	ldr	x2, 100b58 <invalidateCaches_end+0x14>
  100a44:	9100005f 	mov	sp, x2
  100a48:	d2800001 	mov	x1, #0x0                   	// #0
  100a4c:	d5181001 	msr	sctlr_el1, x1
  100a50:	d5033fdf 	isb
  100a54:	d508871f 	tlbi	vmalle1
  100a58:	d508751f 	ic	iallu
  100a5c:	94000018 	bl	100abc <invalidate_dcaches>
  100a60:	d5033f9f 	dsb	sy
  100a64:	d5033fdf 	isb
  100a68:	580007c1 	ldr	x1, 100b60 <invalidateCaches_end+0x1c>
  100a6c:	d5182001 	msr	ttbr0_el1, x1
  100a70:	580007c1 	ldr	x1, 100b68 <invalidateCaches_end+0x24>
  100a74:	d518a201 	msr	mair_el1, x1
  100a78:	580007c1 	ldr	x1, 100b70 <invalidateCaches_end+0x2c>
  100a7c:	d5182041 	msr	tcr_el1, x1
  100a80:	d5033fdf 	isb
  100a84:	d53b4221 	mrs	x1, daif
  100a88:	9277f821 	and	x1, x1, #0xfffffffffffffeff
  100a8c:	d51b4221 	msr	daif, x1
  100a90:	d2800001 	mov	x1, #0x0                   	// #0
  100a94:	b26e0021 	orr	x1, x1, #0x40000
  100a98:	b26f0021 	orr	x1, x1, #0x20000
  100a9c:	b27b0021 	orr	x1, x1, #0x20
  100aa0:	b2740021 	orr	x1, x1, #0x1000
  100aa4:	b27e0021 	orr	x1, x1, #0x4
  100aa8:	b2400021 	orr	x1, x1, #0x1
  100aac:	d5181001 	msr	sctlr_el1, x1
  100ab0:	d5033fdf 	isb
  100ab4:	94000515 	bl	101f08 <_startup>

0000000000100ab8 <error>:
  100ab8:	14000000 	b	100ab8 <error>

0000000000100abc <invalidate_dcaches>:
  100abc:	d5033bbf 	dmb	ish
  100ac0:	d5390020 	mrs	x0, clidr_el1
  100ac4:	53186802 	ubfx	w2, w0, #24, #3
  100ac8:	7100005f 	cmp	w2, #0x0
  100acc:	540003c0 	b.eq	100b44 <invalidateCaches_end>  // b.none
  100ad0:	52800001 	mov	w1, #0x0                   	// #0

0000000000100ad4 <invalidateCaches_flush_level>:
  100ad4:	0b010423 	add	w3, w1, w1, lsl #1
  100ad8:	1ac32403 	lsr	w3, w0, w3
  100adc:	53000863 	ubfx	w3, w3, #0, #3
  100ae0:	7100087f 	cmp	w3, #0x2
  100ae4:	540002ab 	b.lt	100b38 <invalidateCaches_next_level>  // b.tstop
  100ae8:	531f7824 	lsl	w4, w1, #1
  100aec:	d51a0004 	msr	csselr_el1, x4
  100af0:	d5033fdf 	isb
  100af4:	d5390004 	mrs	x4, ccsidr_el1
  100af8:	53000883 	ubfx	w3, w4, #0, #3
  100afc:	11000863 	add	w3, w3, #0x2
  100b00:	530d6c85 	ubfx	w5, w4, #13, #15
  100b04:	53033084 	ubfx	w4, w4, #3, #10
  100b08:	5ac01086 	clz	w6, w4

0000000000100b0c <invalidateCaches_flush_set>:
  100b0c:	2a0403e8 	mov	w8, w4

0000000000100b10 <invalidateCaches_flush_way>:
  100b10:	531f7827 	lsl	w7, w1, #1
  100b14:	1ac320a9 	lsl	w9, w5, w3
  100b18:	2a0900e7 	orr	w7, w7, w9
  100b1c:	1ac62109 	lsl	w9, w8, w6
  100b20:	2a0900e7 	orr	w7, w7, w9
  100b24:	d5087e47 	dc	cisw, x7
  100b28:	71000508 	subs	w8, w8, #0x1
  100b2c:	54ffff2a 	b.ge	100b10 <invalidateCaches_flush_way>  // b.tcont
  100b30:	710004a5 	subs	w5, w5, #0x1
  100b34:	54fffeca 	b.ge	100b0c <invalidateCaches_flush_set>  // b.tcont

0000000000100b38 <invalidateCaches_next_level>:
  100b38:	11000421 	add	w1, w1, #0x1
  100b3c:	6b01005f 	cmp	w2, w1
  100b40:	54fffcac 	b.gt	100ad4 <invalidateCaches_flush_level>

0000000000100b44 <invalidateCaches_end>:
  100b44:	d65f03c0 	ret
  100b48:	00100000 	.word	0x00100000
  100b4c:	00000000 	.word	0x00000000
  100b50:	00100918 	.word	0x00100918
  100b54:	00000000 	.word	0x00000000
  100b58:	001449c0 	.word	0x001449c0
  100b5c:	00000000 	.word	0x00000000
  100b60:	00117000 	.word	0x00117000
  100b64:	00000000 	.word	0x00000000
  100b68:	0400ff44 	.word	0x0400ff44
  100b6c:	000000bb 	.word	0x000000bb
  100b70:	85800518 	.word	0x85800518
  100b74:	00000002 	.word	0x00000002
	...

0000000000100b80 <__do_global_dtors_aux>:
  100b80:	d503233f 	paciasp
  100b84:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  100b88:	910003fd 	mov	x29, sp
  100b8c:	f9000bf3 	str	x19, [sp, #16]
  100b90:	f00000f3 	adrp	x19, 11f000 <XScuGic_ConfigTable+0xfa8>
  100b94:	39660260 	ldrb	w0, [x19, #2432]
  100b98:	37000120 	tbnz	w0, #0, 100bbc <__do_global_dtors_aux+0x3c>
  100b9c:	d00000a0 	adrp	x0, 116000 <__malloc_av_+0x2e0>
  100ba0:	f9438000 	ldr	x0, [x0, #1792]
  100ba4:	b4000080 	cbz	x0, 100bb4 <__do_global_dtors_aux+0x34>
  100ba8:	d00000a0 	adrp	x0, 116000 <__malloc_av_+0x2e0>
  100bac:	911e0000 	add	x0, x0, #0x780
  100bb0:	d503201f 	nop
  100bb4:	52800020 	mov	w0, #0x1                   	// #1
  100bb8:	39260260 	strb	w0, [x19, #2432]
  100bbc:	f9400bf3 	ldr	x19, [sp, #16]
  100bc0:	a8c27bfd 	ldp	x29, x30, [sp], #32
  100bc4:	d50323bf 	autiasp
  100bc8:	d65f03c0 	ret
  100bcc:	d503201f 	nop

0000000000100bd0 <frame_dummy>:
  100bd0:	d503245f 	bti	c
  100bd4:	d00000a0 	adrp	x0, 116000 <__malloc_av_+0x2e0>
  100bd8:	f9439800 	ldr	x0, [x0, #1840]
  100bdc:	b40000c0 	cbz	x0, 100bf4 <frame_dummy+0x24>
  100be0:	f00000e1 	adrp	x1, 11f000 <XScuGic_ConfigTable+0xfa8>
  100be4:	d00000a0 	adrp	x0, 116000 <__malloc_av_+0x2e0>
  100be8:	91262021 	add	x1, x1, #0x988
  100bec:	911e0000 	add	x0, x0, #0x780
  100bf0:	d503201f 	nop
  100bf4:	d65f03c0 	ret
	...

0000000000100c00 <spi_status_handler>:
  100c00:	b9000401 	str	w1, [x0, #4]
  100c04:	52800023 	mov	w3, #0x1                   	// #1
  100c08:	b9000802 	str	w2, [x0, #8]
  100c0c:	b9000003 	str	w3, [x0]
  100c10:	d65f03c0 	ret

0000000000100c14 <read_line>:
  100c14:	a9bc7bfd 	stp	x29, x30, [sp, #-64]!
  100c18:	910003fd 	mov	x29, sp
  100c1c:	a9025bf5 	stp	x21, x22, [sp, #32]
  100c20:	aa0003f6 	mov	x22, x0
  100c24:	2a0103f5 	mov	w21, w1
  100c28:	a90153f3 	stp	x19, x20, [sp, #16]
  100c2c:	52800014 	mov	w20, #0x0                   	// #0
  100c30:	52800033 	mov	w19, #0x1                   	// #1
  100c34:	f9001bf7 	str	x23, [sp, #48]
  100c38:	94000f16 	bl	104890 <inbyte>
  100c3c:	12001c02 	and	w2, w0, #0xff
  100c40:	7100345f 	cmp	w2, #0xd
  100c44:	7a4a1844 	ccmp	w2, #0xa, #0x4, ne	// ne = any
  100c48:	54000380 	b.eq	100cb8 <read_line+0xa4>  // b.none
  100c4c:	7101fc5f 	cmp	w2, #0x7f
  100c50:	7a481844 	ccmp	w2, #0x8, #0x4, ne	// ne = any
  100c54:	54000281 	b.ne	100ca4 <read_line+0x90>  // b.any
  100c58:	52800033 	mov	w19, #0x1                   	// #1
  100c5c:	34fffef4 	cbz	w20, 100c38 <read_line+0x24>
  100c60:	51000697 	sub	w23, w20, #0x1
  100c64:	2a1403f3 	mov	w19, w20
  100c68:	2a1703f4 	mov	w20, w23
  100c6c:	52800100 	mov	w0, #0x8                   	// #8
  100c70:	94000f00 	bl	104870 <outbyte>
  100c74:	52800400 	mov	w0, #0x20                  	// #32
  100c78:	94000efe 	bl	104870 <outbyte>
  100c7c:	52800100 	mov	w0, #0x8                   	// #8
  100c80:	94000efc 	bl	104870 <outbyte>
  100c84:	6b1302bf 	cmp	w21, w19
  100c88:	54fffd88 	b.hi	100c38 <read_line+0x24>  // b.pmore
  100c8c:	38344adf 	strb	wzr, [x22, w20, uxtw]
  100c90:	a94153f3 	ldp	x19, x20, [sp, #16]
  100c94:	a9425bf5 	ldp	x21, x22, [sp, #32]
  100c98:	f9401bf7 	ldr	x23, [sp, #48]
  100c9c:	a8c47bfd 	ldp	x29, x30, [sp], #64
  100ca0:	d65f03c0 	ret
  100ca4:	38344ac2 	strb	w2, [x22, w20, uxtw]
  100ca8:	2a1303f4 	mov	w20, w19
  100cac:	11000673 	add	w19, w19, #0x1
  100cb0:	94000ef0 	bl	104870 <outbyte>
  100cb4:	17fffff4 	b	100c84 <read_line+0x70>
  100cb8:	528001a0 	mov	w0, #0xd                   	// #13
  100cbc:	94000eed 	bl	104870 <outbyte>
  100cc0:	52800140 	mov	w0, #0xa                   	// #10
  100cc4:	94000eeb 	bl	104870 <outbyte>
  100cc8:	38344adf 	strb	wzr, [x22, w20, uxtw]
  100ccc:	a94153f3 	ldp	x19, x20, [sp, #16]
  100cd0:	a9425bf5 	ldp	x21, x22, [sp, #32]
  100cd4:	f9401bf7 	ldr	x23, [sp, #48]
  100cd8:	a8c47bfd 	ldp	x29, x30, [sp], #64
  100cdc:	d65f03c0 	ret

0000000000100ce0 <configure_spi>:
  100ce0:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  100ce4:	52800221 	mov	w1, #0x11                  	// #17
  100ce8:	910003fd 	mov	x29, sp
  100cec:	f9000bf3 	str	x19, [sp, #16]
  100cf0:	f00000f3 	adrp	x19, 11f000 <XScuGic_ConfigTable+0xfa8>
  100cf4:	91270273 	add	x19, x19, #0x9c0
  100cf8:	aa1303e0 	mov	x0, x19
  100cfc:	94000af1 	bl	1038c0 <XSpi_SetOptions>
  100d00:	34000080 	cbz	w0, 100d10 <configure_spi+0x30>
  100d04:	f9400bf3 	ldr	x19, [sp, #16]
  100d08:	a8c27bfd 	ldp	x29, x30, [sp], #32
  100d0c:	d65f03c0 	ret
  100d10:	aa1303e0 	mov	x0, x19
  100d14:	52800021 	mov	w1, #0x1                   	// #1
  100d18:	94000cae 	bl	103fd0 <XSpi_SetSlaveSelect>
  100d1c:	35ffff40 	cbnz	w0, 100d04 <configure_spi+0x24>
  100d20:	9101e261 	add	x1, x19, #0x78
  100d24:	90000002 	adrp	x2, 100000 <_vector_table>
  100d28:	91300042 	add	x2, x2, #0xc00
  100d2c:	aa1303e0 	mov	x0, x19
  100d30:	94000d00 	bl	104130 <XSpi_SetStatusHandler>
  100d34:	aa1303e0 	mov	x0, x19
  100d38:	94000b56 	bl	103a90 <XSpi_Start>
  100d3c:	35fffe40 	cbnz	w0, 100d04 <configure_spi+0x24>
  100d40:	f9400e61 	ldr	x1, [x19, #24]
  100d44:	52b00002 	mov	w2, #0x80000000            	// #-2147483648
  100d48:	f9400bf3 	ldr	x19, [sp, #16]
  100d4c:	b9001c22 	str	w2, [x1, #28]
  100d50:	a8c27bfd 	ldp	x29, x30, [sp], #32
  100d54:	d65f03c0 	ret
  100d58:	d503201f 	nop
  100d5c:	d503201f 	nop

0000000000100d60 <recover_spi>:
  100d60:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  100d64:	d2820001 	mov	x1, #0x1000                	// #4096
  100d68:	52820b20 	mov	w0, #0x1059                	// #4185
  100d6c:	910003fd 	mov	x29, sp
  100d70:	f9000bf3 	str	x19, [sp, #16]
  100d74:	f00000f3 	adrp	x19, 11f000 <XScuGic_ConfigTable+0xfa8>
  100d78:	91270273 	add	x19, x19, #0x9c0
  100d7c:	f2a06001 	movk	x1, #0x300, lsl #16
  100d80:	94000358 	bl	101ae0 <XDisableIntrId>
  100d84:	aa1303e0 	mov	x0, x19
  100d88:	f9400e61 	ldr	x1, [x19, #24]
  100d8c:	b9001c3f 	str	wzr, [x1, #28]
  100d90:	94000d2d 	bl	104244 <XSpi_Reset>
  100d94:	b9007a7f 	str	wzr, [x19, #120]
  100d98:	b9007e7f 	str	wzr, [x19, #124]
  100d9c:	b900827f 	str	wzr, [x19, #128]
  100da0:	97ffffd0 	bl	100ce0 <configure_spi>
  100da4:	2a0003f3 	mov	w19, w0
  100da8:	350000a0 	cbnz	w0, 100dbc <recover_spi+0x5c>
  100dac:	d2820001 	mov	x1, #0x1000                	// #4096
  100db0:	52820b20 	mov	w0, #0x1059                	// #4185
  100db4:	f2a06001 	movk	x1, #0x300, lsl #16
  100db8:	9400033e 	bl	101ab0 <XEnableIntrId>
  100dbc:	2a1303e0 	mov	w0, w19
  100dc0:	f9400bf3 	ldr	x19, [sp, #16]
  100dc4:	a8c27bfd 	ldp	x29, x30, [sp], #32
  100dc8:	d65f03c0 	ret
  100dcc:	d503201f 	nop

0000000000100dd0 <transfer_bounded.constprop.0>:
  100dd0:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
  100dd4:	910003fd 	mov	x29, sp
  100dd8:	a90153f3 	stp	x19, x20, [sp, #16]
  100ddc:	f00000f3 	adrp	x19, 11f000 <XScuGic_ConfigTable+0xfa8>
  100de0:	91270273 	add	x19, x19, #0x9c0
  100de4:	a9025bf5 	stp	x21, x22, [sp, #32]
  100de8:	aa0103f4 	mov	x20, x1
  100dec:	2a0003f5 	mov	w21, w0
  100df0:	a90363f7 	stp	x23, x24, [sp, #48]
  100df4:	910163e0 	add	x0, sp, #0x58
  100df8:	aa0203f7 	mov	x23, x2
  100dfc:	a9046bf9 	stp	x25, x26, [sp, #64]
  100e00:	aa0403f8 	mov	x24, x4
  100e04:	aa0303f9 	mov	x25, x3
  100e08:	b9007a7f 	str	wzr, [x19, #120]
  100e0c:	b9007e7f 	str	wzr, [x19, #124]
  100e10:	b900827f 	str	wzr, [x19, #128]
  100e14:	9400063f 	bl	102710 <XTime_GetTime>
  100e18:	f9402fe0 	ldr	x0, [sp, #88]
  100e1c:	f9000280 	str	x0, [x20]
  100e20:	2a1503e3 	mov	w3, w21
  100e24:	d28e7d35 	mov	x21, #0x73e9                	// #29673
  100e28:	aa1303e0 	mov	x0, x19
  100e2c:	f00000e2 	adrp	x2, 11f000 <XScuGic_ConfigTable+0xfa8>
  100e30:	f0000161 	adrp	x1, 12f000 <rx+0xf570>
  100e34:	912a4042 	add	x2, x2, #0xa90
  100e38:	912a4021 	add	x1, x1, #0xa90
  100e3c:	f2a17d75 	movk	x21, #0xbeb, lsl #16
  100e40:	94000b7c 	bl	103c30 <XSpi_Transfer>
  100e44:	2a0003f6 	mov	w22, w0
  100e48:	34000100 	cbz	w0, 100e68 <transfer_bounded.constprop.0+0x98>
  100e4c:	14000021 	b	100ed0 <transfer_bounded.constprop.0+0x100>
  100e50:	94000630 	bl	102710 <XTime_GetTime>
  100e54:	f9400285 	ldr	x5, [x20]
  100e58:	f9402fe0 	ldr	x0, [sp, #88]
  100e5c:	cb050005 	sub	x5, x0, x5
  100e60:	eb1500bf 	cmp	x5, x21
  100e64:	54000248 	b.hi	100eac <transfer_bounded.constprop.0+0xdc>  // b.pmore
  100e68:	b9407a65 	ldr	w5, [x19, #120]
  100e6c:	910163e0 	add	x0, sp, #0x58
  100e70:	34ffff05 	cbz	w5, 100e50 <transfer_bounded.constprop.0+0x80>
  100e74:	94000627 	bl	102710 <XTime_GetTime>
  100e78:	f9402fe0 	ldr	x0, [sp, #88]
  100e7c:	f90002e0 	str	x0, [x23]
  100e80:	b9407e60 	ldr	w0, [x19, #124]
  100e84:	b9000320 	str	w0, [x25]
  100e88:	a9446bf9 	ldp	x25, x26, [sp, #64]
  100e8c:	b9408260 	ldr	w0, [x19, #128]
  100e90:	b9000300 	str	w0, [x24]
  100e94:	2a1603e0 	mov	w0, w22
  100e98:	a94153f3 	ldp	x19, x20, [sp, #16]
  100e9c:	a9425bf5 	ldp	x21, x22, [sp, #32]
  100ea0:	a94363f7 	ldp	x23, x24, [sp, #48]
  100ea4:	a8c67bfd 	ldp	x29, x30, [sp], #96
  100ea8:	d65f03c0 	ret
  100eac:	f90002e0 	str	x0, [x23]
  100eb0:	1284e276 	mov	w22, #0xffffd8ec            	// #-10004
  100eb4:	a94153f3 	ldp	x19, x20, [sp, #16]
  100eb8:	2a1603e0 	mov	w0, w22
  100ebc:	a9425bf5 	ldp	x21, x22, [sp, #32]
  100ec0:	a94363f7 	ldp	x23, x24, [sp, #48]
  100ec4:	a9446bf9 	ldp	x25, x26, [sp, #64]
  100ec8:	a8c67bfd 	ldp	x29, x30, [sp], #96
  100ecc:	d65f03c0 	ret
  100ed0:	910163e0 	add	x0, sp, #0x58
  100ed4:	9400060f 	bl	102710 <XTime_GetTime>
  100ed8:	f9402fe0 	ldr	x0, [sp, #88]
  100edc:	f90002e0 	str	x0, [x23]
  100ee0:	a94153f3 	ldp	x19, x20, [sp, #16]
  100ee4:	2a1603e0 	mov	w0, w22
  100ee8:	a9425bf5 	ldp	x21, x22, [sp, #32]
  100eec:	a94363f7 	ldp	x23, x24, [sp, #48]
  100ef0:	a9446bf9 	ldp	x25, x26, [sp, #64]
  100ef4:	a8c67bfd 	ldp	x29, x30, [sp], #96
  100ef8:	d65f03c0 	ret
  100efc:	d503201f 	nop

0000000000100f00 <prompt_uint.constprop.0>:
  100f00:	a9b97bfd 	stp	x29, x30, [sp, #-112]!
  100f04:	910003fd 	mov	x29, sp
  100f08:	a90153f3 	stp	x19, x20, [sp, #16]
  100f0c:	2a0103f4 	mov	w20, w1
  100f10:	910143f3 	add	x19, sp, #0x50
  100f14:	a9025bf5 	stp	x21, x22, [sp, #32]
  100f18:	900000b6 	adrp	x22, 114000 <main+0x9c0>
  100f1c:	2a0203f5 	mov	w21, w2
  100f20:	912882d6 	add	x22, x22, #0xa20
  100f24:	a90363f7 	stp	x23, x24, [sp, #48]
  100f28:	900000b8 	adrp	x24, 114000 <main+0x9c0>
  100f2c:	aa0003f7 	mov	x23, x0
  100f30:	91290318 	add	x24, x24, #0xa40
  100f34:	d503201f 	nop
  100f38:	2a1503e4 	mov	w4, w21
  100f3c:	2a1403e3 	mov	w3, w20
  100f40:	52800022 	mov	w2, #0x1                   	// #1
  100f44:	aa1703e1 	mov	x1, x23
  100f48:	aa1603e0 	mov	x0, x22
  100f4c:	94000279 	bl	101930 <xil_printf>
  100f50:	aa1303e0 	mov	x0, x19
  100f54:	52800401 	mov	w1, #0x20                  	// #32
  100f58:	97ffff2f 	bl	100c14 <read_line>
  100f5c:	394143e5 	ldrb	w5, [sp, #80]
  100f60:	910123e1 	add	x1, sp, #0x48
  100f64:	aa1303e0 	mov	x0, x19
  100f68:	52800142 	mov	w2, #0xa                   	// #10
  100f6c:	34000205 	cbz	w5, 100fac <prompt_uint.constprop.0+0xac>
  100f70:	94000ed8 	bl	104ad0 <strtoul>
  100f74:	aa0003e5 	mov	x5, x0
  100f78:	f94027e6 	ldr	x6, [sp, #72]
  100f7c:	aa1803e0 	mov	x0, x24
  100f80:	eb1300df 	cmp	x6, x19
  100f84:	540000a0 	b.eq	100f98 <prompt_uint.constprop.0+0x98>  // b.none
  100f88:	394000c1 	ldrb	w1, [x6]
  100f8c:	7100003f 	cmp	w1, #0x0
  100f90:	fa4008a4 	ccmp	x5, #0x0, #0x4, eq	// eq = none
  100f94:	54000061 	b.ne	100fa0 <prompt_uint.constprop.0+0xa0>  // b.any
  100f98:	94000266 	bl	101930 <xil_printf>
  100f9c:	17ffffe7 	b	100f38 <prompt_uint.constprop.0+0x38>
  100fa0:	eb3440bf 	cmp	x5, w20, uxtw
  100fa4:	54ffffa8 	b.hi	100f98 <prompt_uint.constprop.0+0x98>  // b.pmore
  100fa8:	2a0503f5 	mov	w21, w5
  100fac:	a94153f3 	ldp	x19, x20, [sp, #16]
  100fb0:	2a1503e0 	mov	w0, w21
  100fb4:	a9425bf5 	ldp	x21, x22, [sp, #32]
  100fb8:	a94363f7 	ldp	x23, x24, [sp, #48]
  100fbc:	a8c77bfd 	ldp	x29, x30, [sp], #112
  100fc0:	d65f03c0 	ret
	...

0000000000100fd0 <outnum1>:
  100fd0:	a9b77bfd 	stp	x29, x30, [sp, #-144]!
  100fd4:	b00000a3 	adrp	x3, 115000 <zeroes.0+0x5f0>
  100fd8:	910003fd 	mov	x29, sp
  100fdc:	a90153f3 	stp	x19, x20, [sp, #16]
  100fe0:	aa0203f4 	mov	x20, x2
  100fe4:	9111a062 	add	x2, x3, #0x468
  100fe8:	4f01e600 	movi	v0.16b, #0x30
  100fec:	9100e3e7 	add	x7, sp, #0x38
  100ff0:	b9401a83 	ldr	w3, [x20, #24]
  100ff4:	a9401444 	ldp	x4, x5, [x2]
  100ff8:	a9025bf5 	stp	x21, x22, [sp, #32]
  100ffc:	39404042 	ldrb	w2, [x2, #16]
  101000:	390040e2 	strb	w2, [x7, #16]
  101004:	a90397e4 	stp	x4, x5, [sp, #56]
  101008:	ad0283e0 	stp	q0, q0, [sp, #80]
  10100c:	ad0383e0 	stp	q0, q0, [sp, #112]
  101010:	35000083 	cbnz	w3, 101020 <outnum1+0x50>
  101014:	f100001f 	cmp	x0, #0x0
  101018:	7a4ab820 	ccmp	w1, #0xa, #0x0, lt	// lt = tstop
  10101c:	540005e0 	b.eq	1010d8 <outnum1+0x108>  // b.none
  101020:	52800008 	mov	w8, #0x0                   	// #0
  101024:	910143f5 	add	x21, sp, #0x50
  101028:	93407c21 	sxtw	x1, w1
  10102c:	aa1503e4 	mov	x4, x21
  101030:	52800003 	mov	w3, #0x0                   	// #0
  101034:	d503201f 	nop
  101038:	9ac10802 	udiv	x2, x0, x1
  10103c:	aa0003e5 	mov	x5, x0
  101040:	2a0303f3 	mov	w19, w3
  101044:	11000463 	add	w3, w3, #0x1
  101048:	9b018046 	msub	x6, x2, x1, x0
  10104c:	aa0203e0 	mov	x0, x2
  101050:	386668e2 	ldrb	w2, [x7, x6]
  101054:	38001482 	strb	w2, [x4], #1
  101058:	eb0100bf 	cmp	x5, x1
  10105c:	54fffee2 	b.cs	101038 <outnum1+0x68>  // b.hs, b.nlast
  101060:	340000c8 	cbz	w8, 101078 <outnum1+0xa8>
  101064:	11000a60 	add	w0, w19, #0x2
  101068:	528005a1 	mov	w1, #0x2d                  	// #45
  10106c:	2a0303f3 	mov	w19, w3
  101070:	3823caa1 	strb	w1, [x21, w3, sxtw]
  101074:	2a0003e3 	mov	w3, w0
  101078:	aa1503e0 	mov	x0, x21
  10107c:	3823cabf 	strb	wzr, [x21, w3, sxtw]
  101080:	940011b0 	bl	105740 <strlen>
  101084:	b9000280 	str	w0, [x20]
  101088:	29420682 	ldp	w2, w1, [x20, #16]
  10108c:	2a0003f6 	mov	w22, w0
  101090:	7100005f 	cmp	w2, #0x0
  101094:	7a401820 	ccmp	w1, #0x0, #0x0, ne	// ne = any
  101098:	54000460 	b.eq	101124 <outnum1+0x154>  // b.none
  10109c:	8b33c2b3 	add	x19, x21, w19, sxtw
  1010a0:	d10006b5 	sub	x21, x21, #0x1
  1010a4:	d503201f 	nop
  1010a8:	385ff660 	ldrb	w0, [x19], #-1
  1010ac:	94000df1 	bl	104870 <outbyte>
  1010b0:	eb1302bf 	cmp	x21, x19
  1010b4:	54ffffa1 	b.ne	1010a8 <outnum1+0xd8>  // b.any
  1010b8:	29420281 	ldp	w1, w0, [x20, #16]
  1010bc:	7100003f 	cmp	w1, #0x0
  1010c0:	7a401804 	ccmp	w0, #0x0, #0x4, ne	// ne = any
  1010c4:	54000101 	b.ne	1010e4 <outnum1+0x114>  // b.any
  1010c8:	a94153f3 	ldp	x19, x20, [sp, #16]
  1010cc:	a9425bf5 	ldp	x21, x22, [sp, #32]
  1010d0:	a8c97bfd 	ldp	x29, x30, [sp], #144
  1010d4:	d65f03c0 	ret
  1010d8:	cb0003e0 	neg	x0, x0
  1010dc:	52800028 	mov	w8, #0x1                   	// #1
  1010e0:	17ffffd1 	b	101024 <outnum1+0x54>
  1010e4:	29400293 	ldp	w19, w0, [x20]
  1010e8:	6b00027f 	cmp	w19, w0
  1010ec:	54fffeea 	b.ge	1010c8 <outnum1+0xf8>  // b.tcont
  1010f0:	39403280 	ldrb	w0, [x20, #12]
  1010f4:	11000673 	add	w19, w19, #0x1
  1010f8:	94000dde 	bl	104870 <outbyte>
  1010fc:	b9400680 	ldr	w0, [x20, #4]
  101100:	6b00027f 	cmp	w19, w0
  101104:	54fffe2a 	b.ge	1010c8 <outnum1+0xf8>  // b.tcont
  101108:	39403280 	ldrb	w0, [x20, #12]
  10110c:	11000673 	add	w19, w19, #0x1
  101110:	94000dd8 	bl	104870 <outbyte>
  101114:	b9400680 	ldr	w0, [x20, #4]
  101118:	6b00027f 	cmp	w19, w0
  10111c:	54fffeab 	b.lt	1010f0 <outnum1+0x120>  // b.tstop
  101120:	17ffffea 	b	1010c8 <outnum1+0xf8>
  101124:	b9400681 	ldr	w1, [x20, #4]
  101128:	6b01001f 	cmp	w0, w1
  10112c:	54fffb8a 	b.ge	10109c <outnum1+0xcc>  // b.tcont
  101130:	39403280 	ldrb	w0, [x20, #12]
  101134:	110006d6 	add	w22, w22, #0x1
  101138:	94000dce 	bl	104870 <outbyte>
  10113c:	b9400680 	ldr	w0, [x20, #4]
  101140:	6b0002df 	cmp	w22, w0
  101144:	54fffaca 	b.ge	10109c <outnum1+0xcc>  // b.tcont
  101148:	39403280 	ldrb	w0, [x20, #12]
  10114c:	110006d6 	add	w22, w22, #0x1
  101150:	94000dc8 	bl	104870 <outbyte>
  101154:	b9400680 	ldr	w0, [x20, #4]
  101158:	6b0002df 	cmp	w22, w0
  10115c:	54fffeab 	b.lt	101130 <outnum1+0x160>  // b.tstop
  101160:	17ffffcf 	b	10109c <outnum1+0xcc>

0000000000101164 <outnum>:
  101164:	a9b97bfd 	stp	x29, x30, [sp, #-112]!
  101168:	900000a3 	adrp	x3, 115000 <zeroes.0+0x5f0>
  10116c:	910003fd 	mov	x29, sp
  101170:	a90153f3 	stp	x19, x20, [sp, #16]
  101174:	aa0203f4 	mov	x20, x2
  101178:	9111a062 	add	x2, x3, #0x468
  10117c:	4f01e600 	movi	v0.16b, #0x30
  101180:	9100e3e7 	add	x7, sp, #0x38
  101184:	b9401a83 	ldr	w3, [x20, #24]
  101188:	a9401444 	ldp	x4, x5, [x2]
  10118c:	a9025bf5 	stp	x21, x22, [sp, #32]
  101190:	39404042 	ldrb	w2, [x2, #16]
  101194:	390040e2 	strb	w2, [x7, #16]
  101198:	a90397e4 	stp	x4, x5, [sp, #56]
  10119c:	ad0283e0 	stp	q0, q0, [sp, #80]
  1011a0:	35000083 	cbnz	w3, 1011b0 <outnum+0x4c>
  1011a4:	7100001f 	cmp	w0, #0x0
  1011a8:	7a4ab820 	ccmp	w1, #0xa, #0x0, lt	// lt = tstop
  1011ac:	540005a0 	b.eq	101260 <outnum+0xfc>  // b.none
  1011b0:	52800008 	mov	w8, #0x0                   	// #0
  1011b4:	910143f5 	add	x21, sp, #0x50
  1011b8:	52800003 	mov	w3, #0x0                   	// #0
  1011bc:	aa1503e2 	mov	x2, x21
  1011c0:	1ac10804 	udiv	w4, w0, w1
  1011c4:	2a0003e5 	mov	w5, w0
  1011c8:	2a0303f3 	mov	w19, w3
  1011cc:	11000463 	add	w3, w3, #0x1
  1011d0:	1b018086 	msub	w6, w4, w1, w0
  1011d4:	2a0403e0 	mov	w0, w4
  1011d8:	386648e4 	ldrb	w4, [x7, w6, uxtw]
  1011dc:	38001444 	strb	w4, [x2], #1
  1011e0:	6b0100bf 	cmp	w5, w1
  1011e4:	54fffee2 	b.cs	1011c0 <outnum+0x5c>  // b.hs, b.nlast
  1011e8:	340000c8 	cbz	w8, 101200 <outnum+0x9c>
  1011ec:	11000a60 	add	w0, w19, #0x2
  1011f0:	528005a1 	mov	w1, #0x2d                  	// #45
  1011f4:	2a0303f3 	mov	w19, w3
  1011f8:	3823caa1 	strb	w1, [x21, w3, sxtw]
  1011fc:	2a0003e3 	mov	w3, w0
  101200:	aa1503e0 	mov	x0, x21
  101204:	3823cabf 	strb	wzr, [x21, w3, sxtw]
  101208:	9400114e 	bl	105740 <strlen>
  10120c:	b9000280 	str	w0, [x20]
  101210:	29420682 	ldp	w2, w1, [x20, #16]
  101214:	2a0003f6 	mov	w22, w0
  101218:	7100005f 	cmp	w2, #0x0
  10121c:	7a401820 	ccmp	w1, #0x0, #0x0, ne	// ne = any
  101220:	54000460 	b.eq	1012ac <outnum+0x148>  // b.none
  101224:	8b33c2b3 	add	x19, x21, w19, sxtw
  101228:	d10006b5 	sub	x21, x21, #0x1
  10122c:	d503201f 	nop
  101230:	385ff660 	ldrb	w0, [x19], #-1
  101234:	94000d8f 	bl	104870 <outbyte>
  101238:	eb15027f 	cmp	x19, x21
  10123c:	54ffffa1 	b.ne	101230 <outnum+0xcc>  // b.any
  101240:	29420281 	ldp	w1, w0, [x20, #16]
  101244:	7100003f 	cmp	w1, #0x0
  101248:	7a401804 	ccmp	w0, #0x0, #0x4, ne	// ne = any
  10124c:	54000101 	b.ne	10126c <outnum+0x108>  // b.any
  101250:	a94153f3 	ldp	x19, x20, [sp, #16]
  101254:	a9425bf5 	ldp	x21, x22, [sp, #32]
  101258:	a8c77bfd 	ldp	x29, x30, [sp], #112
  10125c:	d65f03c0 	ret
  101260:	4b0003e0 	neg	w0, w0
  101264:	52800028 	mov	w8, #0x1                   	// #1
  101268:	17ffffd3 	b	1011b4 <outnum+0x50>
  10126c:	29400293 	ldp	w19, w0, [x20]
  101270:	6b00027f 	cmp	w19, w0
  101274:	54fffeea 	b.ge	101250 <outnum+0xec>  // b.tcont
  101278:	39403280 	ldrb	w0, [x20, #12]
  10127c:	11000673 	add	w19, w19, #0x1
  101280:	94000d7c 	bl	104870 <outbyte>
  101284:	b9400680 	ldr	w0, [x20, #4]
  101288:	6b00027f 	cmp	w19, w0
  10128c:	54fffe2a 	b.ge	101250 <outnum+0xec>  // b.tcont
  101290:	39403280 	ldrb	w0, [x20, #12]
  101294:	11000673 	add	w19, w19, #0x1
  101298:	94000d76 	bl	104870 <outbyte>
  10129c:	b9400680 	ldr	w0, [x20, #4]
  1012a0:	6b00027f 	cmp	w19, w0
  1012a4:	54fffeab 	b.lt	101278 <outnum+0x114>  // b.tstop
  1012a8:	17ffffea 	b	101250 <outnum+0xec>
  1012ac:	b9400681 	ldr	w1, [x20, #4]
  1012b0:	6b01001f 	cmp	w0, w1
  1012b4:	54fffb8a 	b.ge	101224 <outnum+0xc0>  // b.tcont
  1012b8:	39403280 	ldrb	w0, [x20, #12]
  1012bc:	110006d6 	add	w22, w22, #0x1
  1012c0:	94000d6c 	bl	104870 <outbyte>
  1012c4:	b9400680 	ldr	w0, [x20, #4]
  1012c8:	6b0002df 	cmp	w22, w0
  1012cc:	54fffaca 	b.ge	101224 <outnum+0xc0>  // b.tcont
  1012d0:	39403280 	ldrb	w0, [x20, #12]
  1012d4:	110006d6 	add	w22, w22, #0x1
  1012d8:	94000d66 	bl	104870 <outbyte>
  1012dc:	b9400680 	ldr	w0, [x20, #4]
  1012e0:	6b0002df 	cmp	w22, w0
  1012e4:	54fffeab 	b.lt	1012b8 <outnum+0x154>  // b.tstop
  1012e8:	17ffffcf 	b	101224 <outnum+0xc0>
  1012ec:	d503201f 	nop

00000000001012f0 <xil_vprintf>:
  1012f0:	a9b77bfd 	stp	x29, x30, [sp, #-144]!
  1012f4:	910003fd 	mov	x29, sp
  1012f8:	a90153f3 	stp	x19, x20, [sp, #16]
  1012fc:	aa0003f4 	mov	x20, x0
  101300:	a9025bf5 	stp	x21, x22, [sp, #32]
  101304:	b9401836 	ldr	w22, [x1, #24]
  101308:	a9400035 	ldp	x21, x0, [x1]
  10130c:	f90033e0 	str	x0, [sp, #96]
  101310:	b40005f4 	cbz	x20, 1013cc <xil_vprintf+0xdc>
  101314:	39400280 	ldrb	w0, [x20]
  101318:	340005a0 	cbz	w0, 1013cc <xil_vprintf+0xdc>
  10131c:	a90363f7 	stp	x23, x24, [sp, #48]
  101320:	f0000097 	adrp	x23, 114000 <main+0x9c0>
  101324:	9115b2f7 	add	x23, x23, #0x56c
  101328:	a9046bf9 	stp	x25, x26, [sp, #64]
  10132c:	f0000099 	adrp	x25, 114000 <main+0x9c0>
  101330:	9117c739 	add	x25, x25, #0x5f1
  101334:	a90573fb 	stp	x27, x28, [sp, #80]
  101338:	14000005 	b	10134c <xil_vprintf+0x5c>
  10133c:	91000694 	add	x20, x20, #0x1
  101340:	94000d4c 	bl	104870 <outbyte>
  101344:	39400280 	ldrb	w0, [x20]
  101348:	340003c0 	cbz	w0, 1013c0 <xil_vprintf+0xd0>
  10134c:	7100941f 	cmp	w0, #0x25
  101350:	54ffff61 	b.ne	10133c <xil_vprintf+0x4c>  // b.any
  101354:	39400681 	ldrb	w1, [x20, #1]
  101358:	5280003a 	mov	w26, #0x1                   	// #1
  10135c:	2a1a03fb 	mov	w27, w26
  101360:	52800400 	mov	w0, #0x20                  	// #32
  101364:	528fffe2 	mov	w2, #0x7fff                	// #32767
  101368:	52800018 	mov	w24, #0x0                   	// #0
  10136c:	5280001c 	mov	w28, #0x0                   	// #0
  101370:	f9003bff 	str	xzr, [sp, #112]
  101374:	b9007be2 	str	w2, [sp, #120]
  101378:	3901f3e0 	strb	w0, [sp, #124]
  10137c:	f90043ff 	str	xzr, [sp, #128]
  101380:	b9008bff 	str	wzr, [sp, #136]
  101384:	d503201f 	nop
  101388:	38614b20 	ldrb	w0, [x25, w1, uxtw]
  10138c:	91000693 	add	x19, x20, #0x1
  101390:	37100740 	tbnz	w0, #2, 101478 <xil_vprintf+0x188>
  101394:	12000402 	and	w2, w0, #0x3
  101398:	11008020 	add	w0, w1, #0x20
  10139c:	7100045f 	cmp	w2, #0x1
  1013a0:	1a810000 	csel	w0, w0, w1, eq	// eq = none
  1013a4:	51009400 	sub	w0, w0, #0x25
  1013a8:	71014c1f 	cmp	w0, #0x53
  1013ac:	54000189 	b.ls	1013dc <xil_vprintf+0xec>  // b.plast
  1013b0:	91000674 	add	x20, x19, #0x1
  1013b4:	d503201f 	nop
  1013b8:	39400280 	ldrb	w0, [x20]
  1013bc:	35fffc80 	cbnz	w0, 10134c <xil_vprintf+0x5c>
  1013c0:	a94363f7 	ldp	x23, x24, [sp, #48]
  1013c4:	a9446bf9 	ldp	x25, x26, [sp, #64]
  1013c8:	a94573fb 	ldp	x27, x28, [sp, #80]
  1013cc:	a94153f3 	ldp	x19, x20, [sp, #16]
  1013d0:	a9425bf5 	ldp	x21, x22, [sp, #32]
  1013d4:	a8c97bfd 	ldp	x29, x30, [sp], #144
  1013d8:	d65f03c0 	ret
  1013dc:	38604ae0 	ldrb	w0, [x23, w0, uxtw]
  1013e0:	10000061 	adr	x1, 1013ec <xil_vprintf+0xfc>
  1013e4:	8b208820 	add	x0, x1, w0, sxtb #2
  1013e8:	d61f0000 	br	x0
  1013ec:	52800020 	mov	w0, #0x1                   	// #1
  1013f0:	b9008be0 	str	w0, [sp, #136]
  1013f4:	3400141c 	cbz	w28, 101674 <xil_vprintf+0x384>
  1013f8:	37f81776 	tbnz	w22, #31, 1016e4 <xil_vprintf+0x3f4>
  1013fc:	91003ea1 	add	x1, x21, #0xf
  101400:	aa1503e0 	mov	x0, x21
  101404:	927df035 	and	x21, x1, #0xfffffffffffffff8
  101408:	f9400000 	ldr	x0, [x0]
  10140c:	9101c3e2 	add	x2, sp, #0x70
  101410:	52800141 	mov	w1, #0xa                   	// #10
  101414:	91000674 	add	x20, x19, #0x1
  101418:	97fffeee 	bl	100fd0 <outnum1>
  10141c:	17ffffe7 	b	1013b8 <xil_vprintf+0xc8>
  101420:	52800020 	mov	w0, #0x1                   	// #1
  101424:	b9008be0 	str	w0, [sp, #136]
  101428:	340013bc 	cbz	w28, 10169c <xil_vprintf+0x3ac>
  10142c:	37f80896 	tbnz	w22, #31, 10153c <xil_vprintf+0x24c>
  101430:	91003ea1 	add	x1, x21, #0xf
  101434:	aa1503e0 	mov	x0, x21
  101438:	927df035 	and	x21, x1, #0xfffffffffffffff8
  10143c:	f9400000 	ldr	x0, [x0]
  101440:	9101c3e2 	add	x2, sp, #0x70
  101444:	52800201 	mov	w1, #0x10                  	// #16
  101448:	91000674 	add	x20, x19, #0x1
  10144c:	97fffee1 	bl	100fd0 <outnum1>
  101450:	17ffffda 	b	1013b8 <xil_vprintf+0xc8>
  101454:	39400a81 	ldrb	w1, [x20, #2]
  101458:	7100a83f 	cmp	w1, #0x2a
  10145c:	54000e00 	b.eq	10161c <xil_vprintf+0x32c>  // b.none
  101460:	38614b20 	ldrb	w0, [x25, w1, uxtw]
  101464:	aa1303f4 	mov	x20, x19
  101468:	91000693 	add	x19, x20, #0x1
  10146c:	52800038 	mov	w24, #0x1                   	// #1
  101470:	5280001a 	mov	w26, #0x0                   	// #0
  101474:	3617f900 	tbz	w0, #2, 101394 <xil_vprintf+0xa4>
  101478:	35000e58 	cbnz	w24, 101640 <xil_vprintf+0x350>
  10147c:	7100c03f 	cmp	w1, #0x30
  101480:	54000ca0 	b.eq	101614 <xil_vprintf+0x324>  // b.none
  101484:	52800002 	mov	w2, #0x0                   	// #0
  101488:	5100c020 	sub	w0, w1, #0x30
  10148c:	aa1303f4 	mov	x20, x19
  101490:	38401e61 	ldrb	w1, [x19, #1]!
  101494:	0b020842 	add	w2, w2, w2, lsl #2
  101498:	0b020402 	add	w2, w0, w2, lsl #1
  10149c:	38614b20 	ldrb	w0, [x25, w1, uxtw]
  1014a0:	3717ff40 	tbnz	w0, #2, 101488 <xil_vprintf+0x198>
  1014a4:	39400261 	ldrb	w1, [x19]
  1014a8:	b90077e2 	str	w2, [sp, #116]
  1014ac:	b90083fb 	str	w27, [sp, #128]
  1014b0:	17ffffb6 	b	101388 <xil_vprintf+0x98>
  1014b4:	37f81296 	tbnz	w22, #31, 101704 <xil_vprintf+0x414>
  1014b8:	91003eba 	add	x26, x21, #0xf
  1014bc:	927df35a 	and	x26, x26, #0xfffffffffffffff8
  1014c0:	f94002bc 	ldr	x28, [x21]
  1014c4:	b94083e0 	ldr	w0, [sp, #128]
  1014c8:	b94087f5 	ldr	w21, [sp, #132]
  1014cc:	7100001f 	cmp	w0, #0x0
  1014d0:	1a9f07fb 	cset	w27, ne	// ne = any
  1014d4:	b400023c 	cbz	x28, 101518 <xil_vprintf+0x228>
  1014d8:	aa1c03e0 	mov	x0, x28
  1014dc:	94001099 	bl	105740 <strlen>
  1014e0:	b90073e0 	str	w0, [sp, #112]
  1014e4:	710002bf 	cmp	w21, #0x0
  1014e8:	7a400b64 	ccmp	w27, #0x0, #0x4, eq	// eq = none
  1014ec:	2a0003f4 	mov	w20, w0
  1014f0:	54001961 	b.ne	10181c <xil_vprintf+0x52c>  // b.any
  1014f4:	39400380 	ldrb	w0, [x28]
  1014f8:	34000100 	cbz	w0, 101518 <xil_vprintf+0x228>
  1014fc:	b9407bf4 	ldr	w20, [sp, #120]
  101500:	340000d4 	cbz	w20, 101518 <xil_vprintf+0x228>
  101504:	51000694 	sub	w20, w20, #0x1
  101508:	b9007bf4 	str	w20, [sp, #120]
  10150c:	94000cd9 	bl	104870 <outbyte>
  101510:	38401f80 	ldrb	w0, [x28, #1]!
  101514:	35ffff60 	cbnz	w0, 101500 <xil_vprintf+0x210>
  101518:	710002bf 	cmp	w21, #0x0
  10151c:	7a401b64 	ccmp	w27, #0x0, #0x4, ne	// ne = any
  101520:	54001201 	b.ne	101760 <xil_vprintf+0x470>  // b.any
  101524:	aa1a03f5 	mov	x21, x26
  101528:	91000674 	add	x20, x19, #0x1
  10152c:	17ffffa3 	b	1013b8 <xil_vprintf+0xc8>
  101530:	52800020 	mov	w0, #0x1                   	// #1
  101534:	b9008be0 	str	w0, [sp, #136]
  101538:	36fff7d6 	tbz	w22, #31, 101430 <xil_vprintf+0x140>
  10153c:	110022c1 	add	w1, w22, #0x8
  101540:	7100003f 	cmp	w1, #0x0
  101544:	5400148d 	b.le	1017d4 <xil_vprintf+0x4e4>
  101548:	91003ea2 	add	x2, x21, #0xf
  10154c:	aa1503e0 	mov	x0, x21
  101550:	2a0103f6 	mov	w22, w1
  101554:	927df055 	and	x21, x2, #0xfffffffffffffff8
  101558:	17ffffb9 	b	10143c <xil_vprintf+0x14c>
  10155c:	39400a81 	ldrb	w1, [x20, #2]
  101560:	5280003c 	mov	w28, #0x1                   	// #1
  101564:	aa1303f4 	mov	x20, x19
  101568:	5280001a 	mov	w26, #0x0                   	// #0
  10156c:	17ffff87 	b	101388 <xil_vprintf+0x98>
  101570:	39400a81 	ldrb	w1, [x20, #2]
  101574:	52800020 	mov	w0, #0x1                   	// #1
  101578:	aa1303f4 	mov	x20, x19
  10157c:	5280001a 	mov	w26, #0x0                   	// #0
  101580:	b90087e0 	str	w0, [sp, #132]
  101584:	17ffff81 	b	101388 <xil_vprintf+0x98>
  101588:	528004a0 	mov	w0, #0x25                  	// #37
  10158c:	91000674 	add	x20, x19, #0x1
  101590:	94000cb8 	bl	104870 <outbyte>
  101594:	17ffff89 	b	1013b8 <xil_vprintf+0xc8>
  101598:	37f80976 	tbnz	w22, #31, 1016c4 <xil_vprintf+0x3d4>
  10159c:	91002ea1 	add	x1, x21, #0xb
  1015a0:	aa1503e0 	mov	x0, x21
  1015a4:	927df035 	and	x21, x1, #0xfffffffffffffff8
  1015a8:	39400000 	ldrb	w0, [x0]
  1015ac:	91000674 	add	x20, x19, #0x1
  1015b0:	94000cb0 	bl	104870 <outbyte>
  1015b4:	17ffff81 	b	1013b8 <xil_vprintf+0xc8>
  1015b8:	39400a80 	ldrb	w0, [x20, #2]
  1015bc:	91000a93 	add	x19, x20, #0x2
  1015c0:	7101b81f 	cmp	w0, #0x6e
  1015c4:	54000180 	b.eq	1015f4 <xil_vprintf+0x304>  // b.none
  1015c8:	54000bc8 	b.hi	101740 <xil_vprintf+0x450>  // b.pmore
  1015cc:	7101841f 	cmp	w0, #0x61
  1015d0:	540011a0 	b.eq	101804 <xil_vprintf+0x514>  // b.none
  1015d4:	7101a01f 	cmp	w0, #0x68
  1015d8:	54000141 	b.ne	101600 <xil_vprintf+0x310>  // b.any
  1015dc:	52800100 	mov	w0, #0x8                   	// #8
  1015e0:	94000ca4 	bl	104870 <outbyte>
  1015e4:	39400e81 	ldrb	w1, [x20, #3]
  1015e8:	5280001a 	mov	w26, #0x0                   	// #0
  1015ec:	aa1303f4 	mov	x20, x19
  1015f0:	17ffff66 	b	101388 <xil_vprintf+0x98>
  1015f4:	528001a0 	mov	w0, #0xd                   	// #13
  1015f8:	94000c9e 	bl	104870 <outbyte>
  1015fc:	52800140 	mov	w0, #0xa                   	// #10
  101600:	94000c9c 	bl	104870 <outbyte>
  101604:	5280001a 	mov	w26, #0x0                   	// #0
  101608:	39400e81 	ldrb	w1, [x20, #3]
  10160c:	aa1303f4 	mov	x20, x19
  101610:	17ffff5e 	b	101388 <xil_vprintf+0x98>
  101614:	3901f3e1 	strb	w1, [sp, #124]
  101618:	17ffff9b 	b	101484 <xil_vprintf+0x194>
  10161c:	39400e80 	ldrb	w0, [x20, #3]
  101620:	7101cc1f 	cmp	w0, #0x73
  101624:	54001220 	b.eq	101868 <xil_vprintf+0x578>  // b.none
  101628:	f0000080 	adrp	x0, 114000 <main+0x9c0>
  10162c:	91000a93 	add	x19, x20, #0x2
  101630:	39586c00 	ldrb	w0, [x0, #1563]
  101634:	3617ebe0 	tbz	w0, #2, 1013b0 <xil_vprintf+0xc0>
  101638:	5280001a 	mov	w26, #0x0                   	// #0
  10163c:	d503201f 	nop
  101640:	52800000 	mov	w0, #0x0                   	// #0
  101644:	d503201f 	nop
  101648:	5100c022 	sub	w2, w1, #0x30
  10164c:	aa1303f4 	mov	x20, x19
  101650:	38401e61 	ldrb	w1, [x19, #1]!
  101654:	0b000800 	add	w0, w0, w0, lsl #2
  101658:	0b000440 	add	w0, w2, w0, lsl #1
  10165c:	38614b22 	ldrb	w2, [x25, w1, uxtw]
  101660:	3717ff42 	tbnz	w2, #2, 101648 <xil_vprintf+0x358>
  101664:	39400261 	ldrb	w1, [x19]
  101668:	52800038 	mov	w24, #0x1                   	// #1
  10166c:	b9007be0 	str	w0, [sp, #120]
  101670:	17ffff46 	b	101388 <xil_vprintf+0x98>
  101674:	37f80576 	tbnz	w22, #31, 101720 <xil_vprintf+0x430>
  101678:	91002ea1 	add	x1, x21, #0xb
  10167c:	aa1503e0 	mov	x0, x21
  101680:	927df035 	and	x21, x1, #0xfffffffffffffff8
  101684:	b9400000 	ldr	w0, [x0]
  101688:	9101c3e2 	add	x2, sp, #0x70
  10168c:	52800141 	mov	w1, #0xa                   	// #10
  101690:	91000674 	add	x20, x19, #0x1
  101694:	97fffeb4 	bl	101164 <outnum>
  101698:	17ffff48 	b	1013b8 <xil_vprintf+0xc8>
  10169c:	37f80a56 	tbnz	w22, #31, 1017e4 <xil_vprintf+0x4f4>
  1016a0:	91002ea1 	add	x1, x21, #0xb
  1016a4:	aa1503e0 	mov	x0, x21
  1016a8:	927df035 	and	x21, x1, #0xfffffffffffffff8
  1016ac:	b9400000 	ldr	w0, [x0]
  1016b0:	9101c3e2 	add	x2, sp, #0x70
  1016b4:	52800201 	mov	w1, #0x10                  	// #16
  1016b8:	91000674 	add	x20, x19, #0x1
  1016bc:	97fffeaa 	bl	101164 <outnum>
  1016c0:	17ffff3e 	b	1013b8 <xil_vprintf+0xc8>
  1016c4:	110022c1 	add	w1, w22, #0x8
  1016c8:	7100003f 	cmp	w1, #0x0
  1016cc:	5400060d 	b.le	10178c <xil_vprintf+0x49c>
  1016d0:	91002ea2 	add	x2, x21, #0xb
  1016d4:	aa1503e0 	mov	x0, x21
  1016d8:	2a0103f6 	mov	w22, w1
  1016dc:	927df055 	and	x21, x2, #0xfffffffffffffff8
  1016e0:	17ffffb2 	b	1015a8 <xil_vprintf+0x2b8>
  1016e4:	110022c1 	add	w1, w22, #0x8
  1016e8:	7100003f 	cmp	w1, #0x0
  1016ec:	540006cd 	b.le	1017c4 <xil_vprintf+0x4d4>
  1016f0:	91003ea2 	add	x2, x21, #0xf
  1016f4:	aa1503e0 	mov	x0, x21
  1016f8:	2a0103f6 	mov	w22, w1
  1016fc:	927df055 	and	x21, x2, #0xfffffffffffffff8
  101700:	17ffff42 	b	101408 <xil_vprintf+0x118>
  101704:	110022c0 	add	w0, w22, #0x8
  101708:	7100001f 	cmp	w0, #0x0
  10170c:	5400050d 	b.le	1017ac <xil_vprintf+0x4bc>
  101710:	91003eba 	add	x26, x21, #0xf
  101714:	2a0003f6 	mov	w22, w0
  101718:	927df35a 	and	x26, x26, #0xfffffffffffffff8
  10171c:	17ffff69 	b	1014c0 <xil_vprintf+0x1d0>
  101720:	110022c1 	add	w1, w22, #0x8
  101724:	7100003f 	cmp	w1, #0x0
  101728:	540003ad 	b.le	10179c <xil_vprintf+0x4ac>
  10172c:	91002ea2 	add	x2, x21, #0xb
  101730:	aa1503e0 	mov	x0, x21
  101734:	2a0103f6 	mov	w22, w1
  101738:	927df055 	and	x21, x2, #0xfffffffffffffff8
  10173c:	17ffffd2 	b	101684 <xil_vprintf+0x394>
  101740:	7101c81f 	cmp	w0, #0x72
  101744:	54fff5e1 	b.ne	101600 <xil_vprintf+0x310>  // b.any
  101748:	528001a0 	mov	w0, #0xd                   	// #13
  10174c:	94000c49 	bl	104870 <outbyte>
  101750:	39400e81 	ldrb	w1, [x20, #3]
  101754:	5280001a 	mov	w26, #0x0                   	// #0
  101758:	aa1303f4 	mov	x20, x19
  10175c:	17ffff0b 	b	101388 <xil_vprintf+0x98>
  101760:	294e57f4 	ldp	w20, w21, [sp, #112]
  101764:	6b15029f 	cmp	w20, w21
  101768:	54ffedea 	b.ge	101524 <xil_vprintf+0x234>  // b.tcont
  10176c:	3941f3fb 	ldrb	w27, [sp, #124]
  101770:	2a1b03e0 	mov	w0, w27
  101774:	11000694 	add	w20, w20, #0x1
  101778:	94000c3e 	bl	104870 <outbyte>
  10177c:	6b1402bf 	cmp	w21, w20
  101780:	54ffff81 	b.ne	101770 <xil_vprintf+0x480>  // b.any
  101784:	aa1a03f5 	mov	x21, x26
  101788:	17ffff68 	b	101528 <xil_vprintf+0x238>
  10178c:	f94033e0 	ldr	x0, [sp, #96]
  101790:	8b36c000 	add	x0, x0, w22, sxtw
  101794:	2a0103f6 	mov	w22, w1
  101798:	17ffff84 	b	1015a8 <xil_vprintf+0x2b8>
  10179c:	f94033e0 	ldr	x0, [sp, #96]
  1017a0:	8b36c000 	add	x0, x0, w22, sxtw
  1017a4:	2a0103f6 	mov	w22, w1
  1017a8:	17ffffb7 	b	101684 <xil_vprintf+0x394>
  1017ac:	f94033e1 	ldr	x1, [sp, #96]
  1017b0:	aa1503fa 	mov	x26, x21
  1017b4:	8b36c021 	add	x1, x1, w22, sxtw
  1017b8:	2a0003f6 	mov	w22, w0
  1017bc:	aa0103f5 	mov	x21, x1
  1017c0:	17ffff40 	b	1014c0 <xil_vprintf+0x1d0>
  1017c4:	f94033e0 	ldr	x0, [sp, #96]
  1017c8:	8b36c000 	add	x0, x0, w22, sxtw
  1017cc:	2a0103f6 	mov	w22, w1
  1017d0:	17ffff0e 	b	101408 <xil_vprintf+0x118>
  1017d4:	f94033e0 	ldr	x0, [sp, #96]
  1017d8:	8b36c000 	add	x0, x0, w22, sxtw
  1017dc:	2a0103f6 	mov	w22, w1
  1017e0:	17ffff17 	b	10143c <xil_vprintf+0x14c>
  1017e4:	110022c1 	add	w1, w22, #0x8
  1017e8:	7100003f 	cmp	w1, #0x0
  1017ec:	5400036d 	b.le	101858 <xil_vprintf+0x568>
  1017f0:	91002ea2 	add	x2, x21, #0xb
  1017f4:	aa1503e0 	mov	x0, x21
  1017f8:	2a0103f6 	mov	w22, w1
  1017fc:	927df055 	and	x21, x2, #0xfffffffffffffff8
  101800:	17ffffab 	b	1016ac <xil_vprintf+0x3bc>
  101804:	528000e0 	mov	w0, #0x7                   	// #7
  101808:	94000c1a 	bl	104870 <outbyte>
  10180c:	39400e81 	ldrb	w1, [x20, #3]
  101810:	5280001a 	mov	w26, #0x0                   	// #0
  101814:	aa1303f4 	mov	x20, x19
  101818:	17fffedc 	b	101388 <xil_vprintf+0x98>
  10181c:	b94077e1 	ldr	w1, [sp, #116]
  101820:	b9006be1 	str	w1, [sp, #104]
  101824:	6b01001f 	cmp	w0, w1
  101828:	5400010a 	b.ge	101848 <xil_vprintf+0x558>  // b.tcont
  10182c:	3941f3f8 	ldrb	w24, [sp, #124]
  101830:	2a1803e0 	mov	w0, w24
  101834:	94000c0f 	bl	104870 <outbyte>
  101838:	b9406be0 	ldr	w0, [sp, #104]
  10183c:	11000694 	add	w20, w20, #0x1
  101840:	6b14001f 	cmp	w0, w20
  101844:	54ffff61 	b.ne	101830 <xil_vprintf+0x540>  // b.any
  101848:	39400380 	ldrb	w0, [x28]
  10184c:	34ffe6c0 	cbz	w0, 101524 <xil_vprintf+0x234>
  101850:	b9407bf4 	ldr	w20, [sp, #120]
  101854:	17ffff2b 	b	101500 <xil_vprintf+0x210>
  101858:	f94033e0 	ldr	x0, [sp, #96]
  10185c:	8b36c000 	add	x0, x0, w22, sxtw
  101860:	2a0103f6 	mov	w22, w1
  101864:	17ffff92 	b	1016ac <xil_vprintf+0x3bc>
  101868:	37f80316 	tbnz	w22, #31, 1018c8 <xil_vprintf+0x5d8>
  10186c:	91002ea0 	add	x0, x21, #0xb
  101870:	b94002a2 	ldr	w2, [x21]
  101874:	927df000 	and	x0, x0, #0xfffffffffffffff8
  101878:	91003c15 	add	x21, x0, #0xf
  10187c:	927df2b5 	and	x21, x21, #0xfffffffffffffff8
  101880:	f9400001 	ldr	x1, [x0]
  101884:	34000182 	cbz	w2, 1018b4 <xil_vprintf+0x5c4>
  101888:	8b224020 	add	x0, x1, w2, uxtw
  10188c:	aa0103f3 	mov	x19, x1
  101890:	f90037e0 	str	x0, [sp, #104]
  101894:	14000006 	b	1018ac <xil_vprintf+0x5bc>
  101898:	94000bf6 	bl	104870 <outbyte>
  10189c:	91000673 	add	x19, x19, #0x1
  1018a0:	f94037e0 	ldr	x0, [sp, #104]
  1018a4:	eb00027f 	cmp	x19, x0
  1018a8:	54000060 	b.eq	1018b4 <xil_vprintf+0x5c4>  // b.none
  1018ac:	39400260 	ldrb	w0, [x19]
  1018b0:	35ffff40 	cbnz	w0, 101898 <xil_vprintf+0x5a8>
  1018b4:	39401281 	ldrb	w1, [x20, #4]
  1018b8:	91000e93 	add	x19, x20, #0x3
  1018bc:	35ffd7ba 	cbnz	w26, 1013b0 <xil_vprintf+0xc0>
  1018c0:	aa1303f4 	mov	x20, x19
  1018c4:	17fffeb1 	b	101388 <xil_vprintf+0x98>
  1018c8:	110022c0 	add	w0, w22, #0x8
  1018cc:	7100001f 	cmp	w0, #0x0
  1018d0:	540000cd 	b.le	1018e8 <xil_vprintf+0x5f8>
  1018d4:	91002ea1 	add	x1, x21, #0xb
  1018d8:	2a0003f6 	mov	w22, w0
  1018dc:	b94002a2 	ldr	w2, [x21]
  1018e0:	927df020 	and	x0, x1, #0xfffffffffffffff8
  1018e4:	17ffffe5 	b	101878 <xil_vprintf+0x588>
  1018e8:	f94033e1 	ldr	x1, [sp, #96]
  1018ec:	b876c822 	ldr	w2, [x1, w22, sxtw]
  1018f0:	54000160 	b.eq	10191c <xil_vprintf+0x62c>  // b.none
  1018f4:	110042d6 	add	w22, w22, #0x10
  1018f8:	710002df 	cmp	w22, #0x0
  1018fc:	540000ad 	b.le	101910 <xil_vprintf+0x620>
  101900:	91003ea1 	add	x1, x21, #0xf
  101904:	aa1503e0 	mov	x0, x21
  101908:	927df035 	and	x21, x1, #0xfffffffffffffff8
  10190c:	17ffffdd 	b	101880 <xil_vprintf+0x590>
  101910:	f94033e1 	ldr	x1, [sp, #96]
  101914:	8b20c020 	add	x0, x1, w0, sxtw
  101918:	17ffffda 	b	101880 <xil_vprintf+0x590>
  10191c:	aa1503e0 	mov	x0, x21
  101920:	52800016 	mov	w22, #0x0                   	// #0
  101924:	17ffffd5 	b	101878 <xil_vprintf+0x588>
  101928:	d503201f 	nop
  10192c:	d503201f 	nop

0000000000101930 <xil_printf>:
  101930:	a9af7bfd 	stp	x29, x30, [sp, #-272]!
  101934:	128006e9 	mov	w9, #0xffffffc8            	// #-56
  101938:	12800fe8 	mov	w8, #0xffffff80            	// #-128
  10193c:	910003fd 	mov	x29, sp
  101940:	910343ea 	add	x10, sp, #0xd0
  101944:	910443eb 	add	x11, sp, #0x110
  101948:	a9032feb 	stp	x11, x11, [sp, #48]
  10194c:	f90023ea 	str	x10, [sp, #64]
  101950:	290923e9 	stp	w9, w8, [sp, #72]
  101954:	3d8017e0 	str	q0, [sp, #80]
  101958:	ad41c3e0 	ldp	q0, q16, [sp, #48]
  10195c:	3d801be1 	str	q1, [sp, #96]
  101960:	3d801fe2 	str	q2, [sp, #112]
  101964:	ad00c3e0 	stp	q0, q16, [sp, #16]
  101968:	3d8023e3 	str	q3, [sp, #128]
  10196c:	3d8027e4 	str	q4, [sp, #144]
  101970:	3d802be5 	str	q5, [sp, #160]
  101974:	3d802fe6 	str	q6, [sp, #176]
  101978:	3d8033e7 	str	q7, [sp, #192]
  10197c:	a90d8be1 	stp	x1, x2, [sp, #216]
  101980:	910043e1 	add	x1, sp, #0x10
  101984:	a90e93e3 	stp	x3, x4, [sp, #232]
  101988:	a90f9be5 	stp	x5, x6, [sp, #248]
  10198c:	f90087e7 	str	x7, [sp, #264]
  101990:	97fffe58 	bl	1012f0 <xil_vprintf>
  101994:	a8d17bfd 	ldp	x29, x30, [sp], #272
  101998:	d65f03c0 	ret
  10199c:	00000000 	udf	#0

00000000001019a0 <XConfigInterruptCntrl>:
  1019a0:	370001c0 	tbnz	w0, #0, 1019d8 <XConfigInterruptCntrl+0x38>
  1019a4:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  1019a8:	3200e3e1 	mov	w1, #0x11111111            	// #286331153
  1019ac:	910003fd 	mov	x29, sp
  1019b0:	f9000bf3 	str	x19, [sp, #16]
  1019b4:	d00001f3 	adrp	x19, 13f000 <tx+0xf570>
  1019b8:	912a4273 	add	x19, x19, #0xa90
  1019bc:	b9400a62 	ldr	w2, [x19, #8]
  1019c0:	6b01005f 	cmp	w2, w1
  1019c4:	540000e1 	b.ne	1019e0 <XConfigInterruptCntrl+0x40>  // b.any
  1019c8:	f9400bf3 	ldr	x19, [sp, #16]
  1019cc:	52800000 	mov	w0, #0x0                   	// #0
  1019d0:	a8c27bfd 	ldp	x29, x30, [sp], #32
  1019d4:	d65f03c0 	ret
  1019d8:	52800020 	mov	w0, #0x1                   	// #1
  1019dc:	d65f03c0 	ret
  1019e0:	927ff800 	and	x0, x0, #0xfffffffffffffffe
  1019e4:	940006a3 	bl	103470 <XScuGic_LookupConfig>
  1019e8:	b9401261 	ldr	w1, [x19, #16]
  1019ec:	35fffee1 	cbnz	w1, 1019c8 <XConfigInterruptCntrl+0x28>
  1019f0:	aa0003e1 	mov	x1, x0
  1019f4:	aa1303e0 	mov	x0, x19
  1019f8:	f9400bf3 	ldr	x19, [sp, #16]
  1019fc:	52800002 	mov	w2, #0x0                   	// #0
  101a00:	a8c27bfd 	ldp	x29, x30, [sp], #32
  101a04:	140005ec 	b	1031b4 <XScuGic_CfgInitialize>
  101a08:	d503201f 	nop
  101a0c:	d503201f 	nop

0000000000101a10 <XConnectToInterruptCntrl>:
  101a10:	2a0003e4 	mov	w4, w0
  101a14:	37000203 	tbnz	w3, #0, 101a54 <XConnectToInterruptCntrl+0x44>
  101a18:	d00001e5 	adrp	x5, 13f000 <tx+0xf570>
  101a1c:	912a40a5 	add	x5, x5, #0xa90
  101a20:	b94010a0 	ldr	w0, [x5, #16]
  101a24:	340001a0 	cbz	w0, 101a58 <XConnectToInterruptCntrl+0x48>
  101a28:	12002c80 	and	w0, w4, #0xfff
  101a2c:	37b000a4 	tbnz	w4, #22, 101a40 <XConnectToInterruptCntrl+0x30>
  101a30:	11004003 	add	w3, w0, #0x10
  101a34:	f26c009f 	tst	x4, #0x100000
  101a38:	11008000 	add	w0, w0, #0x20
  101a3c:	1a830000 	csel	w0, w0, w3, eq	// eq = none
  101a40:	aa0203e3 	mov	x3, x2
  101a44:	aa0103e2 	mov	x2, x1
  101a48:	2a0003e1 	mov	w1, w0
  101a4c:	aa0503e0 	mov	x0, x5
  101a50:	14000350 	b	102790 <XScuGic_Connect>
  101a54:	52800020 	mov	w0, #0x1                   	// #1
  101a58:	d65f03c0 	ret
  101a5c:	d503201f 	nop

0000000000101a60 <XDisconnectInterruptCntrl>:
  101a60:	370001e1 	tbnz	w1, #0, 101a9c <XDisconnectInterruptCntrl+0x3c>
  101a64:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  101a68:	12002c01 	and	w1, w0, #0xfff
  101a6c:	910003fd 	mov	x29, sp
  101a70:	37b000a0 	tbnz	w0, #22, 101a84 <XDisconnectInterruptCntrl+0x24>
  101a74:	f26c001f 	tst	x0, #0x100000
  101a78:	11004020 	add	w0, w1, #0x10
  101a7c:	11008021 	add	w1, w1, #0x20
  101a80:	1a800021 	csel	w1, w1, w0, eq	// eq = none
  101a84:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101a88:	912a4000 	add	x0, x0, #0xa90
  101a8c:	9400036d 	bl	102840 <XScuGic_Disconnect>
  101a90:	52800000 	mov	w0, #0x0                   	// #0
  101a94:	a8c17bfd 	ldp	x29, x30, [sp], #16
  101a98:	d65f03c0 	ret
  101a9c:	52800020 	mov	w0, #0x1                   	// #1
  101aa0:	d65f03c0 	ret

0000000000101aa4 <XStartInterruptCntrl>:
  101aa4:	12000020 	and	w0, w1, #0x1
  101aa8:	d65f03c0 	ret
  101aac:	d503201f 	nop

0000000000101ab0 <XEnableIntrId>:
  101ab0:	37000141 	tbnz	w1, #0, 101ad8 <XEnableIntrId+0x28>
  101ab4:	12002c01 	and	w1, w0, #0xfff
  101ab8:	37b000a0 	tbnz	w0, #22, 101acc <XEnableIntrId+0x1c>
  101abc:	f26c001f 	tst	x0, #0x100000
  101ac0:	11004020 	add	w0, w1, #0x10
  101ac4:	11008021 	add	w1, w1, #0x20
  101ac8:	1a800021 	csel	w1, w1, w0, eq	// eq = none
  101acc:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101ad0:	912a4000 	add	x0, x0, #0xa90
  101ad4:	140004a3 	b	102d60 <XScuGic_Enable>
  101ad8:	d65f03c0 	ret
  101adc:	d503201f 	nop

0000000000101ae0 <XDisableIntrId>:
  101ae0:	37000141 	tbnz	w1, #0, 101b08 <XDisableIntrId+0x28>
  101ae4:	12002c01 	and	w1, w0, #0xfff
  101ae8:	37b000a0 	tbnz	w0, #22, 101afc <XDisableIntrId+0x1c>
  101aec:	f26c001f 	tst	x0, #0x100000
  101af0:	11004020 	add	w0, w1, #0x10
  101af4:	11008021 	add	w1, w1, #0x20
  101af8:	1a800021 	csel	w1, w1, w0, eq	// eq = none
  101afc:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101b00:	912a4000 	add	x0, x0, #0xa90
  101b04:	14000500 	b	102f04 <XScuGic_Disable>
  101b08:	d65f03c0 	ret
  101b0c:	d503201f 	nop

0000000000101b10 <XSetPriorityTriggerType>:
  101b10:	12140c03 	and	w3, w0, #0xf000
  101b14:	12001c25 	and	w5, w1, #0xff
  101b18:	51400463 	sub	w3, w3, #0x1, lsl #12
  101b1c:	52800064 	mov	w4, #0x3                   	// #3
  101b20:	7213487f 	tst	w3, #0xffffe000
  101b24:	12002c01 	and	w1, w0, #0xfff
  101b28:	1a9f0483 	csinc	w3, w4, wzr, eq	// eq = none
  101b2c:	37b000a0 	tbnz	w0, #22, 101b40 <XSetPriorityTriggerType+0x30>
  101b30:	f26c001f 	tst	x0, #0x100000
  101b34:	11004020 	add	w0, w1, #0x10
  101b38:	11008021 	add	w1, w1, #0x20
  101b3c:	1a800021 	csel	w1, w1, w0, eq	// eq = none
  101b40:	36000042 	tbz	w2, #0, 101b48 <XSetPriorityTriggerType+0x38>
  101b44:	d65f03c0 	ret
  101b48:	2a0503e2 	mov	w2, w5
  101b4c:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101b50:	912a4000 	add	x0, x0, #0xa90
  101b54:	140003b8 	b	102a34 <XScuGic_SetPriorityTriggerType>
  101b58:	d503201f 	nop
  101b5c:	d503201f 	nop

0000000000101b60 <XGetPriorityTriggerType>:
  101b60:	370001a3 	tbnz	w3, #0, 101b94 <XGetPriorityTriggerType+0x34>
  101b64:	12002c04 	and	w4, w0, #0xfff
  101b68:	37b000a0 	tbnz	w0, #22, 101b7c <XGetPriorityTriggerType+0x1c>
  101b6c:	f26c001f 	tst	x0, #0x100000
  101b70:	11004080 	add	w0, w4, #0x10
  101b74:	11008084 	add	w4, w4, #0x20
  101b78:	1a800084 	csel	w4, w4, w0, eq	// eq = none
  101b7c:	aa0203e3 	mov	x3, x2
  101b80:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101b84:	aa0103e2 	mov	x2, x1
  101b88:	912a4000 	add	x0, x0, #0xa90
  101b8c:	2a0403e1 	mov	w1, w4
  101b90:	14000408 	b	102bb0 <XScuGic_GetPriorityTriggerType>
  101b94:	d65f03c0 	ret
  101b98:	d503201f 	nop
  101b9c:	d503201f 	nop

0000000000101ba0 <XStopInterruptCntrl>:
  101ba0:	36000040 	tbz	w0, #0, 101ba8 <XStopInterruptCntrl+0x8>
  101ba4:	d65f03c0 	ret
  101ba8:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101bac:	912a4000 	add	x0, x0, #0xa90
  101bb0:	14000540 	b	1030b0 <XScuGic_Stop>

0000000000101bb4 <XRegisterInterruptHandler>:
  101bb4:	370000e1 	tbnz	w1, #0, 101bd0 <XRegisterInterruptHandler+0x1c>
  101bb8:	b40000e0 	cbz	x0, 101bd4 <XRegisterInterruptHandler+0x20>
  101bbc:	aa0003e1 	mov	x1, x0
  101bc0:	d00001e2 	adrp	x2, 13f000 <tx+0xf570>
  101bc4:	52800040 	mov	w0, #0x2                   	// #2
  101bc8:	912a4042 	add	x2, x2, #0xa90
  101bcc:	14000095 	b	101e20 <Xil_ExceptionRegisterHandler>
  101bd0:	d65f03c0 	ret
  101bd4:	d00001e2 	adrp	x2, 13f000 <tx+0xf570>
  101bd8:	d0000001 	adrp	x1, 103000 <XScuGic_UnmapAllInterruptsFromCpu+0x10>
  101bdc:	912a4042 	add	x2, x2, #0xa90
  101be0:	910fc021 	add	x1, x1, #0x3f0
  101be4:	52800040 	mov	w0, #0x2                   	// #2
  101be8:	1400008e 	b	101e20 <Xil_ExceptionRegisterHandler>
  101bec:	d503201f 	nop

0000000000101bf0 <XSetupInterruptSystem>:
  101bf0:	a9bb7bfd 	stp	x29, x30, [sp, #-80]!
  101bf4:	910003fd 	mov	x29, sp
  101bf8:	a90153f3 	stp	x19, x20, [sp, #16]
  101bfc:	a9025bf5 	stp	x21, x22, [sp, #32]
  101c00:	aa0303f5 	mov	x21, x3
  101c04:	2a0203f6 	mov	w22, w2
  101c08:	a90363f7 	stp	x23, x24, [sp, #48]
  101c0c:	aa0003f8 	mov	x24, x0
  101c10:	aa0103f7 	mov	x23, x1
  101c14:	aa0303e0 	mov	x0, x3
  101c18:	f90023f9 	str	x25, [sp, #64]
  101c1c:	12003c99 	and	w25, w4, #0xffff
  101c20:	97ffff60 	bl	1019a0 <XConfigInterruptCntrl>
  101c24:	34000120 	cbz	w0, 101c48 <XSetupInterruptSystem+0x58>
  101c28:	52800033 	mov	w19, #0x1                   	// #1
  101c2c:	2a1303e0 	mov	w0, w19
  101c30:	a94153f3 	ldp	x19, x20, [sp, #16]
  101c34:	a9425bf5 	ldp	x21, x22, [sp, #32]
  101c38:	a94363f7 	ldp	x23, x24, [sp, #48]
  101c3c:	f94023f9 	ldr	x25, [sp, #64]
  101c40:	a8c57bfd 	ldp	x29, x30, [sp], #80
  101c44:	d65f03c0 	ret
  101c48:	d00001f4 	adrp	x20, 13f000 <tx+0xf570>
  101c4c:	912a4294 	add	x20, x20, #0xa90
  101c50:	52800023 	mov	w3, #0x1                   	// #1
  101c54:	2a0003f3 	mov	w19, w0
  101c58:	2a1903e1 	mov	w1, w25
  101c5c:	aa1503e2 	mov	x2, x21
  101c60:	2a1603e0 	mov	w0, w22
  101c64:	b9001283 	str	w3, [x20, #16]
  101c68:	97ffffaa 	bl	101b10 <XSetPriorityTriggerType>
  101c6c:	3707fdf5 	tbnz	w21, #0, 101c28 <XSetupInterruptSystem+0x38>
  101c70:	b9401280 	ldr	w0, [x20, #16]
  101c74:	12002ed5 	and	w21, w22, #0xfff
  101c78:	120a02d9 	and	w25, w22, #0x400000
  101c7c:	340005e0 	cbz	w0, 101d38 <XSetupInterruptSystem+0x148>
  101c80:	35000459 	cbnz	w25, 101d08 <XSetupInterruptSystem+0x118>
  101c84:	720c02d6 	ands	w22, w22, #0x100000
  101c88:	52800400 	mov	w0, #0x20                  	// #32
  101c8c:	52800201 	mov	w1, #0x10                  	// #16
  101c90:	1a801021 	csel	w1, w1, w0, ne	// ne = any
  101c94:	aa1803e3 	mov	x3, x24
  101c98:	aa1703e2 	mov	x2, x23
  101c9c:	0b150021 	add	w1, w1, w21
  101ca0:	aa1403e0 	mov	x0, x20
  101ca4:	940002bb 	bl	102790 <XScuGic_Connect>
  101ca8:	35fffc00 	cbnz	w0, 101c28 <XSetupInterruptSystem+0x38>
  101cac:	d0000001 	adrp	x1, 103000 <XScuGic_UnmapAllInterruptsFromCpu+0x10>
  101cb0:	aa1403e2 	mov	x2, x20
  101cb4:	910fc021 	add	x1, x1, #0x3f0
  101cb8:	52800040 	mov	w0, #0x2                   	// #2
  101cbc:	94000059 	bl	101e20 <Xil_ExceptionRegisterHandler>
  101cc0:	110042a0 	add	w0, w21, #0x10
  101cc4:	710002df 	cmp	w22, #0x0
  101cc8:	110082b5 	add	w21, w21, #0x20
  101ccc:	1a8002b5 	csel	w21, w21, w0, eq	// eq = none
  101cd0:	2a1503e1 	mov	w1, w21
  101cd4:	aa1403e0 	mov	x0, x20
  101cd8:	94000422 	bl	102d60 <XScuGic_Enable>
  101cdc:	9400004e 	bl	101e14 <Xil_ExceptionInit>
  101ce0:	d53b4220 	mrs	x0, daif
  101ce4:	12187800 	and	w0, w0, #0xffffff7f
  101ce8:	d51b4220 	msr	daif, x0
  101cec:	a9425bf5 	ldp	x21, x22, [sp, #32]
  101cf0:	2a1303e0 	mov	w0, w19
  101cf4:	a94153f3 	ldp	x19, x20, [sp, #16]
  101cf8:	a94363f7 	ldp	x23, x24, [sp, #48]
  101cfc:	f94023f9 	ldr	x25, [sp, #64]
  101d00:	a8c57bfd 	ldp	x29, x30, [sp], #80
  101d04:	d65f03c0 	ret
  101d08:	aa1803e3 	mov	x3, x24
  101d0c:	aa1703e2 	mov	x2, x23
  101d10:	2a1503e1 	mov	w1, w21
  101d14:	aa1403e0 	mov	x0, x20
  101d18:	9400029e 	bl	102790 <XScuGic_Connect>
  101d1c:	35fff860 	cbnz	w0, 101c28 <XSetupInterruptSystem+0x38>
  101d20:	aa1403e2 	mov	x2, x20
  101d24:	d0000001 	adrp	x1, 103000 <XScuGic_UnmapAllInterruptsFromCpu+0x10>
  101d28:	52800040 	mov	w0, #0x2                   	// #2
  101d2c:	910fc021 	add	x1, x1, #0x3f0
  101d30:	9400003c 	bl	101e20 <Xil_ExceptionRegisterHandler>
  101d34:	17ffffe7 	b	101cd0 <XSetupInterruptSystem+0xe0>
  101d38:	d0000001 	adrp	x1, 103000 <XScuGic_UnmapAllInterruptsFromCpu+0x10>
  101d3c:	aa1403e2 	mov	x2, x20
  101d40:	910fc021 	add	x1, x1, #0x3f0
  101d44:	52800040 	mov	w0, #0x2                   	// #2
  101d48:	94000036 	bl	101e20 <Xil_ExceptionRegisterHandler>
  101d4c:	35fffc39 	cbnz	w25, 101cd0 <XSetupInterruptSystem+0xe0>
  101d50:	120c02d6 	and	w22, w22, #0x100000
  101d54:	17ffffdb 	b	101cc0 <XSetupInterruptSystem+0xd0>
  101d58:	d503201f 	nop
  101d5c:	d503201f 	nop

0000000000101d60 <XGetEncodedIntrId>:
  101d60:	12001c63 	and	w3, w3, #0xff
  101d64:	2a0003e5 	mov	w5, w0
  101d68:	12001c42 	and	w2, w2, #0xff
  101d6c:	7100047f 	cmp	w3, #0x1
  101d70:	540001c8 	b.hi	101da8 <XGetEncodedIntrId+0x48>  // b.pmore
  101d74:	350000e3 	cbnz	w3, 101d90 <XGetEncodedIntrId+0x30>
  101d78:	340001c2 	cbz	w2, 101db0 <XGetEncodedIntrId+0x50>
  101d7c:	7100045f 	cmp	w2, #0x1
  101d80:	54000240 	b.eq	101dc8 <XGetEncodedIntrId+0x68>  // b.none
  101d84:	7100085f 	cmp	w2, #0x2
  101d88:	540000e1 	b.ne	101da4 <XGetEncodedIntrId+0x44>  // b.any
  101d8c:	320a0005 	orr	w5, w0, #0x400000
  101d90:	53140c21 	ubfiz	w1, w1, #12, #4
  101d94:	52800000 	mov	w0, #0x0                   	// #0
  101d98:	2a050021 	orr	w1, w1, w5
  101d9c:	b9000081 	str	w1, [x4]
  101da0:	d65f03c0 	ret
  101da4:	b9000080 	str	w0, [x4]
  101da8:	52800020 	mov	w0, #0x1                   	// #1
  101dac:	d65f03c0 	ret
  101db0:	51008005 	sub	w5, w0, #0x20
  101db4:	53140c21 	ubfiz	w1, w1, #12, #4
  101db8:	2a050021 	orr	w1, w1, w5
  101dbc:	52800000 	mov	w0, #0x0                   	// #0
  101dc0:	b9000081 	str	w1, [x4]
  101dc4:	17fffff7 	b	101da0 <XGetEncodedIntrId+0x40>
  101dc8:	51004005 	sub	w5, w0, #0x10
  101dcc:	52800280 	mov	w0, #0x14                  	// #20
  101dd0:	2a0000a5 	orr	w5, w5, w0
  101dd4:	17ffffef 	b	101d90 <XGetEncodedIntrId+0x30>
  101dd8:	d503201f 	nop
  101ddc:	d503201f 	nop

0000000000101de0 <XTriggerSoftwareIntr>:
  101de0:	36000061 	tbz	w1, #0, 101dec <XTriggerSoftwareIntr+0xc>
  101de4:	52800000 	mov	w0, #0x0                   	// #0
  101de8:	d65f03c0 	ret
  101dec:	12002c01 	and	w1, w0, #0xfff
  101df0:	d00001e0 	adrp	x0, 13f000 <tx+0xf570>
  101df4:	912a4000 	add	x0, x0, #0xa90
  101df8:	140002cf 	b	102934 <XScuGic_SoftwareIntr>
  101dfc:	00000000 	udf	#0

0000000000101e00 <Xil_ExceptionNullHandler>:
  101e00:	14000000 	b	101e00 <Xil_ExceptionNullHandler>

0000000000101e04 <Xil_SyncErrorHandler>:
  101e04:	d503201f 	nop
  101e08:	14000000 	b	101e08 <Xil_SyncErrorHandler+0x4>
  101e0c:	d503201f 	nop

0000000000101e10 <Xil_SErrorHandler>:
  101e10:	14000000 	b	101e10 <Xil_SErrorHandler>

0000000000101e14 <Xil_ExceptionInit>:
  101e14:	d65f03c0 	ret
  101e18:	d503201f 	nop
  101e1c:	d503201f 	nop

0000000000101e20 <Xil_ExceptionRegisterHandler>:
  101e20:	d37c7c00 	ubfiz	x0, x0, #4, #32
  101e24:	900000a3 	adrp	x3, 115000 <zeroes.0+0x5f0>
  101e28:	912d2063 	add	x3, x3, #0xb48
  101e2c:	8b000064 	add	x4, x3, x0
  101e30:	f8206861 	str	x1, [x3, x0]
  101e34:	f9000482 	str	x2, [x4, #8]
  101e38:	d65f03c0 	ret
  101e3c:	d503201f 	nop

0000000000101e40 <Xil_GetExceptionRegisterHandler>:
  101e40:	d37c7c00 	ubfiz	x0, x0, #4, #32
  101e44:	900000a3 	adrp	x3, 115000 <zeroes.0+0x5f0>
  101e48:	912d2063 	add	x3, x3, #0xb48
  101e4c:	8b000064 	add	x4, x3, x0
  101e50:	f8606860 	ldr	x0, [x3, x0]
  101e54:	f9000020 	str	x0, [x1]
  101e58:	f9400480 	ldr	x0, [x4, #8]
  101e5c:	f9000040 	str	x0, [x2]
  101e60:	d65f03c0 	ret

0000000000101e64 <Xil_ExceptionRemoveHandler>:
  101e64:	d37c7c00 	ubfiz	x0, x0, #4, #32
  101e68:	900000a1 	adrp	x1, 115000 <zeroes.0+0x5f0>
  101e6c:	912d2021 	add	x1, x1, #0xb48
  101e70:	90000002 	adrp	x2, 101000 <outnum1+0x30>
  101e74:	8b000023 	add	x3, x1, x0
  101e78:	91380042 	add	x2, x2, #0xe00
  101e7c:	f8206822 	str	x2, [x1, x0]
  101e80:	f900047f 	str	xzr, [x3, #8]
  101e84:	d65f03c0 	ret
	...

0000000000101e90 <FIQInterrupt>:
  101e90:	900000a0 	adrp	x0, 115000 <zeroes.0+0x5f0>
  101e94:	912d2000 	add	x0, x0, #0xb48
  101e98:	a9430001 	ldp	x1, x0, [x0, #48]
  101e9c:	aa0103f0 	mov	x16, x1
  101ea0:	d61f0200 	br	x16

0000000000101ea4 <IRQInterrupt>:
  101ea4:	900000a0 	adrp	x0, 115000 <zeroes.0+0x5f0>
  101ea8:	912d2000 	add	x0, x0, #0xb48
  101eac:	a9420001 	ldp	x1, x0, [x0, #32]
  101eb0:	aa0103f0 	mov	x16, x1
  101eb4:	d61f0200 	br	x16
  101eb8:	d503201f 	nop
  101ebc:	d503201f 	nop

0000000000101ec0 <SynchronousInterrupt>:
  101ec0:	900000a0 	adrp	x0, 115000 <zeroes.0+0x5f0>
  101ec4:	912d2000 	add	x0, x0, #0xb48
  101ec8:	a9410001 	ldp	x1, x0, [x0, #16]
  101ecc:	aa0103f0 	mov	x16, x1
  101ed0:	d61f0200 	br	x16

0000000000101ed4 <SErrorInterrupt>:
  101ed4:	900000a0 	adrp	x0, 115000 <zeroes.0+0x5f0>
  101ed8:	912d2000 	add	x0, x0, #0xb48
  101edc:	a9440001 	ldp	x1, x0, [x0, #64]
  101ee0:	aa0103f0 	mov	x16, x1
  101ee4:	d61f0200 	br	x16
  101ee8:	0011f980 	.word	0x0011f980
  101eec:	00000000 	.word	0x00000000
  101ef0:	0011f980 	.word	0x0011f980
  101ef4:	00000000 	.word	0x00000000
  101ef8:	0011f980 	.word	0x0011f980
  101efc:	00000000 	.word	0x00000000
  101f00:	0013fdc0 	.word	0x0013fdc0
  101f04:	00000000 	.word	0x00000000


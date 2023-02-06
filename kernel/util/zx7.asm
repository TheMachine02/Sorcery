zx7:

.decompress:
; hl : src, de : dest
; Routine copied from the C toolchain & speed optimized
;  Input:
;   HL = compressed data pointer
;   DE = output data pointer
	ld	a, 128
.copy_byte_loop:
	ldi
.main_loop:
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	jr	nc, .copy_byte_loop
	push	de
	ld	de, 0
	ld	bc, 1
.len_size_loop:
	inc	d
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	jr	nc, .len_size_loop
	jr	.len_value_start
.len_value_loop:
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	rl	c
	rl	b
	jr	c, .exit
.len_value_start:
	dec	d
	jr	nz, .len_value_loop
	inc	bc
	ld	e, (hl)
	inc	hl
	sla	e
	inc	e
	jr	nc, .offset_end
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	rl	d
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	rl	d
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	rl	d
	add	a, a
	jr	nz, $+5
	ld	a, (hl)
	inc	hl
	rla
	ccf
	jr	c, .offset_end
	inc	d
.offset_end:
	rr	e
	ex	(sp), hl
	push	hl
	sbc	hl, de
	pop	de
	ldir
.exit:
	pop	hl
	jr	nc, .main_loop
	ret

udiv:

.fault:
	ld	a, SIGFPE
	call	raise
	pop	af
	ret

.16:
; hl = hl / bc, de = hl mod bc, return a 16 bits results (bc is 16 bits, hl is 16 bits)
	push	af
	ld	a, c
	or	a, b
	jr	z, .fault
	xor	a, a
	sbc	hl, hl
	ld	h, d
	ld	l, e
	ex	de, hl
	sbc	hl, hl
	ld	a, d
repeat 8
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
end repeat
	adc	a, a
	cpl
	ld	d, a
	ld	a, e
repeat 8
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
end repeat
	adc	a, a
	cpl
	ld	e, a
	ex	de, hl
	pop	af
	ret

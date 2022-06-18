fpu:

.uidiv:
;; divide 16 bits DE by 16 bits BC and output the 16 bits BC result. HL is the remainder
;; Thanks Xeda for this routine
;; Inputs: DE is the numerator, BC is the divisor
;; Outputs: DE is the result
;;         A is a copy of E
;;         HL is the remainder
;;         BC is not changed
	xor	a, a
	sbc	hl, hl
	ld	a, d
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	cpl
	ld	d, a
	ld	a, e
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	adc	hl, hl
	sbc	hl, bc
	jr	nc, $+3
	add	hl, bc
	adc	a, a
	cpl
	ld	e, a
	ret  

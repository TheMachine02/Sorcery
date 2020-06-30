.glyph_string:
; bc = string, hl xy
	call	.glyph_adress
.glyph_string_loop:
	ld	a, (bc)
	or	a, a
	ret	z
	push	de
	push	bc
	ld	h, a
	cp	a, $1B
	jr	z, .escape_sequence
.glyph_write_color:
	ld	a, (console_color)
	ld	c, a
	ld	a, h
	call	.glyph_char_entry
	pop	bc
	pop	de
	ld	hl, 6
	add	hl, de
	ex	de, hl
	inc	bc
	jr	.glyph_string_loop

.escape_sequence:
	inc	bc
	ld	a, (bc)
	inc	bc
	cp	a, '['
	jr	z, .escape_CSI
; dunno, other sequences
	ret
.escape_CSI:
; bad, I should read parameter and do the command given by last byte
	inc	bc
	ld	a, (bc)	; color
	sub	a, '0' - 2
	cp	a, 11
	jr	nz, $+4
	xor	a, a
	inc	a
	ld	(console_color), a
.sequence_end:
	inc	bc
	ld	a, (bc)
	cp	a, 'm'
	jr	nz, .sequence_end
	inc	bc
	pop	hl
	pop	de
	jr	.glyph_string_loop
	
.glyph_adress:
	ld	d, 110
	ld	e, h
	mlt	de
	ex	de, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	ld	d, 6
	mlt	de
	add	hl, de
	ld	de, 10*320+10
	add	hl, de
	ld	de, (DRIVER_VIDEO_SCREEN)
	add	hl, de
	ex	de, hl
	ret

.glyph_char:
; h = y , l = x (console 50x20), c is color, a is char
; y isdb 11, x is 6 in height/width
; x * 6 + (y*11)*320 + buffer (3520)
	call	.glyph_adress
.glyph_char_entry:
	or	a, a
	jr	z, .glyph_blank_entry
	sbc	hl, hl
	ld	l, a
	ld	a, c
	add	hl, hl
	add	hl, hl
	ld	bc, .TRANSLATION_TABLE
	add	hl, bc
	ld	hl, (hl)
	ex	de, hl
	push	hl
	ex	(sp), iy
	ld	b, 11
	ld	c, a
.glyph_char_ow_loop:
	push	de
	ld	a, (de)
	ld	e, a
	rr	e
	sbc	a, a
	and	a, c
	ld	(hl), a
	inc	hl
	rr	e
	sbc	a, a
	and	a, c
	ld	(hl), a
	inc	hl
	rr	e
	sbc	a, a
	and	a, c
	ld	(hl), a
	inc	hl
	rr	e
	sbc	a, a
	and	a, c
	ld	(hl), a
	inc	hl
	rr	e
	sbc	a, a
	and	a, c
	ld	(hl), a
	inc	hl
	rr	e
	sbc	a, a
	and	a, c
	ld	(hl), a
	inc	hl
	ld	de, 320
	add	iy, de
	lea	hl, iy + 0
	pop	de
	inc	de
	djnz	.glyph_char_ow_loop
	pop	iy
	ret

.glyph_blank:
	call	.glyph_adress
; hl = screen
.glyph_blank_entry:
	ld	hl, $E40000
	ld	bc, 256 + 11
	ld	a, c
.glyph_blank_loop:
	dec	b
	ld	c, 6
	ldir
	inc	b
	ld	c, 58
	ex	de, hl
	add	hl, bc
	ex	de, hl
	dec	a
	jr	nz, .glyph_blank_loop
	ret

.glyph_hex:
; bc = number to blit in hex format [8 characters], a = color
	call	.glyph_adress
	push	iy
	push	bc
	ld	iy, 0
	add	iy, sp
	ld	c, a
	ld	a, '0'
	push	de
	call	.glyph_char_entry
	pop	de
	ld	hl, 6
	add	hl, de
	ex	de, hl
	ld	a, 'x'
	push	de
	call	.glyph_char_entry
	pop	de
	ld	hl, 6
	add	hl, de
	ex	de, hl
	ld	b, (iy+2)
	call	.glyph_8bit_digit
	ld	b, (iy+1)
	call	.glyph_8bit_digit
	ld	b, (iy+0)
	call	.glyph_8bit_digit
	pop	bc
	pop	iy
	ret
.glyph_8bit_digit:
; input c
	ld	a, b
	push	af
	rra
	rra
	rra
	rra
	call	.glyph_4bit_digit
	pop	af
.glyph_4bit_digit:
	and	$0F
	add	a, $90
	daa
	jr	nc, $+4
	adc	a, $C0		; $60 + ($90 - $30)
	sub	a, $60		; ($90-$30)
	push	de
	call	.glyph_char_entry
	pop	de
	ld	hl, 6
	add	hl, de
	ex	de, hl
	ret
	
.glyph_integer:
	push	iy
	push	bc
	call	.glyph_adress
	ld	iy, .TABLE_OF_TEN
	pop	hl
	ld	a, 8
.glyph_integer_loop:
	push	af
	ld	bc, (iy+0)
	lea	iy, iy+3
	ld	a,'0'-1
.glyph_find_digit:
	inc	a
	or	a, a
	sbc	hl, bc
	jr	nc, .glyph_find_digit
	add	hl, bc
	push	hl
	push	de
	ld	c, 1	; color
	call	.glyph_char_entry
	pop	de
	ld	hl, 6
	add	hl, de
	ex	de, hl
	pop	hl
	pop	af
	dec	a
	jr	nz, .glyph_integer_loop
	pop	iy
	ret
.glyph_quit:
	pop	af
	pop	iy
	ret

.TABLE_OF_TEN:
 dl	10000000
 dl	1000000
 dl	100000
 dl	10000
 dl	1000
 dl	100
 dl	10
 dl	1

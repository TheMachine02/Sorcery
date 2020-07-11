.glyph_adress:
	ld	d, 220
	ld	e, h
	mlt	de
	ex	de, hl
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
; display a character a the cursor position and of the console color
; DOESNT update console_cursor nor color
; return de = next screen buffer position
	ld	hl, console_color
	ld	c, (hl)
	inc	hl
	ld	hl, (hl)
; h = y , l = x (console 50x20), c is color, a is char
; y isdb 11, x is 6 in height/width
; x * 6 + (y*11)*320 + buffer (3520)
	call	.glyph_adress
.glyph_char_address:
	or	a, a
	jr	z, .glyph_blank_address
	sbc	hl, hl
	ld	l, a
	ld	a, c
	add	hl, hl
	add	hl, hl
	ld	bc, .TRANSLATION_TABLE
	add	hl, bc
	ld	hl, (hl)
	push	de
	ex	(sp), iy
	ld	b, 11
	ld	c, a
.glyph_char_loop:
	push	hl
	ld	l, (hl)
	rr	l
	sbc	a, a
	and	a, c
	ld	(de), a
	inc	de
	rr	l
	sbc	a, a
	and	a, c
	ld	(de), a
	inc	de
	rr	l
	sbc	a, a
	and	a, c
	ld	(de), a
	inc	de
	rr	l
	sbc	a, a
	and	a, c
	ld	(de), a
	inc	de
	rr	l
	sbc	a, a
	and	a, c
	ld	(de), a
	inc	de
	rr	l
	sbc	a, a
	and	a, c
	ld	(de), a
	ld	de, 320
	add	iy, de
	lea	de, iy + 0
	pop	hl
	inc	hl
	djnz	.glyph_char_loop
; hl is the last line position
; so hl - 320*11 + 6 = next character position
	ld	hl, -320*11+6
	add	hl, de
	ex	de, hl
	pop	iy
	ret

.glyph_blank:
; erase a caracter
	call	.glyph_adress
; hl = screen
.glyph_blank_address:
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
	ld	hl, -320*11
	add	hl, de
	ret

if CONFIG_USE_GLYPH_NUMBER = 1
.glyph_hex:
; bc = number to blit in hex format [8 characters], a = color
	call	.glyph_adress
.glyph_hex_address:
	push	iy
	push	bc
	ld	iy, 0
	add	iy, sp
	ld	c, a
	ld	a, '0'
	call	.glyph_char_address
	ld	a, 'x'
	call	.glyph_char_address
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
	ld	c, 1
	jp	.glyph_char_address
	
.glyph_integer:
	ld	a, 8
.glyph_integer_format:
	call	.glyph_adress
.glyph_integer_address:
	push	iy
	push	bc
	ex	de, hl
	ld	e, a
	ld	a, 8
	sub	a, e
	jr	nc, $+3
	xor	a, a
	ld	d, a
	ld	a, e
	ld	e, 3
	mlt	de
	ld	iy, .TABLE_OF_TEN
	add	iy, de
	ex	de, hl
	pop	hl
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
	ld	c, 1	; color
	call	.glyph_char_address
	pop	hl
	pop	af
	dec	a
	jr	nz, .glyph_integer_loop
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
 
 end if
 
 ; font
 include 'gohufont.inc'

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

if CONFIG_USE_GLYPH_NUMBER = 1
.glyph_hex:
; bc = number to blit in hex format [8 characters]
	call	.glyph_adress
.glyph_hex_address:
	push	iy
	push	bc
	ld	iy, 0
	add	iy, sp
	ld	a, '0'
	call	.glyph_char_address
	ld	a, 'x'
	call	.glyph_char_address
	ld	a, (iy+2)
	call	.glyph_8bit_digit
	ld	a, (iy+1)
	call	.glyph_8bit_digit
	ld	a, (iy+0)
	call	.glyph_8bit_digit
	pop	bc
	pop	iy
	ret

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
	or	a, a
.glyph_find_digit:
	inc	a
	sbc	hl, bc
	jr	nc, .glyph_find_digit
	add	hl, bc
	push	hl
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
 
 .glyph_8bit_digit:
; input c
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
	jr	.glyph_char_address
	
 end if
 
.glyph_char:
; display a character a the cursor position and of the console color
; DOESNT update console_cursor nor color
; return de = next screen buffer position
	ld	hl, (console_cursor_xy)
; h = y , l = x (console 50x20)
; y isdb 11, x is 6 in height/width
; x * 6 + (y*11)*320 + buffer (3520)
	call	.glyph_adress
.glyph_char_address:
	ld	l, a
	ld	h, 3
	mlt	hl
	ld	bc, .TRANSLATION_TABLE
	add	hl, bc
	push	iy
	ld	iy, console_dev
; load foreground & background color
;	ld	bc, (iy+CONSOLE_FG_COLOR)
	ld	bc, (iy+CONSOLE_FG_COLOR-1)
	ld	c, (iy+CONSOLE_BG_COLOR)
	ld	iy, (hl)
	ex	de, hl
	ld	de, 315
; c = background b = foreground bcu = background
.glyph_char_loop:
	ld	a, (iy+0)
	inc	iy
	ld	(hl), bc
	add	a, a
	jr	nc, $+3
	ld	(hl), b
	inc	hl
	add	a, a
	jr	c, $+3
	ld	(hl), c
	inc	hl
	add	a, a
	jr	nc, $+3
	ld	(hl), b
	inc	hl
	ld	(hl), bc
	add	a, a
	jr	nc, $+3
	ld	(hl), b
	inc	hl
	add	a, a
	jr	c, $+3
	ld	(hl), c
	inc	hl
	add	a, a
	jr	nc, $+3
	ld	(hl), b
	add	hl, de
	jr	z, .glyph_char_loop
; hl is the last line position
; so hl - 320*11 + 6 = next character position
	ld	de, -320*11+6
	add	hl, de
	ex	de, hl
	pop	iy
	ret

 ; font
 include '../font/gohufont.inc'
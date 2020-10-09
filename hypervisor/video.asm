define	VM_VIDEO_ISR		$E30020
define	VM_VIDEO_ICR		$E30028
define	VM_VIDEO_SCREEN		$E30010

.putstring:
; use the kernel function
; display string bc @ hl (y - x)
	call	.adress
.putstring_loop:
	ld	a, (bc)
	or	a, a
	ret	z
	push	bc
	call	.putchar
	pop	bc
	inc	bc
	jr	.putstring_loop

.vsync:
; wait until the LCD finish displaying the frame
	ld	hl, VM_VIDEO_ICR
	set	2, (hl)
	ld	l, VM_VIDEO_ISR and $FF
.wait_busy:
	bit	2, (hl)
	jr	z, .wait_busy
	ret

.adress:
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
	ld	de, (VM_VIDEO_SCREEN)
	add	hl, de
	ex	de, hl
	ret
 
.putchar:
; ix color pattern, hl position (screen)
	push	iy
	ld	l, a
	ld	h, 3
	mlt	hl
	ld	bc, font.TRANSLATION_TABLE
	add	hl, bc
	lea	bc, ix+0
	ld	iy, (hl)
	ex	de, hl
	ld	de, 315
; c = background b = foreground bcu = background
.putchar_loop:
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
	jr	z, .putchar_loop
; hl is the last line position
; so hl - 320*11 + 6 = next character position
	ld	de, -320*11+6
	add	hl, de
	ex	de, hl
	pop	iy
	ret

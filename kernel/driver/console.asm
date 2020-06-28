define	console_cursor_xy	$D30400
define	console_ring		$D30403
define	console_blink		$D30406
define	console_flags		$D30407
define	console_key		$D30408
define	console_color		$D30409

define	console_string		$D3040A

define	CONSOLE_GLYPH_X		50
define	CONSOLE_GLYPH_Y		20

console:

.run:
	call	.new_line
	ld	hl, (console_cursor_xy)
	call	.prompt
.run_loop:
; wait keyboard scan
	ld	b, 80
.wait_keyboard:
	push	bc
; 	ld	hl, $F50000
; 	ld	(hl),2
; 	xor	a, a
; .busy_wait:
; 	cp	a, (hl)
; 	jr	nz, .busy_wait
	call	kkeyboard.wait_scan
; check if pressed now == pressed previous
	call	.read_keyboard
	ld	l, a
	ld	a, (console_key)
	sub	a, l
	ld	a, l
; no, process
	pop	bc
	jr	nz, .doit
	djnz	.wait_keyboard
	ld	a, $FD
.doit:
	ld	(console_key), a
	
	ld	hl, (console_cursor_xy)
	call	.glyph_blank
	
	ld	iy, (console_ring)
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (console_color)
	ld	c, a
	ld	a, (hl)
	or	a, a
	ld	hl, (console_cursor_xy)
	call	nz, .glyph_put_char
	
	ld	a, (console_key)
	cp	a, $FC
	call	z, .handle_key_clear

	ld	a, (console_key)
	cp	a, $FE
	call	z, .handle_key_enter
	
	ld	a, (console_key)
	cp	a, $F9
	call	z, .handle_key_right
	
	ld	a, (console_key)
	cp	a, $FA
	call	z, .handle_key_left
	
	ld	a, (console_key)
	cp	a, $FF
	call	z, .handle_key_del

	ld	a, (console_key)
	cp	a, $F7
	call	z, .handle_key_mode
	
	call	.read_char
	push	af
	ld	a, (console_color)
	ld	c, a
	pop	af
	call	p, .write_char
; keyboard00
	
	ld	a, (console_blink)
	inc	a
	ld	(console_blink), a
		
	bit	2, a
	call	nz, .cursor
	
	call	kvideo.vsync	; wait for vsync to be sure change has been comit
	jp	.run_loop

	
	
	
.KEYMAP_NO_MOD:
 db ' ', ':', '?', 'x', 'y', 'z', '"', 's', 't', 'u', 'v', 'w', 'n', 'o', 'p', 'q', 'r', 'i', 'j', 'k', 'l', 'm'
 db 'd', 'e', 'f', 'g', 'h', 'a', 'b', 'c', 0
 
.KEYMAP_ALPHA:
 db ' ', '.', ';', 'X', 'Y', 'Z', '!', 'S', 'T', 'U', 'V', 'W', 'N', 'O', 'P', 'Q', 'R', 'I', 'J', 'K', 'L', 'M'
 db 'D', 'E', 'F', 'G', 'H', 'A', 'B', 'C', 0

.KEYBOARD_KEY:
 db $FD, $FD, $FD, $FD, $FD, $FD, $F7, $FF
 db $FD, $03, $07, $0C, $11, $16, $1B, $FD
 db $00, $04, $08, $0D, $12, $17, $1C, $FD
 db $01, $05, $09, $0E, $13, $18, $1D, $FD
 db $02, $FD, $0A, $0F, $14, $19, $FD, $FD
 db $FE, $06, $0B, $10, $15, $1A, $FC, $FD
 db $FB, $FA, $F9, $F8, $FD, $FD, $FD, $FD

.KEYMAP_2ND:

.read_char:
	ld	a, (console_flags)
	bit	0, a
	ld	hl, .KEYMAP_NO_MOD
	jr	z, .oooo
	ld	hl, .KEYMAP_ALPHA
.oooo:
	ld	de, 0
	ld	a, (console_key)
	or	a, a
	ret	m
	ld	e, a
	add	hl, de
	xor	a, a
	ld	(console_flags), a
	ld	a, (hl)
	ret

.read_keyboard:
	ld	a, ($F50014)
	bit	7, a
	jr	z, .swap_alpha
	ld	a, (console_flags)
	or	a, 00000001b
	ld	(console_flags), a
.swap_alpha:

	ld	a, ($F50012)
	bit	5, a
	jr	z, .swap_2nd
	ld	a, (console_flags)
	or	a, 00000010b
	ld	(console_flags), a
.swap_2nd:
	ld	hl, .KEYBOARD_KEY
	ld	de, $F50012
	ld	c, 7
.loop1:
	ld	a, (de)
	ld	b, 8
.loop0:
	rra
	jr	c, .found_key
.back:
	inc	hl
	djnz	.loop0
	inc	de
	inc	de
	dec	c
	jr	nz, .loop1
	ld	a, $FD
	ret
.found_key:
	ld	iyl, a
	ld	a, (hl)
	cp	a, $FD
	ret	nz
	ld	a, iyl
	jr	.back
	
.cursor:
	ld	hl, (console_cursor_xy)
	ld	a, (console_color)
	ld	c, a
	ld	a, '_'
	jp	.glyph_put_char
	
.glyph_blank:
	call	.glyph_adress
; hl = screen
	ld	hl, $E40000
	ld	a, 11
.glyph_blank_loop:
	ld	bc, 6
	ldir
	ld	bc, 320-6
	ex	de, hl
	add	hl, bc
	ex	de, hl
	dec	a
	jr	nz, .glyph_blank_loop
	ret
	
.decrement_cursor:
	ld	hl, (console_cursor_xy)
	ld	a, l
	dec	a
	cp	a, 255
	jr	z, .prev_line
	ld	l, a
	ld	(console_cursor_xy), hl
	ret

.prev_line:
	ld	hl, (console_cursor_xy)
	ld	l, CONSOLE_GLYPH_X - 1
	ld	a, h
	dec	a
	cp	a, 255
	ret	z
	ld	h, a
	ld	(console_cursor_xy), hl
	ret	
	
.increment_cursor:
	ld	hl, (console_cursor_xy)
	ld	a, l
	inc	a
	cp	a, CONSOLE_GLYPH_X
	jr	z, .new_line
	ld	l, a
	ld	(console_cursor_xy), hl
	ret
	
.new_line:
	ld	hl, (console_cursor_xy)
; x = l, y = h
	ld	l, 0
	ld	a, h
	inc	a
	cp	a, CONSOLE_GLYPH_Y
	jr	z, .new_line_shift
; else
	ld	h, a
	ld	(console_cursor_xy), hl
	ret
.new_line_shift:
	ld	(console_cursor_xy), hl
	jp	.shift_up

.handle_key_del:
	ld	iy, (console_ring)
	call	ring_buffer.remove_head
	ret	z
	jr	.refresh_line
	
.handle_key_mode:
; backspace behaviour
	ld	iy, (console_ring)
	call	ring_buffer.remove
	ret	z
	ld	hl, (console_cursor_xy)
	call	.glyph_blank
	call	console.decrement_cursor

.refresh_line:
; start at cursor, ring buffer head
; write glyph to console till ring buffer != 0
	ld	iy, (console_ring)
	ld	hl, (console_cursor_xy)
	push	hl
	ld	hl, (iy+RING_BUFFER_HEAD)
.refresh_line_loop:
	push	hl
	ld	hl, (console_cursor_xy)
	call	.glyph_blank
	pop	hl
	ld	a, (hl)
	or	a, a
	jr	z, .restore
	ld	iy, (console_ring)
	call	ring_buffer.increment
	push	hl
	push	af
	ld	hl, (console_cursor_xy)
	ld	a, (console_color)
	ld	c, a
	pop	af
	call	.glyph_put_char
	call	console.increment_cursor
	pop	hl
	jr	.refresh_line_loop
.restore:
	pop	hl
	ld	(console_cursor_xy), hl
	ret

.handle_key_enter:
	ld	hl, (console_cursor_xy)
	call	.glyph_blank
	ld	iy, (console_ring)
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (console_color)
	ld	c, a
	ld	a, (hl)
	or	a, a
	ld	hl, (console_cursor_xy)
	call	nz, .glyph_put_char
	
	ld	iy, (console_ring)
	ld	de, console_string
	ld	bc, 0
.loop:
	push	bc
	call	ring_buffer.read
	pop	bc
	jr	z, .finish
	or	a, a
	jr	z, .loop
	ld	(de), a
	inc	de
	inc	bc
	jr	.loop
.finish:
	xor	a, a
	ld	(de), a
	push	bc
	call	.new_line
; execute the instruction now
	pop	bc
	ld	a, b
	or	a, c
	jr	z, .no_command
; check the command
; if command = reboot, we'll do rst 0h
	ld	de, console_string
	ld	hl, .REBOOT
	ld	b, (hl)
	inc	hl
.check:
	ld	a, (de)
	cp	a, (hl)
	jr	nz, .not_found
	inc	hl
	inc	de
	djnz	.check
	jp	kinit
.not_found:
	
	ld	bc, .UNKNOW_INSTR
	call	.write_string
	call	.new_line
.no_command:
	ld	hl, (console_cursor_xy)
	jp	.prompt
	
.handle_key_right:
	ld	iy, (console_ring)
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (hl)
	or	a, a
	ret	z
	call	ring_buffer.increment
	ld	(iy+RING_BUFFER_HEAD), hl
	jp	console.increment_cursor

.handle_key_left:
	ld	iy, (console_ring)
	ld	hl, (iy+RING_BUFFER_HEAD)
	call	ring_buffer.decrement
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(iy+RING_BUFFER_HEAD), hl
	jp	console.decrement_cursor

.write_string:
; bc is string
	ld	a, (bc)
	or	a, a
	ret	z
	cp	a, 10	; '\n'
	jr	z, .write_string_new_line
	push	bc
	call	.write_char
	pop	bc
	inc	bc
	jr	.write_string
.write_string_new_line:
	push	bc
	call	.new_line
	pop	bc
	inc	bc
	jr	.write_string
	
.write_char:
	push	af
	ld	iy, (console_ring)
	call	ring_buffer.write
	ld	hl, (console_cursor_xy)
	call	.glyph_blank
	ld	hl, (console_cursor_xy)
	ld	a, (console_color)
	ld	c, a
	pop	af
	call	.glyph_put_char
	jp	console.increment_cursor

.handle_key_clear:
.clear:
; reset cursor xy and put prompt
	ld	hl, $E40000
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	bc, 76800
	ldir
	or	a, a
	sbc	hl, hl
	jr	.prompt
	
.init:
	ld	de, DRIVER_VIDEO_PALETTE
	ld	hl, .PALETTE
	ld	bc, 20
	ldir
	ld	hl, .PALETTE_SPLASH
	ld	bc, 16
	ldir
	ld	hl, $E40000
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	bc, 76800
	ldir
	ld	iy, $D30000
	ld	(console_ring), iy
	ld	a, 1
	ld	(console_color), a
	ld	a, $FD
	ld	(console_key), a
	xor	a, a
	ld	(console_flags), a
	call	ring_buffer.create
	
.init_splash:
	ld	hl, 5*256
	ld	(console_cursor_xy), hl
	ld	h, 0
	ld	e, l
	ld	bc, .SPLASH
	call	.blit
	ld	hl, 2*256+10
	call	kname
	call	.glyph_put_string
	ret
	
.prompt:
	push	hl
	ld	iy, (console_ring)
	call	ring_buffer.flush
	pop	hl
	ld	bc, 8
	add	hl, bc
	ld	(console_cursor_xy), hl
	sbc	hl, bc
	ld	bc, .PROMPT

.glyph_put_string:
; bc = string, hl xy
	call	.glyph_adress
.glyph_string_loop:
	ld	a, (bc)
	or	a, a
	ret	z
	push	de
	push	bc
	ld	h, a
	cp	a, '\'
	jr	nz, .glyph_write_color
	inc	bc
	ld	a, (bc)
	cp	a, 'e'
	jr	nz, .glyph_write_color
	inc	bc
	ld	a, (bc)
	cp	a, '['
	jr	z, .escape_sequence
.glyph_write_color:
	ld	a, (console_color)
	ld	c, a
	ld	a, h
	call	.glyph_put_char_entry
	pop	bc
	pop	de
	ld	hl, 6
	add	hl, de
	ex	de, hl
	inc	bc
	jr	.glyph_string_loop
.escape_sequence:
	inc	bc
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

.glyph_put_char:
; h = y , l = x (console 50x20), c is color, a is char
; y isdb 11, x is 6 in height/width
; x * 6 + (y*11)*320 + buffer (3520)
	call	.glyph_adress
; a = char, c = color, hl = screen
.glyph_put_char_entry:
	or	a, a
	sbc	hl, hl
	ld	l, a
	ld	a, c
	add	hl, hl
	add	hl, hl
	ld	bc, .TRANSLATION_TABLE
	add	hl, bc
	ld	hl, (hl)
; hl = font.adress (vstart offset, vsize (bytes), hsize(bytes))
; de = buffer adress
	ld	c, (hl)	; voffset
	ld	b, 160
	mlt	bc
	ex	de, hl
	add	hl, bc
	add	hl, bc	; voffset*320+buffer
	ex	de, hl
	inc	hl
	ld	b, (hl)	; vsize
	ld	c, a
; de = start buffer
	inc	hl
	inc	hl
; hl = start glyph
; a = color, horiz is 6, vertical is b
	ex	de, hl
	push	hl
	ex	(sp), iy
.glyph_char_loop:
	ld	a, (de)
	or	a, a
	jr	z, $+3
	ld	(hl), c
	inc	hl
	inc	de
	ld	a, (de)
	or	a, a
	jr	z, $+3
	ld	(hl), c
	inc	hl
	inc	de
	ld	a, (de)
	or	a, a
	jr	z, $+3
	ld	(hl), c
	inc	hl
	inc	de
	ld	a, (de)
	or	a, a
	jr	z, $+3
	ld	(hl), c
	inc	hl
	inc	de
	ld	a, (de)
	or	a, a
	jr	z, $+3
	ld	(hl), c
	inc	hl
	inc	de
	ld	a, (de)
	or	a, a
	jr	z, $+3
	ld	(hl), c
	inc	hl
	inc	de
	ld	hl, 320
	ex	de, hl
	add	iy, de
	ex	de, hl
	lea	hl, iy + 0
	djnz	.glyph_char_loop
	pop	iy
	ret
	
.shift_up:
	ld	de, (DRIVER_VIDEO_SCREEN)
	or	a, a
	sbc	hl, hl
	add	hl, de
	ld	bc, 11*320
	add	hl, bc
	ld	bc, 76800 - 11*320
	ldir
	ld	hl, $E40000
	ld	bc, 11*320
	ldir
	ret

.blit:
; hl,e ; bc is data as hsize,vsize,data
	ld	d, 160
	mlt	de
	add	hl, de
	add	hl, de
	ld	de, (DRIVER_VIDEO_SCREEN)
	add	hl, de
	ld	a, (bc)
	ld	e, a
	inc	bc
	ld	a, (bc)
; e = h, a = vsize
	push	bc
	inc.s	bc
	ld	b, a
	ld	c, e
	pop	de
.blit_loop:
	push	bc
	push	hl
	ld	b, 0
	ex	de, hl
	ldir
	ex	de, hl
	pop	hl
	ld	c, 64
	inc	b
	add	hl, bc
	pop	bc
	djnz	.blit_loop
	ret

.COMMAND:
 db 2	; command count
 dl .REBOOT
 dl .ECHO
 
.REBOOT:
 db 7, "r", "e", "b", "o", "o", "t", 0
.ECHO:
 db 5, "e", "c", "h", "o"
 
.PROMPT:
 db "\e[31mroot\e[39m:\e[34m~\e[39m# ", 0

.BLINK:
 db "_"
	
.SPLASH:
db 64,65
include 'logo.asm'
 
.PALETTE:
; default = foreground = \e[39m
 dw $0000	; background
 dw $FFFF	; foreground
 dw $0000	; color 1	; \e[30m
 dw $4000	; color 2
 dw $1D83	; color 3
 dw $B343	; color 4
 dw $18D6	; color 5
 dw $1D96	; color 6
 dw $B596	; color 7
 dw $FFFF	; color 8	; \e[37m

.PALETTE_SPLASH:
 dw $3000 ;  // 00 :: rgba(95,0,3,255)
 dw $0000 ;  // 01 :: rgba(0,0,0,255)
 dw $7200 ;  // 02 :: rgba(233,128,0,255)
 dw $4C20 ;  // 03 :: rgba(154,8,2,255)
 dw $DCE0 ;  // 04 :: rgba(189,61,1,255)
 dw $D060 ;  // 05 :: rgba(167,28,3,255)
 dw $6560 ;  // 06 :: rgba(207,90,0,255)
 dw $EDA0 ;  // 07 :: rgba(220,111,0,255)

.UNKNOW_INSTR:
 db "command not found", 0

include 'gohufont.inc'

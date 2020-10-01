define	CONSOLE_STYLE		$0
define	CONSOLE_FG_COLOR	$1
define	CONSOLE_BG_COLOR	$2
define	CONSOLE_CURSOR		$3
define	CONSOLE_CURSOR_COL	$3
define	CONSOLE_CURSOR_ROW	$4
define	CONSOLE_BLINK		$6
define	CONSOLE_FLAGS		$7
define	CONSOLE_KEY		$8
define	CONSOLE_ESC_OFFSET	$9	; describe the current offset inside the buffer (3 bytes for fast read)
define	CONSOLE_ESC_BUFFER	$C	; 9 bytes max, two paramaters + 1 output + 1 master (partial buffer)
define	CONSOLE_ESC_BUFFER_MAX_SIZE	9
define	CONSOLE_TAKEOVER	$15
define	CONSOLE_LINE_HEAD	$18
define	CONSOLE_LINE		$20

define	CONSOLE_LINE_SIZE	$E0

define	CONSOLE_FLAGS_ALPHA	0
define	CONSOLE_FLAGS_2ND	1
define	CONSOLE_FLAGS_MODE	2	; 2 and 3 are for color mode

define	CONSOLE_FLAGS_THREADED	5
define	CONSOLE_FLAGS_SILENT	6
define	CONSOLE_FLAGS_ESC	7	; we are writing an esc sequence

define	CONSOLE_BLINK_RATE	1
define	CONSOLE_CURSOR_MAX_COL	50
define	CONSOLE_CURSOR_MAX_ROW	20

.phy_init:
	ld	bc, .phy_mem_ops
	ld	hl, .CONSOLE_DEV
; inode capabilities flags
; single character device, (so write / read / ioctl), no seek capabilities exposed
; 	ld	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
; 	jp	kvfs.inode_device
	ret

.CONSOLE_DEV:
 db "/dev/console", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	jp	.phy_ioctl

.phy_read:
; file offset hl, buffer is de, bc
; return hl = number of bytes read
	push	bc
	ld	hl, $E40000
	ldir
	pop	hl
	ret

.phy_write:
; write string pointed by hl, file offset de, bc bytes
; write to the character device console
; return hl = number of bytes writed
	push	bc
	push	hl
	ex	(sp), ix
	call	.phy_write_ex
	pop	ix
	pop	hl
	ret

.phy_write_ex:
	ld	iy, console_dev
	bit	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	jr	nz, .phy_escape_sequence_ex
; find address of the glyph on the screen
.phy_write_address:
	ld	hl, (iy+CONSOLE_CURSOR)
	call	.glyph_adress
.phy_write_loop:
	ld	a, (ix+0)
	inc	ix
	cp	a, $20
	jr	c, .phy_special_ascii
; write the char read
	push	bc
	bit	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
	call	z, .glyph_char_address
	pop	bc
; increment cursor position now
	lea	hl, iy+CONSOLE_CURSOR_COL
	inc	(hl)
	ld	a, CONSOLE_CURSOR_MAX_COL
	cpi
; if z = need todo phy_new_line
; ret if po
; continue else
	jr	z, .phy_write_new_line
	jp	pe, .phy_write_loop
	ret
.phy_write_new_line_ex:
	cpi
.phy_write_new_line:
	push	af
	call	.phy_new_line
	pop	af
	ret	po
	jr	.phy_write_address
	
.phy_special_ascii:
	cp	a, 10
	jr	z, .phy_write_new_line_ex
	cp	a, $1B
	jr	nz, .phy_write_loop

; process an escape sequence sequentially, from string
.phy_escape_sequence:
	set	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	cpi
	ret	po
.phy_escape_sequence_ex:
	ld	de, (iy+CONSOLE_ESC_OFFSET)
	lea	hl, iy+CONSOLE_ESC_BUFFER
	add	hl, de
	ex	de, hl
	lea	hl, ix+0
.phy_escape_parse:
	inc	ix
	inc	(iy+CONSOLE_ESC_OFFSET)
; we are checking offset, allowed between 0 and 8
	ld	a, CONSOLE_ESC_BUFFER_MAX_SIZE - 1
	cp	a, (iy+CONSOLE_ESC_OFFSET)
	jr	c, .phy_escape_flush	; ie error out, and ignore
	ld	a, (hl)
	ldi
	jp	po, .phy_single_escape
	cp	a, $5B
	jr	z, .phy_escape_parse
	cp	a, $40
; this is a final digit
	jr	c, .phy_escape_parse
	call	.phy_escape_process
	jr	.phy_write_address

.phy_escape_flush:
	res	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	ld	(iy+CONSOLE_ESC_OFFSET), 0
	ret
	
.phy_single_escape:
	cp	a, $5B
	ret	z
	cp	a, $40
	ret	c
	
; actually apply a escape sequence
.phy_escape_process:
	ld	de, 0
	res	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	ld	(iy+CONSOLE_ESC_OFFSET), e
	lea	hl, iy+CONSOLE_ESC_BUFFER
; read the type of the escape sequence
	ld	a, (hl)
	cp	a, '['
	jr	z, .phy_escape_CSI
; other sequence, not *yet* supported
.phy_escape_unknow:
; return, quite for byte, or return to parse for *string*
	ret

.phy_escape_CSI_intermediate:
; store first param to h
	ld	d, e
	ld	e, 0
	jr	.phy_escape_CSI
.phy_escape_CSI_param:
	push	de
	ld	d, 10
	mlt	de
	add	a, e
	pop	de
	ld	e, a
.phy_escape_CSI:
; read parameter
; 0x30–0x3F value
; 0x20–0x2F intermediate
; final 0x40–0x7E
	inc	hl
	ld	a, (hl)
	sub	a, $30
; this is intermediate
	cp	a, $0B
	jr	z, .phy_escape_CSI_intermediate
	cp	a, $10
	jr	c, .phy_escape_CSI_param
	
.phy_escape_CSI_final:
; depending from the  value
; let's do some shady stuff
	cp	a, 'm' - $30	; this is sgr
	jr	z, .phy_CSI_sgr
	sub	a, $11
	sbc	hl, hl
	ld	l, a
; unsupported above 11
	cp	a, 11
	ret	nc
	add	hl, hl
	add	hl, hl
	push	bc
	ld	bc, .PHY_CSI_JUMP_TABLE
	add	hl, bc
	pop	bc
	ld	hl, (hl)
	jp	(hl)

.phy_CSI_sgr:
; not much supported
	ld	a, e
	or	a, a
	jr	z, .phy_CSI_sgr_default
	cp	a, 40
	jr	nc, .phy_CSI_sgr_background
.phy_CSI_sgr_foreground:
	cp	a, 39
	jr	z, .phy_CSI_sgr_fgd_color
	sub	a, 30 - 2
	ld	(iy+CONSOLE_FG_COLOR), a
	ret
.phy_CSI_sgr_background:
	cp	a, 49
	jr	z, .phy_CSI_sgr_bgd_color
	sub	a, 40 - 2
	ld	(iy+CONSOLE_BG_COLOR), a
	ret
.phy_CSI_sgr_fgd_color:
	ld	(iy+CONSOLE_FG_COLOR), $01
	ret
.phy_CSI_sgr_bgd_color:
	ld	(iy+CONSOLE_BG_COLOR), $00
	ret
.phy_CSI_sgr_default:
	ld	hl, $000100
	ld	(iy+CONSOLE_STYLE), hl
	ret

.PHY_CSI_JUMP_TABLE:
 dd	.phy_cursor_up
 dd	.phy_cursor_down
 dd	.phy_cursor_forward
 dd	.phy_cursor_back
 dd	.phy_cursor_next_line	; next line
 dd	.phy_cursor_prev_line	; previous line
 dd	.phy_cursor_habs	; 
 dd	.phy_cursor_position
 dd	.phy_none
 dd	.phy_erase_display	; erase in display
 dd	.phy_erase_line		; erase in line

.phy_cursor_down:
	lea	hl, iy+CONSOLE_CURSOR_ROW
	ld	a, e
	or	a, a
	jr	nz, $+3
	inc	a
	add	a, (hl)
	ld	(hl), a
	sub	a, CONSOLE_CURSOR_MAX_ROW
	ret	c
	ld	a, CONSOLE_CURSOR_MAX_ROW - 1
	ld	(hl), a
.phy_none:
	ret
	
.phy_cursor_up:
	lea	hl, iy+CONSOLE_CURSOR_ROW
	ld	a, e
	neg
	jr	nz, $+3
	dec	a
	add	a, (hl)
	ld	(hl), a
	ret	p
	xor	a, a
	ld	(hl), a
	ret

.phy_cursor_forward:
	lea	hl, iy+CONSOLE_CURSOR_COL
	ld	a, e
	or	a, a
	jr	nz, $+3
	inc	a
	add	a, (hl)
.phy_cursor_forward_loop:
	ld	(hl), a
	sub	a, CONSOLE_CURSOR_MAX_COL
	ret	c
	inc	hl
	inc	(hl)
	dec	hl
	jr	.phy_cursor_forward_loop

.phy_cursor_back:
	lea	hl, iy+CONSOLE_CURSOR_COL
; e = count to go back
	ld	a, e
	neg
	jr	nz, $+3
	dec	a
	add	a, (hl)
.phy_cursor_back_loop:
	ld	(hl), a
	ret	p
	inc	hl
	dec	(hl)
	dec	hl
	add	a, CONSOLE_CURSOR_MAX_COL
	jr	.phy_cursor_back_loop

.phy_cursor_prev_line:
	call	.phy_cursor_up
	dec	hl
	ld	(hl), 0
	ret

.phy_cursor_next_line:
	call	.phy_cursor_down
	dec	hl
	ld	(hl), 0
	ret
	
.phy_cursor_habs:
	lea	hl, iy+CONSOLE_CURSOR_COL
; move cursor to col n absolute
	ld	a, e
	cp	a, CONSOLE_CURSOR_MAX_COL
	jr	nc, $+4
	ld	a, CONSOLE_CURSOR_MAX_COL - 1
	ld	(hl), a
	ret

.phy_cursor_position:
; row is d, col is e, so correct
; there are 0 based, default is 0
	ld	a, e
	or	a, a
	jr	z, $+3
	dec	e
	ld	a, d
	or	a, a
	jr	z, $+3
	dec	d
	ld	(iy+CONSOLE_CURSOR), de
	ret

.phy_new_line:
; iy = console handle
	lea	hl, iy+CONSOLE_CURSOR_COL
.phy_new_line_ex:
	ld	(hl), 0
	inc	hl
	inc	(hl)
	ld	a, (hl)
	cp	a, CONSOLE_CURSOR_MAX_ROW
	ret	nz
	dec	(hl)
.phy_shift_screen:
	bit	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
	ret	nz
	push	bc
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	hl, 11*320
	add	hl, de
	ld	bc, 76800 - 11*320
	ldir
	ld	hl, $E40000
	ld	bc, 11*320
	ldir
	pop	bc
	ret

; CSI n J 	ED 	Erase in Display 	Clears part of the screen. If n is 0 (or missing), clear from cursor to end of screen. If n is 1, clear from cursor to beginning of the screen. If n is 2, clear entire screen (and moves cursor to upper left on DOS ANSI.SYS). If n is 3, clear entire screen and delete all lines saved in the scrollback buffer (this feature was added for xterm and is supported by other terminal applications).
.phy_erase_display:
	dec	e
	jp	m, .phy_erase_cursor_end_screen
	jr	z, .phy_erase_cursor_begin_screen
.phy_erase_all_display:
; reset cursor xy and delete the screen
	ld	hl, KERNEL_MM_NULL
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	bc, 76800
	ldir
	ld	(iy+CONSOLE_CURSOR), bc
	ret
.phy_erase_cursor_end_screen:
	ret
.phy_erase_cursor_begin_screen:
	ret

; CSI n K 	EL 	Erase in Line 	Erases part of the line. If n is 0 (or missing), clear from cursor to the end of the line. If n is 1, clear from cursor to beginning of the line. If n is 2, clear entire line. Cursor position does not change. 
.phy_erase_line:
	dec	e
	jp	m, .phy_erase_cursor_end_line
	jr	z, .phy_erase_cursor_begin_line
.phy_erase_all_line:
	or	a, a
	sbc	hl, hl
; load only row, and we will clear the line
	ld	h, (iy+CONSOLE_CURSOR_ROW)
	call	.glyph_adress
	ld	hl, KERNEL_MM_NULL
	ld	bc, 320*11
	ldir
	ret
.phy_erase_cursor_end_line:
	ret
.phy_erase_cursor_begin_line:
	ret

.phy_ioctl:
	ret
	
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
 
.putchar:
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
	ld	bc, font.TRANSLATION_TABLE
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

define	CONSOLE_STYLE		$0
define	CONSOLE_COLOR		$1
define	CONSOLE_CURSOR		$2
define	CONSOLE_CURSOR_COL	$2
define	CONSOLE_CURSOR_ROW	$3
define	CONSOLE_BLINK		$5
define	CONSOLE_FLAGS		$6
define	CONSOLE_KEY		$7
define	CONSOLE_ESC_BUFFER	$8	; 9 bytes max, two paramaters + 1 output + 1 master (partial buffer)
define	CONSOLE_ESC_OFFSET	$11	; describe the current offset inside the buffer (3 bytes for fast read)
define	CONSOLE_STRING		$14

define	CONSOLE_FLAGS_ALPHA	0
define	CONSOLE_FLAGS_2ND	1
define	CONSOLE_FLAGS_MODE	2	; 2 and 3 are for color mode
define	CONSOLE_FLAGS_ESC	7	; we are writing an esc sequence

define	CONSOLE_BLINK_RATE	1
define	CONSOLE_CURSOR_MAX_COL	50
define	CONSOLE_CURSOR_MAX_ROW	20

.phy_init:
	ld	hl, .phy_mem_ops
	ld	bc, .CONSOLE_DEV
; inode capabilities flags
; single dev block, (so write / read / seek only), no seek capabilities exposed
	ld	a, KERNEL_VFS_BLOCK_DEVICE
	jp	kvfs.create_inode

.CONSOLE_DEV:
 db "/dev/console", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	
.phy_read:
; bc, hl
	ld	de, $E40000
	ex	de, hl
	ldir
	ret

.phy_write:
; write a zero terminated string @bc to the /dev/console special file
	push	hl
	ex	(sp), ix
	call	.phy_write_ex
	pop	ix
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
	ld	c, (iy+CONSOLE_COLOR)
	call	.glyph_char_address
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
	sub	a, $10
	sbc	hl, hl
	ld	l, a
; unsupported above 12
	cp	a, 12
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
	cp	a, 39
	jr	z, .phy_CSI_sgr_default_color
	sub	a, 30 - 2
	ld	(iy+CONSOLE_COLOR), a
	ret
.phy_CSI_sgr_default_color:
	ld	(iy+CONSOLE_COLOR), $01
	ret

.PHY_CSI_JUMP_TABLE:
 dd	.phy_none
 dd	.phy_cursor_up
 dd	.phy_cursor_down
 dd	.phy_cursor_forward
 dd	.phy_cursor_back
 dd	.phy_cursor_next_line	; next line
 dd	.phy_none		; previous line
 dd	.phy_cursor_habs	; 
 dd	.phy_cursor_position
 dd	.phy_none
 dd	.phy_none		; erase in display
 dd	.phy_none		; erase in line

.phy_cursor_down:
.phy_none:
	ret
	
.phy_cursor_up:
	ret

.phy_cursor_forward:
	ld	a, e
	or	a, a
	jr	nz, $+3
	inc	a
	lea	hl, iy+CONSOLE_CURSOR_COL
	add	a, (hl)
.phy_cursor_ffloop:
	ld	(hl), a
	sub	a, CONSOLE_CURSOR_MAX_COL
	ret	c
	inc	hl
	inc	(hl)
	dec	hl
	jr	.phy_cursor_ffloop

.phy_cursor_back:
; e = count to go back
	ld	a, e
	neg
	jr	nz, $+3
	dec	a
	lea	hl, iy+CONSOLE_CURSOR_COL
	add	a, (hl)
.phy_cursor_fbloop:
	ld	(hl), a
	ret	p
	inc	hl
	dec	(hl)
	dec	hl
	add	a, CONSOLE_CURSOR_MAX_COL
	jr	.phy_cursor_fbloop

.phy_cursor_next_line:
	ret
	
.phy_cursor_habs:
	ret

.phy_cursor_position:
; row is d, col is e, so correct
; there are 0 based, default is 0
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

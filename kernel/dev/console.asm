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

define	CONSOLE_FLAGS_ESC	7	; we are writing an esc sequence
define	CONSOLE_CURSOR_MAX_COL	50
define	CONSOLE_CURSOR_MAX_ROW	20

.phy_write:
; write a zero terminated string @bc to the /dev/console special file
	ld	iy, console_dev
; find address of the glyph on the screen
.phy_write_address:
	ld	hl, (iy+CONSOLE_CURSOR)
	call	.glyph_adress
.phy_write_loop:
	ld	a, (bc)
	inc	bc
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
	cp	a, (hl)
	jr	nz, .phy_write_loop
.phy_new_line_string:
	call	.phy_new_line
	jr	.phy_write_address	
	
.phy_special_ascii:
	or	a, a
	ret	z
	cp	a, 10
	jr	z, .phy_new_line_string
	cp	a, $1B
	jr	nz, .phy_write_loop
	
; process an escape sequence sequentially, from string
.phy_escape_sequence_string:
	set	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	ld	de, (iy+CONSOLE_ESC_OFFSET)
	lea	hl, iy+CONSOLE_ESC_BUFFER
	add	hl, de
.phy_escape_parse:
	ld	a, (bc)
	inc	bc
	or	a, a
	ret	z
	ld	(hl), a
	inc	hl
	inc	(iy+CONSOLE_ESC_OFFSET)
	cp	a, $5B
	jr	z, .phy_escape_parse
	cp	a, $40
; this is a final digit
	jr	c, .phy_escape_parse
	call	.phy_escape_process
	jr	.phy_write_address
	
; process the sequence by byte, jump to by the phy_write_char if CONSOLE_FLAGS_ESC is set
.phy_escape_sequence_byte:
	ld	de, (iy+CONSOLE_ESC_OFFSET)
	lea	hl, iy+CONSOLE_ESC_BUFFER
	add	hl, de
	ld	(hl), a
	inc	(iy+CONSOLE_ESC_OFFSET)
	cp	a, $40
	ret	c
	cp	a, $5B
	ret	z

; actually apply a escape sequence
.phy_escape_process:
	res	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	ld	(iy+CONSOLE_ESC_OFFSET), 0
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
	push	bc
	call	.shift_up
	pop	bc
	ret
	
; write a single byte a to the /dev/console special file
.phy_write_byte:
	ld	iy, console_dev
	bit	CONSOLE_FLAGS_ESC, (iy+CONSOLE_FLAGS)
	jp	nz, .phy_escape_sequence_byte
; special byte ?
	cp	a, 10
	jr	z, .phy_new_line
; write it as a single normal byte
	call	.glyph_char
; update cursor now
	lea	hl, iy+CONSOLE_CURSOR_COL
	inc	(hl)
	ld	a, CONSOLE_CURSOR_MAX_COL
	cp	a, (hl)
	ret	nz
	jr	.phy_new_line

define	console_stdin		$D00800
define	console_color		$D00700
define	console_cursor_xy	$D00701
define	console_blink		$D00704
define	console_flags		$D00705
define	console_key		$D00706
define	console_string		$D00707

define	CONSOLE_GLYPH_X		50
define	CONSOLE_GLYPH_Y		20
define	CONSOLE_BLINK_RATE	1
define	CONSOLE_FLAGS_ALPHA	0
define	CONSOLE_FLAGS_2ND	1
define	CONSOLE_FLAGS_MODE	2	; 2 and 3 are for color mode

console:

.init:
	di
	ld	de, DRIVER_VIDEO_PALETTE
	ld	hl, .PALETTE
	ld	bc, 36
	ldir
;	ld	hl, .PALETTE_SPLASH
;	ld	bc, 16
;	ldir
	ld	hl, $E40000
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	bc, 76800
	ldir
	ld	hl, console_color
	ld	(hl), $01
	ld	l, console_flags and $FF
	ld	(hl), c
	inc	hl
	ld	(hl), $FD
	ld	iy, console_stdin
	call	ring_buffer.create
	
.init_splash:
	or	a, a
	sbc	hl, hl
	ld	e, l
	ld	bc, .SPLASH
	call	.blit
	ld	bc, .SPLASH_NAME
	jp	.glyph_string

.run:
	call	.prompt
.run_loop:
; wait keyboard scan
; around 140 ms repeat time
	ld	b, 12
.wait_keyboard:
	push	bc
	ld	hl, DRIVER_KEYBOARD_CTRL
	ld	(hl), 2
	ld	hl, 10
	call	kthread.sleep	; sleep around 10 ms
; keyboard should be okay now
	ld	hl, DRIVER_KEYBOARD_CTRL
	xor	a, a
.wait_busy:
	cp	a, (hl)
	jr	nz, .wait_busy
; check if pressed now == pressed previous
	call	.read_keyboard
	ld	hl, console_key
	cp	a, (hl)
	pop	bc
	jr	nz, .process_key
	djnz	.wait_keyboard
	ld	a, $FD
	ld	hl, console_key
.process_key:
	ld	(hl), a
	call	kvideo.vsync
; wait for vsync, we are in vblank now (are we ?)
; the syscall destroy a but not hl
	ld	iy, console_stdin
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (hl)
	call	.glyph_char
		
	ld	a, (console_key)
	cp	a, $FD
	call	nz, .check_console_key
.blink:
	ld	hl, console_blink
	inc	(hl)
	bit	CONSOLE_BLINK_RATE, (hl)

	ld	a, '_'
	call	z, .glyph_char
	
	jr	.run_loop
	
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

.read_keyboard:
	ld	de, console_flags
	ld	a, (de)
	ld	hl, $F50014
	bit	7, (hl)
	jr	z, .swap_alpha
	or	a, 00000001b
.swap_alpha:
	ld	l, $12
	bit	5, (hl)
	jr	z, .swap_2nd
	or	a, 00000010b
.swap_2nd:
	ld	(de), a
	ld	de, .KEYBOARD_KEY
	ld	c, 7
.loop1:
	ld	a, (hl)
	ld	b, 8
.loop0:
	rra
	jr	c, .found_key
.back:
	inc	de
	djnz	.loop0
	inc	hl
	inc	hl
	dec	c
	jr	nz, .loop1
	ld	a, $FD
	ret
.found_key:
	ld	iyl, a
	ld	a, (de)
	cp	a, $FD
	ret	nz
	ld	a, iyl
	jr	.back

; console cursor routine ;

.decrement_cursor:
	ld	hl, (console_cursor_xy)
	dec	l
	jp	p, .no_prev_line
	dec	h
	ret	m
	ld	l, CONSOLE_GLYPH_X - 1
.no_prev_line:
	ld	(console_cursor_xy), hl
	ret	
	
.increment_cursor:
	ld	hl, (console_cursor_xy)
	ld	a, l
	cp	a, CONSOLE_GLYPH_X-1
	jr	z, .new_line_entry
	inc	l
	ld	(console_cursor_xy), hl
	ret
	
.new_line:
; return hl = console_cursor_xy
	ld	hl, (console_cursor_xy)
.new_line_entry:	
; x = l, y = h
	ld	a, h
	cp	a, CONSOLE_GLYPH_Y - 1
	jr	z, .new_line_shift
	inc	h
.new_line_shift:
	ld	l, 0
	push	hl
	call	z, .shift_up
	pop	hl
	ld	(console_cursor_xy), hl
	ret

.handle_key_del:
	ld	iy, console_stdin
	call	ring_buffer.remove_head
	ret	z
	jr	.refresh_line
	
.handle_key_mode:
; backspace behaviour
	ld	iy, console_stdin
	call	ring_buffer.remove
	ret	z
	ld	hl, (console_cursor_xy)
	call	console.decrement_cursor

.refresh_line:
; bc = string, hl xy
	ld	hl, (console_cursor_xy)
	push	hl
	call	.glyph_adress
	ld	iy, console_stdin
	ld	hl, (iy+RING_BUFFER_HEAD)
.refresh_line_loop:
	ld	a, (hl)
	or	a, a
	jr	z, .refresh_line_restore
	call	ring_buffer.increment
	push	hl
	ld	hl, console_color
	ld	c, (hl)
	inc	hl
	inc	(hl)
	call	.glyph_char_address
	pop	hl
	ld	a, (console_cursor_xy)
	cp	a, CONSOLE_GLYPH_X
	jr	nz, .refresh_line_loop
.refresh_new_line:
	push	hl
	call	.new_line
; recompute adress from console_cursor
	call	.glyph_adress
	pop	hl
	jr	.refresh_line_loop
.refresh_line_restore:
	call	.glyph_blank_address
	pop	hl
	ld	(console_cursor_xy), hl
	ret
	
.handle_key_enter:
	call	.new_line
	ld	iy, console_stdin
	ld	de, console_string
	ld	bc, 0
.handle_enter_string:
	push	bc
	call	ring_buffer.read
	or	a, a
	ld	(de), a
	jr	z, .finish
	inc	de
	pop	bc
	inc	bc
	jr	.handle_enter_string
.finish:
; execute the instruction now
	pop	bc
	ld	a, b
	or	a, c
	jr	z, .clean_command
; check the command
; if command = reboot, we'll do rst 0h
	ld	hl, .REBOOT
	call	.check_builtin
	jp	z, kinit
	ld	hl, .COLOR
	call	.check_builtin
	jr	z, .color
	ld	hl, .UPTIME
	call	.check_builtin
	jp	z, .uptime
	ld	hl, .SHUTDOWN
	call	.check_builtin
	jr	z, .shutdown
	ld	bc, .UNKNOW_INSTR
	call	.glyph_string
.clean_command:
	ld	hl, (console_cursor_xy)
	jp	.prompt
	
.check_builtin:
	ld	de, console_string
	ld	bc, 0
	ld	c, (hl)
	inc	hl
.check_builtin_compare:
	ld	a, (de)
	cpi
	ret	nz
	inc	de
	jp	pe, .check_builtin_compare
	ret

.shutdown:
	call	kpower.cycle_off
	jr	.clean_command
	
.color:
	ld	hl, (console_cursor_xy)
; 24 * 8 + 4 * 7
	call	.glyph_adress
; de = address
	ld	hl, 40
	add	hl, de
	ex	de, hl
	push	de
	ld	a, 2
	ld	c, 8
.color_block_b:
	ld	b, 24
.color_block:
	ld	(de), a
	inc	de
	djnz	.color_block
	inc	a
	dec	c
	inc	de
	inc	de
	inc	de
	inc	de
	jr	nz, .color_block_b
	pop	de
	ld	hl, 320
	add	hl, de
	ex	de, hl
	ld	a, 10
.color_copy_block:
	push	hl
	ld	bc, 220
	ldir
	ld	hl, 100
	add	hl, de
	ex	de, hl
	pop	hl
	dec	a
	jr	nz, .color_copy_block	
	jr	.finish_resume
.uptime:
; change this to load atomically the 32 bits register please
	ld	bc, .UPTIME_STR
	ld	hl, (console_cursor_xy)
	push	hl
	push	hl
	push	hl
	push	hl
	call	.glyph_string
	pop	hl
	ld	l, 9
	ld	a, 4
	ld	bc, (DRIVER_RTC_COUNTER_DAY)
	call	.glyph_integer_format
	pop	hl
	ld	l, 22
	ld	a, 2
	ld	bc, (DRIVER_RTC_COUNTER_HOUR)
	call	.glyph_integer_format
	pop	hl
	ld	l, 26
	ld	a, 2
	ld	bc, (DRIVER_RTC_COUNTER_MINUTE)
	call	.glyph_integer_format
	pop	hl
	ld	l, 30
	ld	a, 2
	ld	bc, (DRIVER_RTC_COUNTER_SECOND)
	call	.glyph_integer_format
	call	.new_line
	jp	.prompt
.handle_key_up:
	ret

.handle_key_right:
	ld	iy, console_stdin
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (hl)
	or	a, a
	ret	z
	call	ring_buffer.increment
	ld	(iy+RING_BUFFER_HEAD), hl
	jp	console.increment_cursor

.KEY_RIGHT_CSI:
 db $1B, "[C",0

.handle_key_left:
	ld	iy, console_stdin
	ld	hl, (iy+RING_BUFFER_HEAD)
	call	ring_buffer.decrement
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(iy+RING_BUFFER_HEAD), hl
	jp	console.decrement_cursor
	
.KEY_LEFT_CSI:
 db $1B, "[D",0
  
.check_console_key:
	cp	a, $FC
	jr	z, .handle_key_clear

	cp	a, $FE
	jr	z, .handle_key_enter
	
	cp	a, $F9
	jr	z, .handle_key_right
	
	cp	a, $FA
	jr	z, .handle_key_left
	
	cp	a, $FF
	jr	z, .handle_key_del

	cp	a, $F7
	jr	z, .handle_key_mode
	
	or	a, a
	ret	m
	
.handle_key_char:
	ld	hl, console_flags
; reset flags
	ld	bc, .KEYMAP_NO_MOD
	bit	0, (hl)
	jr	z, .handle_key_no_mod
	ld	bc, .KEYMAP_ALPHA
.handle_key_no_mod:
	ld	(hl), 0
	sbc	hl, hl
	ld	l, a
	add	hl, bc
	ld	a, (hl)
; read color

.write_char:
	push	af
	ld	iy, console_stdin
	call	ring_buffer.write
	pop	af
	call	.glyph_char
	jp	console.increment_cursor

.handle_key_clear:
.clear:
; reset cursor xy and put prompt
	ld	hl, $E40000
	ld	de, (DRIVER_VIDEO_SCREEN)
	ld	bc, 76800
	ldir
; actually make hl zero, slower but save 1 byte
	mlt	hl
	ld	(console_cursor_xy), hl
	
.prompt:
	ld	iy, console_stdin
	call	ring_buffer.flush
	ld	bc, .PROMPT
; fall into glyph_string

include 'console_glyph.asm'

.COMMAND:
 db 2	; command count
 dl .REBOOT
 dl .ECHO
 dl .COLOR
 
.REBOOT:
 db 7, "r", "e", "b", "o", "o", "t", 0
.ECHO:
 db 5, "e", "c", "h", "o"
.COLOR:
 db 6, "c", "o", "l", "o", "r", 0
.UPTIME:
 db 7, "u", "p", "t", "i", "m", "e", 0
.SHUTDOWN:
 db 9, "s", "h", "u", "t", "d", "o", "w", "n", 0
 
.UPTIME_STR:
 db "Up since 0000 day(s), 00h 00m 00s", 0

.PROMPT:
 db $1B,"[31mroot",$1B,"[39m:", $1B,"[34m~", $1B, "[39m# ", 0
 
.BLINK:
 db "_"
	
.SPLASH:
db 64,65
include 'logo.asm'
 
.SPLASH_NAME:
; y 2, x 10, then y 5, x 0
 db $1B, "[3;11H", "Sorcery-0.0.1a-slp-d738d5b", $1B, "[6;1H", 0
 
.PALETTE:
; default = foreground = \e[39m
 dw $0000	; background
 dw $FFFF	; foreground
 dw $1084	; color 0	; \e[30m
 dw $7C00	; color 1
 dw $03E0	; color 2
 dw $7FE0	; color 3
 dw $221F	; color 4
 dw $7C1F	; color 5
 dw $421F	; color 6
 dw $FFFF	; color 7	; \e[37m
; 30	Black , rgb
; 31	Red
; 32	Green
; 33	Yellow
; 34	Blue
; 35	Magenta
; 36	Cyan
; 37	White

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
 db "command not found", 10,0

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
 
include 'gohufont.inc'

define	console_stdin		$D00800
define	console_dev		$D00700
define	console_style		$D00700
define	console_fg_color	$D00701
define	console_bg_color	$D00702
define	console_cursor_xy	$D00703
define	console_blink		$D00706
define	console_flags		$D00707
define	console_key		$D00708
define	console_takeover	$D00715
define	console_string		$D00718

console:

.nmi_takeover:
	ld	iy, console_dev
	res	CONSOLE_FLAGS_THREADED, (iy+CONSOLE_FLAGS)
	ld	hl, nmi_console
	jr	.fb_takeover_entry
	
.fb_takeover:
	di
	ld	iy, console_dev
	set	CONSOLE_FLAGS_THREADED, (iy+CONSOLE_FLAGS)
; check CONSOLE_TAKEOVER is null
	ld	hl, (iy+CONSOLE_TAKEOVER)
	add	hl, de
	or	a, a
	sbc	hl, de
	ret	nz
; take control of the video driver mutex
	ld	hl, 64
	call	kmalloc
	ret	c
.fb_takeover_entry:
	ld	(iy+CONSOLE_TAKEOVER), hl
	ex	de, hl
; save LCD state
	ld	hl, DRIVER_VIDEO_SCREEN
	ld	bc, 16
	ldir
; and now the palette state
	ld	hl, DRIVER_VIDEO_PALETTE
	ld	c, 36
	ldir
	ld	hl, KERNEL_INTERRUPT_ISR_DATA_VIDEO
	ld	c, 6
	ldir
; 58 + 3 bytes in grand total, free 3 bytes
; mark console as present
	res	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
; init the screen now
	push	de
	call	.init_screen
	ld	a, (iy+CONSOLE_FLAGS)
	bit	CONSOLE_FLAGS_THREADED, a
	ld	iy, .thread
	call	nz, kthread.create
	pop	hl
; carry if error
	ret	c
; take lcd mutex control
	ld	(hl), iy
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	ld	(hl), $FF
	inc	hl
	ld	(hl), iy
	bit	CONSOLE_FLAGS_THREADED, a
	ret	z
	ei
	ret
	
.fb_restore:
; need to exit the console thread (signal are efficient, since you can raise to your own thread)
; restore the mutex and the propriety
	ld	iy, console_dev
	set	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
	ld	hl, (iy+CONSOLE_TAKEOVER)
; restore status
	ld	de, DRIVER_VIDEO_SCREEN
	ld	bc, 16
	ldir
; restore palette
	ld	de, DRIVER_VIDEO_PALETTE
	ld	c, 36
	ldir
; restore mutex
	ld	de, KERNEL_INTERRUPT_ISR_DATA_VIDEO
	ld	c, 6
	ldir
; restore keyboard ?
	ld	a, DRIVER_KEYBOARD_SCAN_CONTINUOUS
	ld	(DRIVER_KEYBOARD_CTRL), a
; kill the thread now
	ld	de, (hl)
	ld	hl, (iy+CONSOLE_TAKEOVER)
	ld	(iy+CONSOLE_TAKEOVER), bc
	call	kfree
	ex	de, hl
	ld	c, (hl)
	ld	a, SIGKILL
	jp	signal.kill
	
.init:
	ld	bc, $0100
	di
	ld	hl, console_dev
	ld	(hl), bc
	ld	l, console_flags and $FF
	ld	(hl), c
	set	CONSOLE_FLAGS_SILENT, (hl)
	inc	hl
	ld	(hl), $FD
	ld	l, console_takeover and $FF
	dec	b
	ld	(hl), bc
	ld	iy, console_stdin
	call	ring_buffer.create
	jp	.phy_init

.init_screen:
	ld	a, (console_dev+CONSOLE_FLAGS)
	add	a, a
	ret	m
	ld	hl, .PALETTE
	ld	de, DRIVER_VIDEO_PALETTE
	ld	bc, 36
	ldir
	call	video.clear_screen
	or	a, a
	sbc	hl, hl
	ld	e, l
	ld	bc, .SPLASH
	call	.blit
	ld	c, 37
	ld	hl, .SPLASH_NAME
	jp	.phy_write

.thread:
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
.process_key:
	ld	(hl), a
	call	video.vsync
; wait for vsync, we are in vblank now (are we ?)
; the syscall destroy a but not hl
	ld	iy, console_stdin
	ld	hl, (iy+RING_BUFFER_HEAD)
	ld	a, (hl)
	ld	hl, console_blink
	bit	CONSOLE_BLINK_RATE, (hl)
	call	z, .putchar
		
	ld	a, (console_key)
	cp	a, $FD
	call	nz, .handle_console_stdin
.blink:
	ld	hl, console_blink
	inc	(hl)
	bit	CONSOLE_BLINK_RATE, (hl)

	ld	a, '_'
	call	z, .putchar
	
	jr	.run_loop
	
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

.handle_key_enter:
	ld	iy, console_dev
	call	.phy_new_line
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
	inc	c
	ld	a, c
	cp	a, 63
	jr	nz, .handle_enter_string
	push	bc
	call	ring_buffer.flush
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
	ld	hl, .ECHO
	call	.check_builtin
	jr	z, .echo
	ld	hl, .EXIT
	call	.check_builtin
	jp	z, .fb_restore
	ld	hl, .UNKNOW_INSTR
	ld	bc, 18
	call	.phy_write
.clean_command:
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
.echo:
	ld	hl, console_string + 5
	xor	a, a
	ld	bc, 0
	cpir
	sbc	hl, hl
	sbc	hl, bc
	push	hl
	pop	bc
	cpi
	jp	po, .clean_command
	ld	hl, console_string + 5
	call	.phy_write
	call	.phy_new_line	
	jr	.clean_command

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
	ld	c,220
.color_copy_block:
	ldir
	ld	c, 100
	ex	de, hl
	add	hl, bc
	ex	de, hl
	ld	c,220
	sbc	hl, bc
	dec	a
	jr	nz, .color_copy_block
	ld	iy, console_dev
	call	.phy_new_line
	jp	.prompt
.uptime:
	ld	hl, (DRIVER_RTC_COUNTER_SECOND)
	push	hl
	ld	hl, (DRIVER_RTC_COUNTER_MINUTE)
	push	hl
	ld	hl, (DRIVER_RTC_COUNTER_HOUR)
	push	hl
	ld	hl, (DRIVER_RTC_COUNTER_DAY)
	push	hl
	ld	hl, .UPTIME_STR
	push	hl
	ld	hl, console_string
	push	hl
	call	_boot_sprintf_safe
	ld	hl, 18
	add	hl, sp
	ld	sp, hl
	ld	hl, console_string
	ld	bc, 34
	call	.phy_write
	jp	.prompt

.handle_key_del:
	call	ring_buffer.remove_head
	ret	z
	jr	.refresh_line
	
.handle_key_mode:
; backspace behaviour
	call	ring_buffer.remove
	ret	z
	ld	hl, .KEY_LEFT_CSI
	ld	bc, 3
	call	.phy_write

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
	ld	hl, console_cursor_xy
; 	ld	c, (hl)
; 	inc	hl
	inc	(hl)
	call	.glyph_char_address
	pop	hl
	ld	a, (console_cursor_xy)
	cp	a, CONSOLE_CURSOR_MAX_COL
	jr	nz, .refresh_line_loop
.refresh_new_line:
	push	hl
	ld	hl, console_cursor_xy
	call	.phy_new_line_ex
; recompute adress from console_cursor
	ld	hl, (console_cursor_xy)
	call	.glyph_adress
	pop	hl
	jr	.refresh_line_loop
.refresh_line_restore:
	call	.glyph_char_address
	pop	hl
	ld	(console_cursor_xy), hl
	ret  
  
.handle_console_stdin:
	cp	a, $FC
	jr	z, .handle_key_clear
	cp	a, $FE
	jp	z, .handle_key_enter
	cp	a, $FF
	jr	z, .handle_key_del
	cp	a, $F7
	jr	z, .handle_key_mode
	ld	hl, (iy+RING_BUFFER_HEAD)
	cp	a, $F9
	jr	z, .handle_key_right
	cp	a, $FA
	jr	z, .handle_key_left
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
	bit	1, (hl)
	jr	z, .handle_key_no_2nd
	ld	bc, .KEYMAP_2ND
.handle_key_no_2nd:
	ld	(hl), 0
	sbc	hl, hl
	ld	l, a
	add	hl, bc
	ld	a, (hl)
	push	hl
	call	ring_buffer.write
; putchar(a)
	pop	hl
	ld	bc, 1
	jp	.phy_write

.handle_key_up:
	ret

.handle_key_right:
	ld	a, (hl)
	or	a, a
	ret	z
	call	ring_buffer.increment
	ld	(iy+RING_BUFFER_HEAD), hl
	ld	hl, .KEY_RIGHT_CSI
	ld	bc, 3
	jp	.phy_write

.KEY_RIGHT_CSI:
 db $1B, "[C"

.handle_key_left:
	call	ring_buffer.decrement
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(iy+RING_BUFFER_HEAD), hl
	ld	hl, .KEY_LEFT_CSI
	ld	bc, 3
	jp	.phy_write
	
.KEY_LEFT_CSI:
 db $1B, "[D"
	
.handle_key_clear:
.clear:
; reset cursor xy and put prompt
	ld	hl, .KEY_CLEAR_CSI
	ld	bc, 4
	call	.phy_write

.prompt:
	ld	iy, console_stdin
	call	ring_buffer.flush
	ld	bc, 28
	ld	hl, .PROMPT
	jp	.phy_write

.KEY_CLEAR_CSI:
 db $1B, "[2J"	
	
.COMMAND:
 dl .REBOOT
 dl .ECHO
 dl .COLOR
 dl .EXIT
 
.REBOOT:
 db 7, "reboot", 0
.ECHO:
 db 5, "echo "
.COLOR:
 db 6, "color", 0
.UPTIME:
 db 7, "uptime", 0
.SHUTDOWN:
 db 9, "shutdown", 0
.EXIT:
 db 5, "exit", 0
 
.UPTIME_STR:
; db "Up since 0000 day(s), 00h 00m 00s", 0
 db "Up since %04d day(s), %02dh %02dm %02ds" , 10, 0
 
.PROMPT:
 db $1B,"[31mroot",$1B,"[39m:", $1B,"[34m~", $1B, "[39m# "

.SPLASH:
db 64,65
include 'logo.inc'
 
.SPLASH_NAME:
; y 2, x 10, then y 5, x 0
 db $1B, "[3;11H", CONFIG_KERNEL_NAME, $1B, "[6;H"
 
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
 db "command not found", 10

.KEYMAP_NO_MOD:
 db ' ', ':', '?', 'x', 'y', 'z', '"', 's', 't', 'u', 'v', 'w', 'n', 'o', 'p', 'q', 'r', 'i', 'j', 'k', 'l', 'm'
 db 'd', 'e', 'f', 'g', 'h', 'a', 'b', 'c',' '
 
.KEYMAP_ALPHA:
 db ' ', '.', ';', 'X', 'Y', 'Z', '!', 'S', 'T', 'U', 'V', 'W', 'N', 'O', 'P', 'Q', 'R', 'I', 'J', 'K', 'L', 'M'
 db 'D', 'E', 'F', 'G', 'H', 'A', 'B', 'C',' '

.KEYMAP_2ND:
 db '0', '|', '%', '@', '1', '2', '#', '\', '4', '5', '6', ']', '~', '7', '8', '9', '[', '(', ')', '{', '}', '/'
 db '$', '&', '*', '_', '^', '-', '+', '`','3'
 
.KEYBOARD_KEY:
 db $FD, $FD, $FD, $FD, $FD, $FD, $F7, $FF
 db $FD, $03, $07, $0C, $11, $16, $1B, $FD
 db $00, $04, $08, $0D, $12, $17, $1C, $FD
 db $01, $05, $09, $0E, $13, $18, $1D, $FD
 db $02, $1E, $0A, $0F, $14, $19, $FD, $FD
 db $FE, $06, $0B, $10, $15, $1A, $FC, $FD
 db $FB, $FA, $F9, $F8, $FD, $FD, $FD, $FD

define	console_dev		tty_dev
define	console_style		tty_dev
define	console_fg_color	tty_dev+CONSOLE_FG_COLOR
define	console_bg_color	tty_dev+CONSOLE_BG_COLOR
define	console_cursor_xy	tty_dev+CONSOLE_CURSOR
define	console_blink		tty_dev+CONSOLE_BLINK
define	console_flags		tty_dev+CONSOLE_FLAGS
define	console_key		tty_dev+CONSOLE_KEY
define	console_takeover	tty_dev+CONSOLE_TAKEOVER
define	console_line_head	tty_dev+CONSOLE_LINE_HEAD
define	console_line		tty_dev+CONSOLE_LINE

console:

.nmi_takeover:
	ld	iy, console_dev
	ld	hl, nmi_console
	call	.fb_takeover_force
	jp	.fb_init

.fb_takeover:
	ld	iy, console_dev
	bit	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
	jr	z, .__fb_takeover_error
	di
; check CONSOLE_TAKEOVER is null
	ld	hl, (iy+CONSOLE_TAKEOVER)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	nz, .__fb_takeover_error
; take control of the video driver mutex
	ld	hl, kmem_cache_s64
	call	kmem.cache_alloc
	jr	c, .__fb_takeover_error
.fb_takeover_force:
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
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	ld	c, 6
	ldir
; 58 + 3 bytes in grand total, free 3 bytes
; mark console as present
	res	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
; take lcd mutex control
; stop thread holding the mutex
	ld	hl, DRIVER_VIDEO_IRQ_LOCK
	ld	(hl), $FF
	inc	hl
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(hl), 0
	ld	c, a
	ld	a, SIGSTOP
	call	signal.kill
	or	a, a
	ret

.__fb_takeover_error:
	scf
	ret

.fb_restore:
	di
; restore the fb console
; restore the mutex and the propriety
; it doesn't destroy the thread
	ld	iy, console_dev
	set	CONSOLE_FLAGS_SILENT, (iy+CONSOLE_FLAGS)
	ld	hl, (iy+CONSOLE_TAKEOVER)
	add	hl, de
	or	a, a
	sbc	hl, de
	ret	z
; restore status
	ld	de, DRIVER_VIDEO_SCREEN
	ld	bc, 16
	ldir
; restore palette
	ld	de, DRIVER_VIDEO_PALETTE
	ld	c, 36
	ldir
	ld	de, DRIVER_VIDEO_IRQ_LOCK
	ld	c, 6
	ldir
; restore keyboard ?
	ld	a, DRIVER_KEYBOARD_SCAN_CONTINUOUS
	ld	(DRIVER_KEYBOARD_CTRL), a
	ld	hl, (iy+CONSOLE_TAKEOVER)
	ld	bc, 0
	ld	(iy+CONSOLE_TAKEOVER), bc
	call	kfree
	ld	hl, DRIVER_VIDEO_IRQ_LOCK+1
	ld	a, (hl)
	or	a, a
	ret	z
	ld	c, a
	ld	a, SIGCONT
	jp	signal.kill

.fb_init:
	ld	hl, DRIVER_VIDEO_IMSC
	ld	(hl), DRIVER_VIDEO_IMSC_DEFAULT
	ld	hl, DRIVER_VIDEO_CTRL_DEFAULT
	ld	(DRIVER_VIDEO_CTRL), hl
	ld	hl, (DRIVER_VIDEO_BUFFER)
	ld	(DRIVER_VIDEO_SCREEN), hl
	ld	hl, .PALETTE
	ld	de, DRIVER_VIDEO_PALETTE
	ld	bc, 36
	ldir
	call	video.clear_screen
	ld	hl, 4
	ld	e, 7
	ld	bc, .SPLASH
	call	.blit
	ld	c, 37
	ld	hl, .SPLASH_NAME
	jp	tty.phy_write
	
.init:
	di
	ld	bc, $0100
	ld	hl, console_dev
	ld	(hl), bc
	ld	l, (console_flags) and $FF
	ld	(hl), 1 shl CONSOLE_FLAGS_SILENT
	inc	hl
	ld	(hl), $FD
	ld	l, (console_takeover) and $FF
	dec	b
	ld	(hl), bc
	jp	tty.phy_init

.exit:
	call	.fb_restore
	jp	kthread.exit

.irq_switch:
; NOTE : we will need to SIGSTOP the thread owning the mutex (wich may or may be not the thread running)
; if it is the currently running thread, due to the fact that fb_takeover is running in interrupt span
; it may be complex
; thread create irq will set reschedule byte, so we might be good
; however, signal is STILL broken
	call	.fb_takeover
	ret	c
	ld	iy, .vt_init
	jp	kthread.irq_create

.vt_init:
	call	.fb_init
.vt_prompt:
; profiling exemple
; 	ld	hl, kmem_cache_s512
; 	call	kmem.cache_alloc
; ; de : bufsize, bc : offset, ix : scale
; 	ld	de, 256
; 	ld	bc, .run_loop
; ; by 4 bytes blocks
; 	ld	ix, 65536
; 	call	_profil
	call	.prompt
.run_loop:
; wait keyboard scan
; around 100 ms repeat time
	ld	b, 8
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
; use vsync busy call
; use atomic vsync since we dont have the video mutex
	call	video.vsync_atomic
; wait for vsync, we are in vblank now (are we ?)
; the syscall destroy a but not hl
	ld	hl, (console_line_head)
	ld	a, (hl)
	ld	hl, console_blink
	bit	CONSOLE_BLINK_RATE, (hl)
	call	z, tty.putchar
	ld	a, (console_key)
	cp	a, $FD
	call	nz, .handle_console_stdin
.blink:
	ld	hl, console_blink
	inc	(hl)
	bit	CONSOLE_BLINK_RATE, (hl)
	ld	a, '_'
	call	z, tty.putchar
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
	inc	bc
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
	and	a, 11111100b
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
	call	tty.phy_new_line
	ld	hl, console_line
	ld	bc, 0
	xor	a, a
	cpir
	inc	bc
	ld	a, b
	or	a, c
	jp	z, .clean_command
; check the command
; if command = reboot, we'll do rst 0h
	ld	hl, .REBOOT
	call	.check_builtin
	jp	z, reboot
	ld	hl, .COLOR
	call	.check_builtin
	jp	z, .color
	ld	hl, .UPTIME
	call	.check_builtin
	jp	z, .uptime
	ld	hl, .SHUTDOWN
	call	.check_builtin
	jp	z, .shutdown
	ld	hl, .ECHO
	call	.check_builtin
	jp	z, .echo
	ld	hl, .LS
	call	.check_builtin
	jp	z, .ls
	ld	hl, .FREE
	call	.check_builtin
	jp	z, .free
	ld	hl, .EXIT
	call	.check_builtin
	jp	z, .exit
	ld	hl, .DMESG
	call	.check_builtin
	jp	z, .dmesg
; try to exec the program in /bin/xxxx
; bc = string size
	ld	hl, console_line
	ld	bc, CONSOLE_LINE_SIZE - 6
	ld	a, ' '
	cpir
; return hl + 1, or po if none left
; blit zero anyway at the end
	dec	hl
	ld	bc, 6
	ld	(hl), b
	add	hl, bc
	jp	pe, .argv_not_null
	ld	hl, .BIN_ARGV
.argv_not_null:
	push	hl
; copy the string now
	ld	hl, console_line + CONSOLE_LINE_SIZE - 6
	ld	de, console_line + CONSOLE_LINE_SIZE - 1
	ld	bc, CONSOLE_LINE_SIZE - 5
	lddr
	ld	de, console_line
	ld	hl, .BINARY_PATH
	ld	c, 5
	ldir
	pop	bc
	ld	hl, console_line
	ld	de, .BIN_ENVP
; please note argv is a pointer to a raw string, it will be cut and pushed into program stack frame by the program exec call
; TODO : find a better way than leaf.program
; create thread with execve as thread is a good idea, however, the thread creation will always be correct
; then I need to retrieve error code of execve and then utimately error code of exit thread
	dbg	open
	call	leaf.execve
	jr	c, .unknown_command
; ; right here, we should wait for sigchild
; .exclusive_wait_command:
; 	call	signal.wait
; 	ld	a, l
; 	cp	a, SIGCHLD
; 	jr	nz, .exclusive_wait_command
.clean_command:
	jp	.prompt
.unknown_command:
	ld	hl, .UNKNOW_INSTR
	ld	bc, 18
	call	tty.phy_write
	jp	.prompt
	
.check_builtin:
	ld	de, console_line
	ld	bc, CONSOLE_LINE_SIZE
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
	ld	hl, console_line + 5
	xor	a, a
	ld	bc, 0
	cpir
	sbc	hl, hl
	sbc	hl, bc
	push	hl
	pop	bc
	cpi
	jp	po, .clean_command
	ld	hl, console_line + 5
	call	tty.phy_write
	call	tty.phy_new_line
	jr	.clean_command

.shutdown:
	call	kpower.cycle_off
	jr	.clean_command

.dmesg:
	call	dmesg
	jr	.clean_command
	
.color:
	ld	hl, (console_cursor_xy)
; 24 * 8 + 4 * 7
	call	tty.glyph_adress
; de = address
	ex	de, hl
	ld	de, 40
	add	hl, de
	push	hl
	ld	e, 4
	ld	a, 2
	ld	c, 8
.color_block_b:
	ld	b, 24
.color_block:
	ld	(hl), a
	inc	hl
	djnz	.color_block
	inc	a
	add	hl, de
	dec	c
	jr	nz, .color_block_b
	pop	de
	ld	hl, 320
	add	hl, de
	ex	de, hl
	ld	bc,(320*9)+220
	ldir
	ld	iy, console_dev
	call	tty.phy_new_line
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
	ld	hl, console_line
	push	hl
	call	_boot_sprintf_safe
	ld	hl, 18
	add	hl, sp
	ld	sp, hl
	ld	hl, console_line
	ld	bc, 34
	call	tty.phy_write
	jp	.prompt

.free:
	ld	hl, KERNEL_MM_GFP_KERNEL
	push	hl
	ld	c, 0
	ld	b, KERNEL_MM_PAGE_MAX-KERNEL_MM_GFP_KERNEL
	ld	hl, kmm_ptlb_map
	ld	l, KERNEL_MM_GFP_KERNEL
.free_count:
	ld	a, (hl)
	cp	a, KERNEL_MM_PAGE_FREE_MASK
	jr	nz, $+3
	inc	c
	inc	hl
	djnz	.free_count
; c = free
	xor	a, a
	sub	a, c
	sub	a, KERNEL_MM_GFP_KERNEL
; a = used
	or	a, a
	sbc	hl, hl
	ld	l, a
	push	hl
	ld	l, c
	push	hl
	ld	hl, .FREE_STR
	push	hl
	ld	hl, console_line
	push	hl
	call	_boot_sprintf_safe
	ld	hl, 15
	add	hl, sp
	ld	sp, hl
	ld	hl, console_line
	ld	bc, 66
	call	tty.phy_write
	jp	.prompt

.LS_SPACE:
 db " "
.LS_ROOT:
 db "/",0
	
.ls:
	ld	hl, console_line + 2
	ld	a, (hl)
	or	a, a
	jr	nz, .ls_find_arg
	ld	hl, .LS_ROOT
	ld	bc, 1
	jr	.ls_list
.ls_find_arg:
; skip space
	cp	a, ' '
	jp	nz, .ls_error
.ls_skip_space:
	inc	hl
	ld	a, (hl)
	cp	a, ' '
	jr	z, .ls_skip_space
	push	hl
	xor	a, a
	ld	bc, 0
	cpir
	sbc	hl, hl
	sbc	hl, bc
	push	hl
	pop	bc
	cpi
	pop	hl
	jp	po, .ls_error
.ls_list:
	push	bc
	push	hl
	call	kvfs.inode_get_lock
; iy = inode
	pop	hl
	pop	bc
	jp	c, .ls_error
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_DIRECTORY
	jr	z, .ls_dir
	call	tty.phy_write
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	ld	iy, console_dev
	call	tty.phy_new_line
	jp	.prompt
.ls_dir:
	push	iy
; we have a dir, parse all dirent
	ld	b, 16
	lea	iy, iy+KERNEL_VFS_INODE_DATA
.ls_dirent:
	push	bc
	ld	ix, (iy+0)
	lea	hl, ix+0
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .ls_next_dirent
	ld	a, (ix+KERNEL_VFS_DIRECTORY_NAME)
	or	a, a
	call	nz, .ls_display_dirent
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	ld	a, (ix+KERNEL_VFS_DIRECTORY_NAME)
	or	a, a
	call	nz, .ls_display_dirent
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	ld	a, (ix+KERNEL_VFS_DIRECTORY_NAME)
	or	a, a
	call	nz, .ls_display_dirent
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
	ld	a, (ix+KERNEL_VFS_DIRECTORY_NAME)
	or	a, a
	call	nz, .ls_display_dirent
	lea	ix, ix+KERNEL_VFS_DIRECTORY_ENTRY_SIZE
.ls_next_dirent:
	lea	iy, iy+3
	pop	bc
	djnz	.ls_dirent
	pop	iy
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	ld	iy, console_dev
	call	tty.phy_new_line
	jp	.prompt
.ls_display_dirent:
	push	iy
	push	ix
	lea	hl, ix+KERNEL_VFS_DIRECTORY_NAME
	push	hl
	xor	a, a
	ld	bc, 0
	cpir
	sbc	hl, hl
	sbc	hl, bc
	push	hl
	ld	hl, (ix+KERNEL_VFS_DIRECTORY_INODE)
	ld	a, (hl)
	and	a, KERNEL_VFS_TYPE_MASK
	cp	a, KERNEL_VFS_TYPE_DIRECTORY
	ld	hl, .LS_COLOR_NONE
	jr	nz, .ls_color
	ld	hl, .LS_COLOR_FOLDER
.ls_color:
	ld	bc, 5
	call	tty.phy_write
	pop	bc
	dec	bc
	pop	hl
	call	tty.phy_write
	ld	hl, .LS_SPACE
	ld	bc, 1
	call	tty.phy_write
	pop	ix
	pop	iy
	ret
.ls_error:
	ld	hl, .LS_ERROR
	ld	bc, 30
	call	tty.phy_write
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	ld	iy, console_dev
	call	tty.phy_new_line
	jp	.prompt

.handle_key_del:
; suppr
	ld	hl, (console_line_head)
; we need to delete the value @head and collapse
	ld	a, (hl)
	or	a, a
	ret	z
.collapse_do:
	ex	de, hl
	or	a, a
	sbc	hl, hl
	add	hl, de
	inc	hl
; copy hl to de while hl ! = 0
.collapse:
	ld	a, (hl)
	ldi
	or	a, a
	jr	nz, .collapse
	jr	.refresh_line
	
.handle_key_mode:
; backspace behaviour
; we need to delete the value @head-1
	ld	hl, (console_line_head)
	dec	hl
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(console_line_head), hl
	ex	de, hl
	sbc	hl, hl
	add	hl, de
	inc	hl
; copy hl to de while hl ! = 0
.collapse_backspace:
	ld	a, (hl)
	ldi
	or	a, a
	jr	nz, .collapse_backspace
	
	ld	hl, .KEY_LEFT_CSI
	ld	bc, 3
	call	tty.phy_write
	
.refresh_line:
; bc = string, hl xy
	ld	hl, (console_cursor_xy)
	push	hl
	call	tty.glyph_adress
	ld	hl, (console_line_head)
.refresh_line_loop:
	ld	a, (hl)
	or	a, a
	jr	z, .refresh_line_restore
	inc	hl
	push	hl
	ld	hl, console_cursor_xy
	inc	(hl)
	call	tty.glyph_char_address
	pop	hl
	ld	a, (console_cursor_xy)
	cp	a, CONSOLE_CURSOR_MAX_COL
	jr	nz, .refresh_line_loop
.refresh_new_line:
	push	hl
	ld	hl, console_cursor_xy
	call	tty.phy_new_line_ex
; recompute adress from console_cursor
	ld	hl, (console_cursor_xy)
	call	tty.glyph_adress
	pop	hl
	jr	.refresh_line_loop
.refresh_line_restore:
	call	tty.glyph_char_address
	pop	hl
	ld	(console_cursor_xy), hl
	ret  
  
.handle_console_stdin:
	cp	a, $FC
	jp	z, .handle_key_clear
	cp	a, $FE
	jp	z, .handle_key_enter
	cp	a, $FF
	jp	z, .handle_key_del
	cp	a, $F7
	jr	z, .handle_key_mode
	ld	hl, (console_line_head)
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
	ld	de, (console_line_head)
; $FF should always be zero
; so last writeable is $FE
; prevent buffer line overflow
	ld	a, e
	add	a, 2
	ret	z
	ldi
	dec	hl
	ld	(console_line_head), de
; putchar(a)
	ld	bc, 1
	jp	tty.phy_write

.handle_key_up:
	ret

.handle_key_right:
	ld	a, (hl)
	or	a, a
	ret	z
	inc	hl
	ld	(console_line_head), hl
	ld	hl, .KEY_RIGHT_CSI
	ld	bc, 3
	jp	tty.phy_write

.KEY_RIGHT_CSI:
 db $1B, "[C"

.handle_key_left:
	dec	hl
	ld	a, (hl)
	or	a, a
	ret	z
	ld	(console_line_head), hl
	ld	hl, .KEY_LEFT_CSI
	ld	bc, 3
	jp	tty.phy_write
	
.KEY_LEFT_CSI:
 db $1B, "[D"
	
.handle_key_clear:
.clear:
; reset cursor xy and put prompt
	ld	hl, .KEY_CLEAR_CSI
	ld	bc, 4
	call	tty.phy_write

.prompt:
; flush the line buffer
	ld	de, console_line
	ld	(console_line_head), de
	dec	de
	ld	hl, $E41C00
	ld	bc, CONSOLE_LINE_SIZE + 1
	ldir
	ld	c, h
	ld	hl, .PROMPT
	jp	tty.phy_write

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
.LS:
 db 2, "ls"
.FREE:
 db 5, "free",0
.DMESG:
 db 6, "dmesg",0
 
.BINARY_PATH:
 db "/bin/",0
.BIN_ENVP:
.BIN_ARGV:
 dl	NULL

.FREE_STR:
 db "available memory: %03d KiB",10 ; 26
 db "used: %03d KiB", 10
 db "hardware reserved: %02d KiB",10,0
 
.UPTIME_STR:
; db "up since 0000 day(s), 00h 00m 00s", 0
 db "up since %04d day(s), %02dh %02dm %02ds" , 10, 0
 
.LS_ERROR:
 db "no file or folder of this type", 0
 
.LS_COLOR_FOLDER:
 db $1B,"[35m"
.LS_COLOR_NONE:
 db $1B,"[39m"
 
.PROMPT:
 db $1B,"[31mroot",$1B,"[39m:", $1B,"[34m~", $1B, "[39m# "

.SPLASH:
db 58,50
include	'logo.inc'
 
.SPLASH_NAME:
; y 2, x 10, then y 5, x 0
 db $1B, "[3;11H", CONFIG_KERNEL_NAME, "-", CONFIG_KERNEL_VERSION, $1B, "[6;H"
 
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
 db '$', ',', '*', '_', '^', '-', '+', '`','3'
 
.KEYBOARD_KEY:
 db $FD, $FD, $FD, $FD, $FD, $FD, $F7, $FF
 db $FD, $03, $07, $0C, $11, $16, $1B, $FD
 db $00, $04, $08, $0D, $12, $17, $1C, $FD
 db $01, $05, $09, $0E, $13, $18, $1D, $FD
 db $02, $1E, $0A, $0F, $14, $19, $FD, $FD
 db $FE, $06, $0B, $10, $15, $1A, $FC, $FD
 db $FB, $FA, $F9, $F8, $FD, $FD, $FD, $FD

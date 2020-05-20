define	KERNEL_MEMORY                      0xD00000
define	KERNEL_THREAD                      0xD00010
define	KERNEL_STACK                       KERNEL_THREAD + KERNEL_THREAD_STACK
define	KERNEL_STACK_SIZE                  0x40

define	KERNEL_BOOT_MEMORY0                0xD0009B   ; touched memory by the boot.
define	KERNEL_BOOT_MEMORY1                0xD000AC   ; same, a set somewhere

define	KERNEL_CRYSTAL_CTLR                 0x00
define	KERNEL_CRYSTAL_TIMER_DIV74          0x00
define	KERNEL_CRYSTAL_TIMER_DIV154         0x01
define	KERNEL_CRYSTAL_TIMER_DIV218         0x02
define	KERNEL_CRYSTAL_TIMER_DIV314         0x03

define	NULL 0

kinit:
	di	; boot 5.0.1 stupidity power ++
	ld	a, KERNEL_CRYSTAL_TIMER_DIV314
	out0	(KERNEL_CRYSTAL_CTLR), a
	ld	sp, 0xD000E0
	ld	(KERNEL_STACK), sp
	ld.sis sp, 0xD000E0 and 0xFFFF
	ld	a, ( KERNEL_MEMORY shr 16 ) and 0xFF
	ld	MB, a
; blank stack protector
	ld	a, 0xA0
	out0	(0x3A), a
	ld	a, 0x00
	out0	(0x3B), a
	ld	a, 0xD0
	out0	(0x3C), a
    
	call	kpower.init
	call	kmmu.init
	call	kwatchdog.init
	call	kthread.init
	call	kinterrupt.init

; driver init, nice
	call	kvideo.init
	call	kkeyboard.init
; create init thread : ie, first program to run (/bin/init/)
	ld	iy, THREAD_INIT_TEST
	call	kthread.create
; nice idle thread code
	trap
    
THREAD_INIT_TEST:
; load frozen elf16 example
	ld	hl, elf_frozen_example
	call	kexec.load_elf16    
; boom, kill it
	ld	c, 2
	ld	a, SIGSTOP
	call	ksignal.kill
	
	call	kvideo.irq_lock
	ld	bc, 0
.loop:
	push	bc
	ld.atomic de, (DRIVER_VIDEO_BUFFER)
	ld	bc, 320*14
	ld	hl, 0xE40000
	ldir
;	call  kvideo.clear
	ld	hl, 0
	ld	e, 0
	pop	bc
	push	bc
	call	kvideo.put_int
	call	kvideo.swap
	
;	ld	c, 2
;	ld	a, SIGCONT
;	call	ksignal.kill

	pop	bc
	inc	bc
	jr	.loop
    
.teststring:
	db "HELLO WORLD !",0

elf_frozen_example:
include	'frozen.asm'

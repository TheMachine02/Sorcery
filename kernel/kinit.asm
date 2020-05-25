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
; about 150 times per seconde, master interrupt (or jiffies)
	ld	a, KERNEL_CRYSTAL_TIMER_DIV218
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
    
	ld	a, 0x03
	ld	($E00005), a
    
	call	kpower.init
	call	kmmu.init
	call	kwatchdog.init
	call	klocal_timer.init
	call	kinterrupt.init
	call	kthread.init

; driver init, nice
	call	kvideo.init
	call	kkeyboard.init
; create init thread : ie, first program to run (/bin/init/)
	ld	iy, THREAD_INIT_TEST
	call	kthread.create
; nice idle thread code
	ei
	halt
	jr $-2
    
THREAD_INIT_TEST:
; load frozen elf16 example
;	ld	hl, elf_frozen_example
;	call	kexec.load_elf16_ptr   
; C pthread_create exemple, called from asm (syscall, let's look at you really hard)
	ld	iy, TEST_THREAD_C
	ld	hl, 65536
	call	kthread.create

; video lock for me
	call	kvideo.irq_lock
	ld	bc, 0
.loop:
	push	bc
	ld.atomic de, (DRIVER_VIDEO_BUFFER)
	ld	bc, 320*26
	ld	hl, 0xE40000
	ldir
; 	call  kvideo.clear
	ld	hl, 0
	ld	e, 0
	pop	bc
	push	bc
	call	kvideo.put_int
	
	
	call	kcstate.get_clock
	ld	bc, 0
	ld	c, a
	ld	hl, 0
	ld	e, 13
	call	kvideo.put_hex
	
	call	kvideo.swap
	
	ld	hl, 250	; 250 ms is nice
	call	kthread.sleep
; we were waked by spining thread !
	pop	bc
	inc	bc
	jr	.loop
    
TEST_THREAD_C:
	call __frameset0
	ld hl, (ix+6)
	call	kmalloc
.spin:
; we can sleep now ! (only 8 bits value for now)
	ld	hl, 50	; 10 ms is nice
	call	kthread.sleep
; trap opcode instruction
;db	0xDD, 0xFF
; need to catch rst 00h for that !
	ld	hl, 0xAA55AA
	ld	a, SIGCONT
	ld	c, 1
	call	kill
	jr	.spin
	pop ix
	ret
    
elf_frozen_example:
include	'frozen.asm'

define	KERNEL_HEAP			$D00040
define	KERNEL_THREAD			$D00010
define	KERNEL_STACK			KERNEL_THREAD + KERNEL_THREAD_STACK
define	KERNEL_STACK_SIZE		$30

define	KERNEL_BOOT_MEMORY0		$D0009B   ; touched memory by the boot.
define	KERNEL_BOOT_MEMORY1		$D000AC   ; same, a set somewhere

define	KERNEL_CRYSTAL_CTLR		$00
define	KERNEL_CRYSTAL_DIVISOR		CONFIG_CRYSTAL_DIVISOR

define	NULL 0

kinit:
; boot 5.0.1 stupidity power ++
	di
; setup stack for the kernel
	ld	sp, $D000E0
	ld	(KERNEL_STACK), sp
	ld.sis sp, $0000
; setup master interrupt divisor = define jiffies
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
; blank stack protector
	ld	a, $B0
	out0	($3A), a
	ld	a, $00
	out0	($3B), a
	ld	a, $D0
	out0	($3C), a
; faster flash acess please    
	ld	a, $03
	ld	($E00005), a
; general system init
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

kname:	
	ld	hl, .KERNEL_NAME
	ret
	
.KERNEL_NAME:
 db CONFIG_KERNEL_NAME, 0
	
; Exemple area ;
; Static compiled thread an such ;
; Kernel only init and pass to init thread, so a proper OS will go there ;
	
	
THREAD_INIT_TEST:
; load frozen elf16 example
;	ld	hl, elf_frozen_example
;	call	kexec.load_elf16_ptr   
; C pthread_create exemple, called from asm (syscall, let's look at you really hard)
	ld	iy, TEST_THREAD_C
	ld	hl, 2048
	call	kthread.create

; video lock for me
	call	kvideo.irq_lock
	ld	bc, 0
.loop:
	push	bc
	ld	de, (DRIVER_VIDEO_BUFFER)
	ld	bc, 320*26
	ld	hl, $E40000
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
	ld	hl, 16	; 16 ms is nice
	call	kthread.sleep
; trap opcode instruction
;db	$DD, $FF
; need to catch rst 00h for that !
	ld	hl, $AA55AA
	ld	a, SIGCONT
	ld	c, 1
	call	kill
	jr	.spin
	pop ix
	ret
    
elf_frozen_example:
include	'frozen.asm'

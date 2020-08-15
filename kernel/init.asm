define	KERNEL_HEAP			$D00043
define	KERNEL_THREAD			$D00010
define	KERNEL_STACK			KERNEL_THREAD + KERNEL_THREAD_STACK
define	KERNEL_STACK_SIZE		$40
; from B0 to F0

define	KERNEL_BOOT_MEMORY0		$D0009B   ; touched memory by the boot.
define	KERNEL_BOOT_MEMORY1		$D000AC   ; same, a set somewhere

define	KERNEL_CRYSTAL_CTLR		$00
define	KERNEL_CRYSTAL_DIVISOR		CONFIG_CRYSTAL_DIVISOR

define	NULL 				0
define	KERNEL_DEV_NULL			$E40000

kinit:
.reboot:
; boot 5.0.1 stupidity power ++
	di	
; note 2 : boot 5.0.1 also crash is rst 0h is run with LCD interrupts on
; shift to soft kinit way to reboot ++
; setup stack for the kernel
	ld	sp, $D000F0
	ld	(KERNEL_STACK), sp
	ld.sis sp, $0000
	ld	a, $D0
	ld	MB, a
	ld	hl, KERNEL_INTERRUPT_IDT
	ld	i, hl
; setup master interrupt divisor = define jiffies
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
; blank stack protector
	ld	a, $60
	out0	($3A), a
	ld	a, $00
	out0	($3B), a
	ld	a, $D0
	out0	($3C), a
; general system init
	call	power.init
; memory init ;
	call	kmm.init
	call	kslab.init
; timer and interrupts ;
	call	ktimer.init
	call	kinterrupt.init
	call	kthread.init
	call	kwatchdog.init
;	call	kvfs.init
; driver init ;
	call	video.init
	call	keyboard.init
	call	rtc.init
; device & driver init ;
	call	console.init
	call	flash.init
;	call	null.init
; create init thread : ie, first program to run (/bin/init/)
	ld	iy, THREAD_INIT_TEST
	call	kthread.create
	jp	c, nmi
; nice idle thread code
.arch_sleep:
; different behaviour are possible
; most dynamic is reduce by one the value
; most brutal is directly set to 6Mhz, we'll need to ramp up
if CONFIG_USE_DYNAMIC_CLOCK
	xor	a,a
	out0	(KERNEL_POWER_CPU_CLOCK),a
	ld	a, $01
	ld	(KERNEL_FLASH_CTRL),a
end if
	ei
	slp
	jr	.arch_sleep

.root_path:
 db "/", 0

kname:
	ld	bc, .string
	ret	
.string:
 db CONFIG_KERNEL_NAME, 0

; Exemple area ;
; Static compiled thread an such ;
; Kernel only init and pass to init thread, so a proper OS will go there ;


define	global_mutex		$D00170		; that's just a test
define	global_exit_value	$D00180

THREAD_INIT_TEST:
	ld	hl, global_mutex
	call	kmutex.init
	
; load frozen elf example
;	call	kexec.load_elf	; thread  2
; C pthread_create exemple, called from asm (syscall, let's look at you really hard)
	ld	iy, TEST_THREAD_C ; thread 2
	call	kthread.create
; 
	ld	iy, TEST_THREAD_C_DEATH ; thread 3
	call	kthread.create
	
	ld	a, SIGUSR1
	call	signal.procmask_single
	
	call	video.irq_lock
;	call	keyboard.irq_lock
	
	call	console.run
; 	ld	hl, global_mutex
; 	call	kmutex.lock
; 	
; 	ld	hl, lz4_frozen
; 	ld	de, (DRIVER_VIDEO_BUFFER)
; 	call	lz4.decompress
; 
; 	ld	hl, global_mutex
; 	call	kmutex.unlock
; 
; 	ld	hl, 3
; 	ld	de, global_exit_value
; 	call	kthread.join
		
; video lock for me
; 	call	kvideo.irq_lock
	
;	ld	bc, 0
;.loop:
;	push	bc
	
; ; 	ld	de, (DRIVER_VIDEO_BUFFER)
; ; 	ld	hl, KERNEL_MM_NULL
; ; 	ld	bc, 320*39
; ; 	ldir	
; ; printing kernel name ;
; 	call	kname
; 	ld	hl, 10
; 	ld	e, 10
; 	call	kvideo.put_string
; ; print the small counter ;
; 	ld	hl, 10
; 	ld	e, 10+1*11
; 	pop	bc
; 	push	bc
; 	call	kvideo.put_int
; ; clock clock ;
; 	ld	bc, bob
; 	ld	hl, 10
; 	ld	e, 10+2*11
; 	call	kvideo.put_string
; 	call	kcstate.get_clock
; 	ld	hl, global_frequency_table
; 	ld	bc, 0
; 	ld	c, a
; 	add	hl, bc
; 	ld	c, (hl)
; 	ld	hl, 260
; 	ld	e, 10+2*11
; 	call	kvideo.put_int

;	call	kvideo.copy
	
;	ld	hl, 1000	; 1000 ms is nice
;	call	kthread.sleep

; we were not waked by spining thread ! (masked signal)
;	pop	bc
;	inc	bc
;	jr	.loop
	ret
 
TEST_THREAD_C:
	call __frameset0
	ld hl, (ix+6)
	ld	iy, leaf_frozen_file
	call	leaf.exec

.spin:	
;	ld	hl, 30	; 30 ms is nice
;	call	kthread.sleep
; trap opcode instruction
;db	$DD, $FF
; need to catch rst 00h for that !
; 	ld	hl, global_mutex
; 	call	kmutex.lock
; 	ld	hl, $AA55AA
; 	ld	a, SIGUSR1
; 	ld	c, 1
; 	call	signal.kill
; 	ld	hl, global_mutex
; 	call	kmutex.unlock
; 	ld	bc, 65536
; 	ld	hl, $020000
; 	ld	de, $3B0000
; 	call	flash.phy_write
; 	ld	hl, $3B0000
; 	call	flash.phy_erase
	jr	.spin
	pop ix
	ret

TEST_THREAD_C_DEATH:
	call __frameset0
;	ld	iy, (kthread_current)
;	set	THREAD_JOIGNABLE, (iy+KERNEL_THREAD_ATTRIBUTE)
; malloc test ;
.spin:
	ld	hl, 512
	call	kmalloc
	push	hl
	ld	hl, 512
	call	kmalloc	
	ld	hl, 512
	call	kmalloc
	pop	hl
	call	kfree
	jr	.spin
; wait ;
; normal path - but not taken
	ld	hl, 0
	call	kthread.exit
	ret

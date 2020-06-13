define	KERNEL_HEAP			$D00040
define	KERNEL_THREAD			$D00010
define	KERNEL_STACK			KERNEL_THREAD + KERNEL_THREAD_STACK
define	KERNEL_STACK_SIZE		$30

define	KERNEL_BOOT_MEMORY0		$D0009B   ; touched memory by the boot.
define	KERNEL_BOOT_MEMORY1		$D000AC   ; same, a set somewhere

define	KERNEL_CRYSTAL_CTLR		$00
define	KERNEL_CRYSTAL_DIVISOR		CONFIG_CRYSTAL_DIVISOR

define	NULL 0
define	KERNEL_DEV_NULL			$E40000

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
; general system init
	call	kpower.init
	call	kmm.init
	call	kflash.init
	call	kwatchdog.init
	call	klocal_timer.init
	call	kinterrupt.init
	call	kthread.init
	call	kmsg.init
; driver init, nice
	call	kvideo.init
	call	kkeyboard.init
; create init thread : ie, first program to run (/bin/init/)
	ld	iy, THREAD_INIT_TEST
	call	kthread.create
	jp	c, kinterrupt.nmi
; nice idle thread code
.arch_sleep:
	ei
	slp
	jr	.arch_sleep

kname:
	ld	bc, Sorcery.name
	ret

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

	ld	iy, TEST_THREAD_C_DEATH ; thread 3
	call	kthread.create
	
	ld	a, SIGUSR1
	call	ksignal.procmask_single
	
	ld	hl, global_mutex
	call	kmutex.lock
	
	ld	hl, lz4_frozen
	ld	de, $D40000
	call	lz4.decompress

	ld	hl, global_mutex
	call	kmutex.unlock

	ld	hl, 3
	ld	de, global_exit_value
	call	kthread.join

; video lock for me
; 	call	kvideo.irq_lock

	ld	bc, 0
.loop:
	push	bc
	ld	hl, global_mutex
	call	kmutex.lock
	call	kvideo.clear
; printing kernel name ;
	call	kname
	ld	hl, 0
	ld	e, 0
	call	kvideo.put_string
; print the small counter ;
	ld	hl, 0
	ld	e, 13
	pop	bc
	push	bc
	call	kvideo.put_int
; clock clock ;
	ld	bc, global_running_string
	ld	hl, 0
	ld	e, 26
	call	kvideo.put_string
	call	kcstate.get_clock
	ld	hl, global_frequency_table
	ld	bc, 0
	ld	c, a
	add	hl, bc
	ld	c, (hl)
	ld	hl, 102
	ld	e, 26
	call	kvideo.put_int
	
	ld	hl, global_mutex
	call	kmutex.unlock
	
	call	kvideo.swap
	
	ld	hl, 1000	; 1000 ms is nice
	call	kthread.sleep
	
; we were not waked by spining thread ! (masked signal)
	pop	bc
	inc	bc
	jr	.loop

global_running_string:
 db "Frequency (Mhz) :", 0
global_frequency_table:
 db 6,12,24,48
 
TEST_THREAD_C:
	call __frameset0
	ld hl, (ix+6)
.spin:
; we can sleep now ! (only 8 bits value for now)
	
	ld	hl, 16	; 16 ms is nice
	call	kthread.sleep
; trap opcode instruction
;db	$DD, $FF
; need to catch rst 00h for that !
	ld	hl, global_mutex
	call	kmutex.lock

	ld	hl, $AA55AA
	ld	a, SIGCONT
	ld	c, 1
	call	ksignal.kill
;	
	ld	hl, global_mutex
	call	kmutex.unlock

	jr	.spin
	pop ix
	ret

TEST_THREAD_C_DEATH:
	call __frameset0
	
	ld	iy, (kthread_current)
	set	THREAD_JOIGNABLE, (iy+KERNEL_THREAD_ATTRIBUTE)
	
	call	kkeyboard.wait_key

; let's try a segfault, shall we ?
	ld	bc, 4*256 + 1
	call	kmm.page_unmap
	
	ld	hl, 0
	jp	kthread.exit

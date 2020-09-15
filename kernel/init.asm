define	BOOT_DIRTY_MEMORY0		$D0009B		; 1 byte ]
define	BOOT_DIRTY_MEMORY1		$D000AC		; 1 byte ] on interrupt
define	BOOT_DIRTY_MEMORY2		$D000FF		; 3 bytes
define	BOOT_DIRTY_MEMORY3		$D00108		; 9 bytes

define	kernel_heap			$D00100
define	kernel_stack			$D000FF
define	KERNEL_STACK_SIZE		$57
define	kernel_data			$D00000

define	KERNEL_CRYSTAL_CTLR		$00
define	KERNEL_CRYSTAL_DIVISOR		CONFIG_CRYSTAL_DIVISOR

define	NULL 				0
define	KERNEL_DEV_NULL			$E40000

define	kernel_idle			$D00090
define	kernel_stack_pointer		$D0009F

kinit:
; read kernel paramater
; silent :: no LCD flashing / console updating, open console only if error
.reboot:
; boot 5.0.1 stupidity power ++
; note 2 : boot 5.0.1 also crash is rst 0h is run with LCD interrupts on
	di
; load up boot stack
	ld	sp, $D1A87E
; shift to soft kinit way to reboot ++
; we will use temporary boot code stack
; setup master interrupt divisor = define jiffies
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
; setup priviliegied OS code (end of OS)
	ld	a, $06
	out0	($1F), a
	ld	de, kernel_data
	out0	($1D), e
	out0	($1E), e
; disable stack protector to be able to write the whole RAM image
	out0	($3A), e
	out0	($3B), e
	out0	($3C), e
; load the initramfs image, 4K
	ld	hl, kernel_initramfs
	call	lz4.decompress
; and init the rest of memory with poison
	ld	hl, $D01000
	ld	de, $D01001
	ld	bc, KERNEL_MM_RAM_SIZE - 4097
	ld	(hl), KERNEL_HW_POISON
	ldir
; right now, the RAM image is complete
; setup the kernel stack protector
	ld.sis	sp, $0000
	ld	sp, kernel_stack
	ld	(kernel_stack_pointer), sp
	ld	hl, $A80F
	out0	($3A), h
	out0	($3B), c
	ld	a, $D0
	out0	($3C), a
	ld	MB, a
; setup memory protection
	out0	($20), c
	out0	($21), c
	dec	c
	out0	($23), c
	out0	($24), l
	out0	($22), a
	out0	($25), a
; small init for the vfs
	ld	hl, kvfs.phy_none
	ld	(kvfs_root+KERNEL_VFS_INODE_OP), hl
; power, timer and interrupt
	call	kinterrupt.init
	call	kpower.init
	call	kwatchdog.init
; driver init ;
	call	video.init
	call	keyboard.init
	call	rtc.init
; device & driver init ;
	call	console.init
	call	flash.init
	call	null.init	
; create init thread : ie, first program to run (/bin/init/)
; 	ld	iy, THREAD_INIT_TEST
; 	call	kthread.create
; 	jp	c, nmi
	call	console.fb_takeover
	jp	c, nmi
; nice idle thread code
	ei
.arch_sleep:
; different behaviour are possible
; most dynamic is reduce by one the value
; most brutal is directly set to 6Mhz, we'll need to ramp up
	slp
	jr	.arch_sleep
 
.poison_heap: 
	ld	hl, kernel_heap
	ld	de, kernel_heap + 1
	ld	bc, 511
	ld	(hl), KERNEL_HW_POISON
	ldir
	ret
 
kname:
	ld	bc, .string
	ret	
.string:
 db CONFIG_KERNEL_NAME, 0

; Exemple area ;
; Static compiled thread an such ;
; Kernel only init and pass to init thread, so a proper OS will go there ;


define	global_lock		$D3F000		; that's just a test
define	global_exit_value	$D00180

node:
 db "/dev/console",0

THREAD_INIT_TEST:
; 	ld	hl, global_mutex
; 	call	atomic_rw.init	
; load frozen elf example
;	call	kexec.load_elf	; thread  2
; C pthread_create exemple, called from asm (syscall, let's look at you really hard)
	ld	iy, TEST_THREAD_C ; thread 2
	call	kthread.create
; ; 
; 	ld	iy, TEST_THREAD_C_DEATH ; thread 3
; 	call	kthread.create
	
	ld	a, SIGUSR1
	call	signal.procmask_single
	
	call	video.irq_lock
	
.spin:
	jr	.spin
	
;	call	keyboard.irq_lock
; 	call	console.thread
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
;	ld	iy, leaf_frozen_file
;	call	leaf.exec
; 	ld	hl, global_lock
; 	call	atomic_rw.init
; 	
; 	ld	iy, TEST_THREAD_C_DEATH ; thread 3
; 	call	kthread.create	
; 	
.spin:
; 	ld	hl, global_lock
; 	call	atomic_rw.lock_read
; 
; 	ld	hl, 30	; 30 ms is nice
; 	call	kthread.sleep
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

; 	ld	hl, KERNEL_MM_NULL
; 	ld	de, KERNEL_MM_NULL
; 	ld	bc, 65536
; 	ldir
; 	ld	hl, global_lock
; 	call	atomic_rw.unlock_read
		
	jr	.spin
	pop ix
	ret

TEST_THREAD_C_DEATH:
	call __frameset0
;	ld	iy, (kthread_current)
;	set	THREAD_JOIGNABLE, (iy+KERNEL_THREAD_ATTRIBUTE)
; malloc test ;
.spin:
	ld	hl, global_lock
	call	atomic_rw.lock_write
	
; 	ld	hl, 512
; 	call	kmalloc
; 	push	hl
; 	ld	hl, 512
; 	call	kmalloc	
; 	ld	hl, 512
; 	call	kmalloc
; 	pop	hl
; 	call	kfree
	ld	hl, 15
	call	kthread.sleep
	ld	hl, global_lock
	call	atomic_rw.unlock_write
	jr	.spin
; wait ;
; normal path - but not taken
	ld	hl, 0
	call	kthread.exit
	ret

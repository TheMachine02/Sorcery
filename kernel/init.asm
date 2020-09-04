define	BOOT_DIRTY_MEMORY0		$D0009B		; 1 byte ]
define	BOOT_DIRTY_MEMORY1		$D000AC		; 1 byte ] on interrupt
define	BOOT_DIRTY_MEMORY2		$D000FF		; 3 bytes
define	BOOT_DIRTY_MEMORY3		$D00108		; 9 bytes

define	KERNEL_HEAP			$D00100
define	KERNEL_STACK			$D000FF
define	KERNEL_STACK_SIZE		$57
define	KERNEL_RAMFS			$D00000

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
; shift to soft kinit way to reboot ++
; setup temporary stack for the kernel
	ld	sp, $D3FFFF
; setup master interrupt divisor = define jiffies
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
; setup priviliegied OS code (end of OS)
	ld	a, $06
	out0	($1F), a
	xor	a, a
	out0	($1D), a
	out0	($1E), a	
; general system init
; load the ramfs image
	ld	hl, kernel_ramfs_src
	ld	de, KERNEL_RAMFS
	call	lz4.decompress
; setup the kernel stack & protector
	ld	a, $A8
	out0	($3A), a
	xor	a, a
	out0	($3B), a
	ld	a, $D0
	out0	($3C), a
	ld	sp, KERNEL_STACK
	ld	(kernel_stack_pointer), sp
	ld.sis sp, $0000
	ld	MB, a
; memory init, memory protection
	xor	a, a
	out0	($20), a
	out0	($21), a
	dec	a
	out0	($23), a
	ld	a, $0F
	out0	($24), a
	ld	a, $D0
	out0	($22), a
	out0	($25), a
	ld	hl, $D01000
	ld	de, $D01001
	ld	bc, KERNEL_MM_RAM_SIZE - 4097
	ld	(hl), KERNEL_HW_POISON
	ldir
; small init for the vfs
	ld	hl, kvfs.phy_none
	ld	(kvfs_root+KERNEL_VFS_INODE_OP), hl
; power, timer and interrupt ;
	call	kinterrupt.init
	call	kwatchdog.init
	call	kpower.init
; filesystem, should be taken care of with the ramfs
;	call	kvfs.init
; driver init ;
	call	video.init
	call	keyboard.init
	call	rtc.init
; device & driver init ;
;	call	null.init
; create init thread : ie, first program to run (/bin/init/)
	ld	iy, THREAD_INIT_TEST
	call	kthread.create
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
	ld	hl, KERNEL_HEAP
	ld	de, KERNEL_HEAP + 1
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
 db "/dev/",0

THREAD_INIT_TEST:
; 	ld	hl, global_mutex
; 	call	atomic_rw.init
	call	console.init
	call	flash.init	
	
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
;	call	keyboard.irq_lock
	call	console.thread
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

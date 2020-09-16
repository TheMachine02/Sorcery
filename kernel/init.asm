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
; silent : no LCD flashing / console updating, open console only if error
.reboot:
.boot:
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
; create the kernel init thread
	ld	iy, .arch_init
; thread create should enable interrupts
	call	kthread.create
; if this thread create carry, it will get to the arch_sleep and NMI as deadlock
; so, optimise out a jp c, nmi
; nice idle thread code
	ei

.arch_sleep:
; different behaviour are possible
; most dynamic is reduce by one the value
; most brutal is directly set to 6Mhz, we'll need to ramp up
	slp
	jr	.arch_sleep
 
.arch_init:
; here, spawn the thread .init who will mount filesystem, init all driver and device, and then execv into /bin/init
; interrupt will be disabled by most of device init, but that's okay to maintain them in a unknown state anyway
; just don't trigger watchdog please
	call	video.init
	call	keyboard.init
	call	rtc.init
	call	console.init
	call	flash.init
; TODO : if no bin/init found, error out and do a console takeover (console.fb_takeover, which will spawn a console, and the init thread will exit)
; right now, we just do the console takeover directly (if this carry : system error, deadlock, since NO thread is left)
	jp	console.fb_takeover
 
.arch_poison_heap:
	ld	hl, kernel_heap
	ld	de, kernel_heap + 1
	ld	bc, 511
	ld	(hl), KERNEL_HW_POISON
	ldir
	ret
 
kname:
	ld	hl, .name_tag
	ret
; TODO : put this in the certificate ?
.name_tag:
 db CONFIG_KERNEL_NAME, 0
.arch_tag:
 db "ez80", 0

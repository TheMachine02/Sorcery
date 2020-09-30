define	BOOT_DIRTY_MEMORY0		$D0009B		; 1 byte ]
define	BOOT_DIRTY_MEMORY1		$D000AC		; 1 byte ] on interrupt
define	BOOT_DIRTY_MEMORY2		$D000FF		; 3 bytes
define	BOOT_DIRTY_MEMORY3		$D00108		; 9 bytes

define	kernel_data			$D00000		; start of the init image
define	kernel_idle			$D00090		; location of the idle thread image
define	kernel_stack_pointer		$D0009F		; stack pointer within idle thread
define	kernel_stack			$D000FF		; kernel stack
define	kernel_heap			$D00100		; kernel heap

define	KERNEL_STACK_SIZE		87		; size of the stack

define	KERNEL_CRYSTAL_CTLR		$00		; port 00 is master control
define	KERNEL_CRYSTAL_DIVISOR		CONFIG_CRYSTAL_DIVISOR

define	NULL 				0
define	KERNEL_DEV_NULL			$E40000


kinit:
; read kernel paramater
; silent : no LCD flashing / console updating, open console only if error
sysdef _reboot
.reboot:
; boot 5.0.1 stupidity power ++
; note 2 : boot 5.0.1 also crash is rst 0h is run with LCD interrupts on
	di
	rsmix
; load up boot stack
	ld	sp, $D1A87E
; shift to soft kinit way to reboot ++
; we will use temporary boot code stack
; setup master interrupt divisor = define jiffies
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
	ld	de, kernel_data
; setup privileged OS code (end of OS)
; 	ld	a, $03
; 	out0	($1F), a
; 	out0	($1D), e
; 	out0	($1E), e
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
	ld	a, $D0
	ld	MB, a
; setup the kernel stack protector
	ld.sis	sp, $0000
	ld	sp, kernel_stack
	ld	(kernel_stack_pointer), sp
; setup memory protection
	ld	bc, $0620
	ld	hl, .arch_MPU_init
	otir
; stack clash protector
	ld	bc, $033A
	ld	a, b
	otir
; flash ws and mapping
	ld	hl, KERNEL_FLASH_CTRL
	ld	(hl), a
	ld	l, KERNEL_FLASH_MAPPING and $FF
	add	a, a
	ld	(hl), a
; small init for the vfs
	ld	hl, kvfs.phy_none
	ld	(kvfs_root+KERNEL_VFS_INODE_OP), hl
; power, timer and interrupt
	call	kinterrupt.init
	call	kpower.init
	call	kwatchdog.init
; create the kernel init thread
	ld	iy, .arch_init
	call	kthread.create
; if this thread create carry, it will get to the arch_sleep and NMI as deadlock
; so, optimise out a jp c, nmi
; nice idle thread code

.arch_sleep:
	ei
	slp
	jr	.arch_sleep
 
.arch_MPU_init:
 db	$00, $00, $D0, $FF, $0F, $D0
 db	$A8, $00, $D0
 
.arch_init:
; here, spawn the thread .init who will mount filesystem, init all driver and device, and then execv into /bin/init
; interrupt will be disabled by most of device init, but that's okay to maintain them in a unknown state anyway
; just don't trigger watchdog please
	call	video.init
	call	keyboard.init
	call	rtc.init
	call	console.init
; flash device ;
	call	flash.init
; mtd block driver ;
;	call	mtd.init
; debug thread & other debugging stuff
; 	ld	hl, $D30000
; 	call	atomic_mutex.init
; 	ld	iy, DEBUG_THREAD
; 	call	kthread.create
; 	ld	iy, DEBUG_THREAD_2
; 	call	kthread.create
; if no bin/init found, error out and do a console takeover (console.fb_takeover, which will spawn a console, and the init thread will exit)
	ld	bc, .arch_bin_path
	ld	de, .arch_bin_envp
	ld	hl, .arch_bin_argv
	call	leaf.execve
; right now, we just do the console takeover directly (if this carry : system error, deadlock, since NO thread is left)
; TODO printk a message for panic
	xor	a, a
	call	console.fb_takeover
	ld	hl, .arch_bin_error
	call	printk
	jp	console.thread

.arch_bin_path:
 db	"/bin/init",0
.arch_bin_argv:
.arch_bin_envp:
 dl	NULL
.arch_bin_error:
 db	"Failed to execute /bin/init",10,"Running emergency shell",10,0

.arch_poison_heap:
; shouldn't be called within irq
	di
	ld	hl, kernel_heap
	ld	de, kernel_heap + 1
	ld	bc, 506
	ld	(hl), KERNEL_HW_POISON
	ldir
	ei
	ret
 
sysdef _uname
kname:
; hl is structure buf
; copy it
	add	hl, de
	or	a, a
	sbc	hl, de
	ld	a, EFAULT
	jp	z, syserror
; copy data
	ex	de, hl
	ld	bc, 15
	ldir
	ret
; TODO, put this in certificate ?
.name_table:
	dl	.name_system	; Operating system name (e.g., "Sorcery")
	dl	.name_node	; network name ?
	dl	.name_release	; Operating system release (e.g., "1.0.0")
	dl	.name_version	; Operating system version
	dl	.name_architecture	; Hardware identifier
.name_system:
 db CONFIG_KERNEL_NAME, 0
.name_node:
 db "TI-83PCE", 0
.name_release:
 db CONFIG_KERNEL_RELEASE, 0
.name_version:
 db CONFIG_KERNEL_VERSION, 0
.name_architecture:
 db "ez80", 0
 
; DEBUG_THREAD:
; 	ld	hl, 30
; 	call	kthread.sleep
; 	ld	hl, $D30000
; 	call	atomic_mutex.lock
; 	ld	hl, 10
; 	call	kthread.sleep
; 	ld	hl, $D30000
; 	call	atomic_mutex.unlock 
; 	jr	DEBUG_THREAD
; 	
; DEBUG_THREAD_2:
; 	ld	hl, 200
; 	call	kthread.sleep
; 	ld	hl, $D30000
; 	call	atomic_mutex.lock
; 	ld	hl, 100
; 	call	kthread.sleep
; 	ld	hl, $D30000
; 	call	atomic_mutex.unlock
; 	jr	DEBUG_THREAD_2

; TODO : put this in the certificate ?
; flash unlock and lock
flash.lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret
	
flash.unlock:
; need to be in privileged flash actually
	in0	a, ($06)
	or	a, 4
	out0	($06), a
; flash sequence
	ld	a, 4
	di 
	jr	$+2
	di
	rsmix 
	im 1
	out0	($28), a
	in0	a, ($28)
	bit	2, a
	ret

printk:
	push	hl
	ld	bc, 0
	xor	a, a
	cpir
	or	a, a
	sbc	hl, hl
	scf
	sbc	hl, bc
	ex	(sp), hl
	pop	bc
	jp	console.phy_write

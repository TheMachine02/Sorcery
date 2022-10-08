define	BOOT_DIRTY_MEMORY0		$D0009B		; 1 byte ]
define	BOOT_DIRTY_MEMORY1		$D000AC		; 1 byte ] on interrupt
define	BOOT_DIRTY_MEMORY2		$D000FF		; 3 bytes
define	BOOT_DIRTY_MEMORY3		$D00108		; 9 bytes
define	KERNEL_STACK_SIZE		86		; size of the stack
define	KERNEL_CRYSTAL_CTLR		$00		; port 00 is master control
define	KERNEL_CRYSTAL_DIVISOR		CONFIG_CRYSTAL_DIVISOR
define	KERNEL_CRYSTAL_HEART		CONFIG_CRYSTAL_HEART
define	KERNEL_DEV_NULL			$E40000
define	KERNEL_LCD_CLOCK_DIVISOR	$E30008		; the LCD clock timings is derived from CPU clock
define	KERNEL_EMERG			0 
define	KERNEL_ALERT			1
define	KERNEL_CRIT			2
define	KERNEL_ERR			3
define	KERNEL_WARNING			4
define	KERNEL_NOTICE			5
define	KERNEL_INFO			6
define	KERNEL_DEBUG			7
define	kernel_data			$D00000		; start of the init image

define	NULL 				0

macro align number
	rb number - ($ mod number)
end macro

; NOTE : memory map of the initramfs is here
virtual at kernel_data
	include 'bss.asm'
end virtual

init:
; TODO : read kernel paramater
; silent : no LCD flashing / console updating, open console only if error
; boot 5.0.1 stupidity power ++
; NOTE : boot 5.0.1 also crash is rst 0h is run with LCD interrupts on
	di
	rsmix
	in0	a, ($03)
	inc	a
	jp	z, _boot_CheckHardware
; load up boot stack
	ld	sp, $D1A87E
; we will use temporary boot code stack
; setup master interrupt divisor = define jiffies
	ld	a, KERNEL_CRYSTAL_DIVISOR
	out0	(KERNEL_CRYSTAL_CTLR), a
	ld	de, kernel_data
; disable stack protector to be able to write the whole RAM image
	out0	($3A), e
	out0	($3B), e
	out0	($3C), e
; load the initramfs image, 4K
	ld	hl, .arch_initramfs
	call	lz4.decompress
; and init the rest of memory with poison
	ld	hl, KERNEL_MM_GFP_RAM
	ld	de, KERNEL_MM_GFP_RAM + 1
	ld	bc, KERNEL_MM_GFP_RAM_SIZE
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
	otimr
; stack clash protector
	ld	bc, $033A
	otimr
; flash ws and mapping
	ld	hl, KERNEL_FLASH_CTRL
	ld	(hl), $03
	ld	l, KERNEL_FLASH_MAPPING and $FF
	ld	(hl), $06
; small init for the vfs
	ld	hl, tmpfs.memops
	ld	(kvfs_root+KERNEL_VFS_INODE_OP), hl
; power, timer and interrupt
	call	kinterrupt.init
	call	kpower.init
	call	kwatchdog.init
	call	dmesg.init
	ld	hl, .arch_heart
	call	printk
; create the kernel init thread
	ld	iy, .arch_init
	call	kthread.create
; NOTE : if this thread create carry, it will get to the arch_sleep and NMI as deadlock
; so, optimise out a jp c, nmi

.arch_sleep:
; nice idle thread code
	ei
	slp
	jr	.arch_sleep
 
.arch_initramfs:
file	'initramfs'
; NOTE : end guard is part of MPU init (those two $00 are important)

.arch_MPU_init:
 db	$00, $00, $D0, $FF, $7F, $D0
 db	$A8, $00, $D0
 
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
 
.arch_init:
; NOTE : here, spawn the thread .init who will mount filesystem, init all driver and device, and then execv into /bin/init
; interrupt will be disabled by most of device in it, but that's okay to maintain them in a unknown state anyway
; just don't trigger watchdog please
; first mount filesystem with /dev/flash (specially understood by the kernel)
	call	kvfs.mount_root
; hardware device init
	ld	bc, KERNEL_VFS_PERMISSION_RW
	ld	hl, .arch_dev_path
	call	kvfs.mkdir
	call	video.init
	call	keyboard.init
	call	rtc.init
	call	console.init
	call	flash.init
	call	mem.init
; mtd block driver ;
;	call	mtd.init
	ld	hl, .arch_welcome
	call	printk
; now launch init
; if no bin/init found, error out and do a console takeover
	ld	hl, .arch_bin_path
	ld	de, .arch_bin_envp
	ld	bc, .arch_bin_argv
	call	execve
	ld	hl, .arch_bin_error
	call	printk
; right now, we just do the console takeover directly (if this carry : system error, deadlock, since NO thread is left)
	call	console.fb_takeover
	ret	c
; output kernel log to help user
	call	dmesg
	ei
; and open a virtual terminal
	jp	console.vt_init

.arch_dev_path:
 db	"/dev",0
.arch_bin_path:
 db	"/bin/init",0
.arch_bin_argv:
.arch_bin_envp:
 dl	NULL
.arch_bin_error:
 db	$01, KERNEL_ERR, "init: failed to execute /bin/init",10,"init: running emergency shell",10,0
.arch_heart:
 db	$01, KERNEL_INFO, "hw: interrupt heartbeat=", KERNEL_CRYSTAL_HEART, "Hz",10, 0
.arch_welcome:
 db	$01, KERNEL_INFO, "welcome to sorcery !", 10, 0
 
sysdef _reboot
reboot:
; disable interruption and watchdog then rst 0 to the boot code firmware
; it is expected to sync filesystem before reboot and that all thread are proprely shutdown
	di
	call	kwatchdog.disarm
	ld	de, NULL
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	(hl), de
	ld	l, KERNEL_INTERRUPT_ICR and $FF
	dec	de
	ld	(hl), de
	rst	$00

sysdef _uname
uname:
; hl is structure buf
; copy it
	add	hl, de
	or	a, a
	sbc	hl, de
	ex	de, hl
	ld	hl, -EFAULT
	ret	z
; copy data
	ld	hl, .__uname_table
	ld	bc, 15
	ldir
	or	a, a
	sbc	hl, hl
	ret
.__uname_table:
	dl	.name_system		; Operating system name (e.g., "Sorcery")
	dl	.name_node		; network name ?
	dl	.name_release		; Operating system release (e.g., "1.0.0")
	dl	.name_version		; Operating system version
	dl	.name_architecture	; Hardware identifier

.name_system:
 db	CONFIG_KERNEL_NAME, 0
.name_node:
 db	"TI-83PCE", 0
.name_release:
 db	CONFIG_KERNEL_RELEASE, 0
.name_version:
 db	CONFIG_KERNEL_VERSION, 0
.name_architecture:
 db	"ez80", 0
 
printk:
; (start of header) $01, followed by info level at the start of the string is expected
; print time ?
; String is : $01, LEVEL, [time]
; defaut is KERNEL_WARNING 
; write to the ring buffer (and also the tty)
	ld	a, (hl)
	dec	a
	ret	nz
	inc	hl
	inc	hl
.nmi:
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
; hl = string, bc = size
	push	hl
	push	bc
	call	dmesg.write
	pop	bc
	pop	hl
	jp	tty.phy_write

dmesg:
	ld	iy, dmesg_log
.tty:
; output the whole ring buffer to tty device
; iy is the ring read, de is destination buffer, bc is size
	ld	hl, (iy+RING_TAIL)
	ld	bc, (iy+RING_SIZE)
; if tail + size > RING_BOUND_UPP, then we need to first output from tail to bound_up and then from bound_low to size
	add	hl, bc
	ld	bc, (iy+RING_BOUND_UPP)
	or	a, a
	sbc	hl, bc
	jp	p, .__tty_cut_output
; we just need to output from tail for size
	ld	hl, (iy+RING_TAIL)
	ld	bc, (iy+RING_SIZE)
	jp	tty.phy_write
.__tty_cut_output:
	ld	hl, (iy+RING_BOUND_UPP)
	ld	bc, (iy+RING_TAIL)
	or	a, a
	sbc	hl, bc
; this is size
	ex	de, hl
	ld	hl, (iy+RING_SIZE)
	or	a, a
	sbc	hl, de
	push	hl
	inc.s	bc
	ld	b, d
	ld	c, e
	ld	hl, (iy+RING_TAIL)
	call	tty.phy_write
	pop	bc
	ld	a, b
	or	a, c
	ret	z
	ld	iy, dmesg_log
	ld	hl, (iy+RING_BOUND_LOW)
	jp	tty.phy_write

.write:
	ex	de, hl
	ld	iy, dmesg_log
	jp	ring.write

.init:
; create a ring buffer
	ld	iy, dmesg_log
	ld	hl, dmesg_buffer
	jp	ring.create

include	'header/include/ez80.inc'
include	'header/include/tiformat.inc'
; kernel header
include	'header/asm-errno.inc'
include	'header/asm-signal.inc'
include	'header/asm-leaf-def.inc'
include	'header/asm-boot.inc'
; kernel build config
include 'config'

define	VMM_HYPERVISOR_BASE	$0C8000
define	VMM_HYPERVISOR_END	$0D0000

define	VMM_HYPERVISOR_INIT	$D30109
define	VMM_HYPERVISOR_NMI	$D321A9
define	VMM_HYPERVISOR_SIZE	$D30105
define	VMM_HYPERVISOR_IRQ	$D3010D

define	VMM_HYPERVISOR_FLAG	$D0007F
define	VMM_HYPERVISOR_OFFSET	-1
define	VMM_HYPERVISOR_BIT	0

define	VMM_GUEST_INIT		$020109
define	VMM_GUEST_IRQ		$02010D
define	VMM_GUEST_NMI		$0220A9

format	ti executable 'VMM'

vmm_installer:

.install:
; install the kernel in flash at the end of the OS and adapt the size of the OS to reflect the increased size
; touch some hypervisor code so we have an easy jump to base init and irq of TI OS
	ld	hl, (VMM_GUEST_INIT)
	ld	de, vmm.boot
	or	a, a
	sbc	hl, de
	jr	z, .upgrade
	add	hl, de
	ld	(guest_init_ram+1), hl
	ld	hl, (VMM_GUEST_IRQ)
	ld	(guest_irq_ram+1), hl
	ld	hl, (VMM_GUEST_NMI)
	ld	(guest_nmi_ram+1), hl
	jr	.do_install
.upgrade:
	ld	hl, (vmm.guest_init+1)
	ld	(guest_init_ram+1), hl
	ld	hl, (vmm.guest_interrupt+1)
	ld	(guest_irq_ram+1), hl
	ld	hl, (vmm.guest_nmi+1)
	ld	(guest_nmi_ram+1), hl
.do_install:
	di
	call	.unlock
; FIXME : can't work for OS 5.5 and 5.6
.erase:
	ld	a, $0C
	call	.erase_sector
	ld	hl, vmm_ram
	ld	de, VMM_HYPERVISOR_BASE
	ld	bc, sorcery_size
	call	$0002E0
; now we need to patch the OS sector $020000
; use $D30000 as temporary page
	ld	hl, $020000
	ld	de, $D30000
	ld	bc, 65536
	ldir
; patch adress
; change the entry point of the OS (init, interrupt, nmi $0220A8) 
; start of kernel : $0C8000
; 32K free up to $0D000
; set end of OS pointer to this
	ld	hl, VMM_HYPERVISOR_END
	ld	(VMM_HYPERVISOR_SIZE), hl
	ld	hl, vmm.nmi
	ld	(VMM_HYPERVISOR_NMI), hl
	ld	hl, vmm.boot
	ld	(VMM_HYPERVISOR_INIT), hl
	ld	hl, vmm.interrupt
	ld	(VMM_HYPERVISOR_IRQ), hl
	ld	a, $02
	call	.erase_sector
	ld	hl, $D30000
	ld	de, $020000
	ld	bc, 65536
	call	$0002E0
	call	.lock
	xor	a,a
	rst	$00

.erase_sector:
	ld	bc, $f8
	push	bc
	jp	$2dc

.unlock:
	ld	bc, $24
	ld	a, $8c
	call	.write
	ld	bc, $06
	call	.read
	or	a, 4
	call	.write
	ld	bc, $28
	ld	a, $4
	jp	.write
.lock:
	ld	bc, $28
	xor	a, a
	call	.write
	ld	bc, $06
	call	.read
	res	2, a
	call	.write
	ld	bc, $24
	ld	a, $88
	jp	.write
.write:
	ld	de, $C979ED
	ld	hl, $D1887C - 3
	ld	(hl), de
	jp	(hl)
.read:
	ld	de, $C978ED
	ld	hl, $0D1887C - 3
	ld	(hl), de
	jp	(hl)
	
vmm_ram:
	
virtual at $
guest_init_ram:
	jp	$0
guest_irq_ram:
	jp	$0
guest_nmi_ram:
	jp	$0
end virtual

org	VMM_HYPERVISOR_BASE
	
vmm:

.guest_init:
	jp	$0
.guest_interrupt:
	jp	$0
.guest_nmi:
	jp	$0

.interrupt:
	bit	VMM_HYPERVISOR_BIT, (iy+VMM_HYPERVISOR_OFFSET)
	jr	z, .guest_interrupt
	jp	kinterrupt.irq_handler

.nmi:
	push	iy
	ld	iy, $D00080
	bit	VMM_HYPERVISOR_BIT, (iy+VMM_HYPERVISOR_OFFSET)
	pop	iy
	jr	z, .guest_nmi
	jp	nmi.handler
	
.boot:
	di
; ti os = bit reset
; kernel = bit set
; nice little boot loader
; LCD to 8 bits
	ld	hl, $D40000
	ld	($E30010), hl
	ld	a,$27
	ld	($E30018), a
; colors 0, 1
	or	a, a
	sbc	hl, hl
	ld	($E30200), hl
	dec	hl
	ld	($E30202), hl
	
	ld	hl, $E40000
	ld	de, $E30204
	ld	bc, 508
	ldir
	
	ld	ix, $000100
	
	ld	hl, 0
	ld	bc, .string_boot0
	call	.string
	
	ld	hl, 19*256+0
	ld	bc, .string_enter
	call	.string
	
	xor	a, a
.boot_choose_loop:
	push	af
	ld	b, 8
.wait:
	push	bc
	call	video.vsync
	pop	bc
	djnz	.wait
	pop	af
	push	af
	ld	ix, $000100
	or	a, a
	jr	nz, .not_reverse
	ld	ix, $010001
.not_reverse:
	ld	hl, 1*256+3
	ld	bc, .string_boot1
	call	.string
	pop	af
	push	af
	ld	ix, $000100
	or	a, a
	jr	z, .not_reverse2
	ld	ix, $010001
.not_reverse2:
	ld	hl, 2*256+3
	ld	bc, .string_boot2
	call	.string
	ld	hl, $F50000
	ld	(hl), 2
	xor	a, a
.scan_wait:
	cp	a, (hl)
	jr	nz, .scan_wait
	pop	af
	ld	hl, $F5001E
	bit	0, (hl)
	jr	z, $+3
	cpl
	bit	3, (hl)
	jr	z, $+3
	cpl
	ld	hl, $F5001C
	bit	0, (hl)
	jr	z, .boot_choose_loop
	
	or	a, a
	jr	z, .tios_init
	ld	iy, $D00080
	set	VMM_HYPERVISOR_BIT, (iy+VMM_HYPERVISOR_OFFSET)
	jp	init
.tios_init:
; FIXME : we need to explain to the OS that he is smaller
; invisible variable taking up to $0D0000 ??
	ld	hl, $E40000
	ld	de, $D40000
	ld	bc, 76800*2
	ldir
	ld	a,$2D
	ld	($E30018), a
	jp	.guest_init
	
.string:
; use the kernel function
; display string bc @ hl (y - x)
	call	console.glyph_adress
.string_loop:
	ld	a, (bc)
	or	a, a
	ret	z
	push	bc
	call	.char
	pop	bc
	inc	bc
	jr	.string_loop
	
.char:
	push	iy
	ld	l, a
	ld	h, 3
	mlt	hl
	ld	bc, font.TRANSLATION_TABLE
	add	hl, bc
	lea	bc, ix+0
	ld	iy, (hl)
	ex	de, hl
	ld	de, 315
	jp	console.glyph_char_loop	

.string_boot0:
 db "Choose OS to boot from :", 0
.string_boot1:
 db "TI-os version x.x.x", 0
.string_boot2:
 db "Sorcery version x.x.x", 0
 
.string_enter:
 db "Press enter to boot selected entry", 0

; now, the whole kernel 
 
sorcery:

sysjump:
	jp	_open
	jp	_close
	jp	_enosys		; _rename
	jp	_enosys		; _link
	jp	_enosys		; _unlink
	jp	_read
	jp	_write
	jp	_lseek
	jp	_enosys		; _chdir
	jp	_sync
	jp	_access
	jp	_chmod
	jp	_chown
	jp	_stat
	jp	_fstat
	jp	_dup
	jp	_getpid
	jp	_getppid
	jp	_enosys		; _statfs
	jp	_execve
	jp	_enosys		; _getdirent
	jp	_enosys		; _time
	jp	_enosys		; _stime
	jp	_ioctl
	jp	_brk
	jp	_sbrk
	jp	_enosys		; _vfork
	jp	_enosys		; _mount
	jp	_enosys		; _umount
	jp	_enosys		; _signal
	jp	_pause
	jp	_alarm
	jp	_kill
	jp	_pipe
	jp	_enosys		; _times
	jp	_enosys		; _utime
	jp	_chroot
	jp	_enosys		; _fcntl
	jp	_enosys		; _fchdir
	jp	_fchmod
	jp	_fchown
	jp	_mkdir
	jp	_rmdir
	jp	_mknod
	jp	_mkfifo
	jp	_uname
	jp	_enosys		; _waitpid
	jp	_profil
	jp	_uadmin
	jp	_nice
	jp	_enosys		; _sigdisp
	jp	_enosys		; _flock
	jp	_yield
	jp	_schedule
	jp	_kmalloc
	jp	_kfree
	jp	_enosys		; _select
	jp	_enosys		; _getrlimit
	jp	_enosys		; _setrlimit
	jp	_enosys		; _setsid
	jp	_enosys		; _getsid
	jp	_shutdown
	jp	_reboot
	jp	_usleep
	jp	_priv_lock
	jp	_priv_unlock
	jp	_flash_lock
	jp	_flash_unlock
	jp	_printk
; 	jp	_socket
; 	jp	_listen
; 	jp	_bind
; 	jp	_connect
; 	jp	_accept
; 	jp	_getsockaddrs
; 	jp	_sendto
; 	jp	_recvfrom
; NOTE : special vm init and interrupts
; we need to reallocate kernel memory to $D30000, so all the memory map change

include	'kernel/init.asm'
include	'kernel/interrupt.asm'
include	'kernel/nmi.asm'
include	'kernel/watchdog.asm'
include	'kernel/power.asm'
include	'kernel/thread.asm'
include	'kernel/queue.asm'
include	'kernel/fifo.asm'
include	'kernel/signal.asm'
include	'kernel/restart.asm'
include	'kernel/syscall.asm'
include	'kernel/timer.asm'
include	'kernel/vfs.asm'
include	'kernel/inode.asm'
include	'kernel/arch/atomic.asm'
include	'kernel/arch/debug.asm'
include	'kernel/mm/mm.asm'
include	'kernel/mm/cache.asm'
include	'kernel/mm/slab.asm'
include	'kernel/compress/lz4.asm'
include	'kernel/arch/pic.asm'
include	'kernel/arch/leaf.asm'
include	'kernel/arch/ldso.asm'
include	'fs/romfs.asm'
include	'kernel/font/gohufont.inc'

; driver & device
include	'kernel/driver/video.asm'
include	'kernel/driver/rtc.asm'
include	'kernel/driver/hrtimer.asm'
include	'kernel/driver/keyboard.asm'
include	'kernel/driver/spi.asm'
include	'kernel/driver/usb.asm'
include	'kernel/driver/mtd.asm'
include	'kernel/driver/console.asm'
; NOTE : dev console must follow driver/console code
include	'kernel/dev/console.asm'
include	'kernel/dev/null.asm'
include	'kernel/dev/flash.asm'

; WARNING : flash breakage right here !

;sorcery_size = $ - VMX_KERNEL_BASE
sorcery_size = 32768

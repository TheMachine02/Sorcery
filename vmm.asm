include	'header/include/ez80.inc'
include	'header/include/tiformat.inc'
; kernel header
include	'header/asm-errno.inc'
include	'header/asm-signal.inc'
include	'header/asm-leaf-def.inc'
include	'header/asm-boot.inc'
; kernel build config
include 'config'

define	VMM_KERNEL_BASE		$0C8000
define	VMM_KERNEL_END		$0D0000

define	VMM_HYPERVISOR_INIT	$D30109
define	VMM_HYPERVISOR_NMI	$D321A9
define	VMM_HYPERVISOR_SIZE	$D30105
define	VMM_HYPERVISOR_IRQ	$D3010D

define	VMM_GUEST_INIT		$020109
define	VMM_GUEST_IRQ		$02010D

format	ti executable 'VMM'

vmm:

.install:
; install the kernel in flash at the end of the OS and adapt the size of the OS to reflect the increased size

	di
	call	.unlock
; FIXME : can't work for OS 5.5 and 5.6
.erase:
	ld	a, $0C
	call	.erase_sector
	
; touch some hypervisor code so we have an easy jump to base init and irq of TI OS
	ld	hl, (VMM_GUEST_INIT)
	ld	(guest_init+1), hl
	ld	hl, (VMM_GUEST_IRQ)
	ld	(guest_irq+1), hl
	ld	hl, sorcery
	ld	de, VMM_KERNEL_BASE
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
	ld	hl, VMM_KERNEL_END
	ld	(VMM_HYPERVISOR_SIZE), hl
	ld	hl, (.arch_nmi)
	ld	(VMM_HYPERVISOR_NMI), hl
	ld	hl, (.arch_init)
	ld	(VMM_HYPERVISOR_INIT), hl
	ld	hl, (.arch_interrupt)
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

.arch_nmi:
 dl	nmi.handler
.arch_interrupt:
 dl	kinterrupt.irq_handler
.arch_init:
 dl	init
	
sorcery:
guest_init:
	jp	$0
guest_irq:
	jp	$0
; NOTE : we need to offset the two jump
org	VMM_KERNEL_BASE + 8
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

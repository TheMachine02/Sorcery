include	'header/include/ez80.inc'
; kernel header
include	'header/asm-errno.inc'
include	'header/asm-signal.inc'
include	'header/asm-boot.inc'
; kernel build config
include 'config'
include	'header/asm-leaf.inc'

LEAF.settings.flags:=LF_STATIC

entry sorcery

org	$D01000
section '.boot' writeable

sorcery:
	jp	init
sorcery_hypervisor:
	jp	kinterrupt.irq_handler
	jp	nmi.handler
	dd	$DEC0ADDE
	db CONFIG_KERNEL_NAME, "-", CONFIG_KERNEL_VERSION,0

assert $ < $D01040
org	$D01040
section '.sys' writeable
sysjump:
; the kernel syscall jump table
; align this to 4 bytes
; NOTE : DO NOT CHANGE ORDER
	jp	_open
	jp	_close
	jp	_rename
	jp	_link
	jp	_unlink
	jp	_symlink
	jp	_read
	jp	_write
	jp	_lseek
	jp	_chdir
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
	jp	_time
	jp	_stime
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
	jp	_times
	jp	_clock
	jp	_chroot
	jp	_enosys		; _fcntl
	jp	_fchdir
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
	jp	_flash_lock
	jp	_flash_unlock
	jp	_printk
	jp	_thread
	jp	_dma_access
	jp	_dma_blk
	jp	_dma_release
; 	jp	_socket
; 	jp	_listen
; 	jp	_bind
; 	jp	_connect
; 	jp	_accept
; 	jp	_getsockaddrs
; 	jp	_sendto
; 	jp	_recvfrom
; NOTE : max 240 syscall, should be way more than enough
align	1024
sysinternal:
; internal API are all within these, driver binding etc

include	'kernel/init.asm'
include	'kernel/interrupt.asm'
include	'kernel/watchdog.asm'
include	'kernel/power.asm'
include	'kernel/thread.asm'
include	'kernel/queue.asm'
include	'kernel/clock.asm'
include	'kernel/fifo.asm'
include	'kernel/signal.asm'
include	'kernel/restart.asm'
include	'kernel/syscall.asm'
include	'kernel/timer.asm'
include	'kernel/vfs.asm'
include	'kernel/dma.asm'
include	'kernel/inode.asm'
include	'kernel/arch/atomic.asm'
include	'kernel/arch/debug.asm'
include	'kernel/mm/mm.asm'
include	'kernel/mm/cache.asm'
include	'kernel/mm/slab.asm'
include	'kernel/compress/lz4.asm'
include	'kernel/nmi.asm'
include	'kernel/arch/pic.asm'
include	'kernel/arch/leaf.asm'
include	'kernel/arch/ldso.asm'
include	'fs/romfs.asm'
include	'fs/tifs.asm'
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

init_conway:
include	'conway.asm'

assert $ < $D08000

kernel_size strcalc $D08000 - $
display "kernel space left : ", kernel_size," bytes."

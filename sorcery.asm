include	'header/include/ez80.inc'
include	'header/include/tiformat.inc'
include	'header/include/os.inc'
; kernel header
include	'header/asm-errno.inc'
include	'header/asm-signal.inc'
include	'header/asm-leaf-def.inc'
include	'header/asm-boot.inc'
; kernel build config
include 'config'

format	ti executable 'SORCERY'

;-------------------------------------------------------------------------------
	os_create
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
	os_rom
;-------------------------------------------------------------------------------

sorcery:
include 'certificate.asm'
; we'll set as occupying 1 sectors - or 64KB
	db	$5A, $A5, $FF, $01
	jp	sorcery_end
	jp	init
	jp	kinterrupt.irq_handler
	jp	restart.10h
	jp	restart.18h
	jp	restart.20h
	jp	restart.28h
	jp	restart.30h
; align this to 4 bytes
sysjump:
	jp	_open
	jp	_close
	jp	_enosys		; _rename
	jp	_enosys		; _link
	jp	_enosys		; _unlink
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

include	'kernel/init.asm'
include	'kernel/interrupt.asm'
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
; be sure we are in the correct spot for NMI
 assert $ < $0220A8
 rb $0220A8-$
include	'kernel/nmi.asm'
include	'kernel/arch/pic.asm'
include	'kernel/arch/leaf.asm'
include	'kernel/arch/ldso.asm'
include	'fs/romfs.asm'
include	'fs/tifs.asm'
; kernel_romfs:
; file	'rootfs'
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

sorcery_end:

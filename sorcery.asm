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

Sorcery:
include 'sorcery_certificate.asm'
; we'll set as occupying 4 sectors - or 256KB
	db	$5A, $A5, $FF, $04
	jp	__end
.syscall:
	jp	kinit
	jp	kinterrupt.irq_handler
	jp	restart.10h
	jp	restart.18h
	jp	restart.20h
	jp	restart.28h
	jp	restart.30h
	jp	nmi.handler
	
include	'kernel/init.asm'
include	'kernel/interrupt.asm'
include	'kernel/watchdog.asm'
include	'kernel/power.asm'
include	'kernel/thread.asm'
include	'kernel/queue.asm'
include	'kernel/ring.asm'
include	'kernel/signal.asm'
include	'kernel/restart.asm'
include	'kernel/syscall.asm'
include	'kernel/timer.asm'
include	'kernel/mm/mm.asm'
include	'kernel/mm/cache.asm'
include	'kernel/mm/slab.asm'
include	'kernel/vfs.asm'
include	'kernel/inode.asm'
include	'kernel/arch/atomic.asm'
include	'kernel/arch/debug.asm'
include	'kernel/arch/pic.asm'
include	'kernel/compress/lz4.asm'
include	'kernel/exec/leaf.asm'
include	'fs/romfs.asm'
include	'kernel/nmi.asm'

kernel_initramfs:
file	'initramfs'
; end guard
 db	$00, $00
kernel_romfs:
file	'rootfs'

include	'kernel/driver/video.asm'
include	'kernel/driver/rtc.asm'
include	'kernel/driver/hrtimer.asm'
include	'kernel/driver/keyboard.asm'
include	'kernel/driver/spi.asm'
; driver & device
include	'kernel/dev/null.asm'
include	'kernel/driver/console.asm'
include	'kernel/dev/console.asm'
include	'kernel/font/gohufont.inc'
include	'kernel/driver/flash.asm'
include	'kernel/dev/flash.asm'

; WARNING, flash breakage right here !

; include	'kernel/exec/kexec.asm'
; include	'kernel/exec/kso.asm'
; include	'kernel/exec/kelf.asm'


__end:

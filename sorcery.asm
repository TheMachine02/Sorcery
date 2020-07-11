include	'include/ez80.inc'
include	'include/asm-errno.inc'
include	'include/asm-signal.inc'
include	'include/tiformat.inc'
include	'include/os.inc'
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
.start:
	db	$5a,$a5,$ff,$04
	jp	_endos
.syscall:
	jp	kinit
	jp	kinterrupt.service
	jp	kinterrupt.rst10
	jp	kinterrupt.rst18
	jp	kinterrupt.rst20
	jp	kinterrupt.rst28
	jp	kinterrupt.rst30
	jp	kinterrupt.nmi
	
include	'kernel/init.asm'
include	'kernel/interrupt.asm'
include	'kernel/irq.asm'
include	'kernel/watchdog.asm'
include	'kernel/power.asm'
include	'kernel/thread.asm'
include	'kernel/queue.asm'
include	'kernel/ring.asm'
include	'kernel/signal.asm'
include	'kernel/timer.asm'
include	'kernel/mm.asm'
include	'kernel/slab.asm'
include	'kernel/vfs.asm'
include	'kernel/nmi.asm'

include	'kernel/arch/atomic.asm'
include	'kernel/compress/lz4.asm'
include	'kernel/crypto/crc.asm'
include	'kernel/driver/video.asm'
include	'kernel/driver/rtc.asm'
include	'kernel/driver/hrtimer.asm'
include	'kernel/driver/keyboard.asm'
include	'kernel/driver/console.asm'
include	'kernel/fpu/idiv.asm'
; include	'kernel/exec/kexec.asm'
; include	'kernel/exec/kso.asm'
; include	'kernel/exec/kelf.asm'

; rb	$060000 - $

include	'kernel/dev/flash.asm'

org $060000
_endos:

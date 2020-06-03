include	'include/ez80.inc'
include	'include/asm-errno.inc'
include	'include/asm-signal.inc'
include	'include/tiformat.inc'
format	ti executable 'SORCERY'
include	'include/os.inc'

include 'config'

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
; 020110
	jp	kinterrupt.rst10
	jp	kinterrupt.rst18
	jp	kinterrupt.rst20
	jp	kinterrupt.rst28
	jp	kinterrupt.rst30
	jp	kinterrupt.nmi
	
include	'kernel/kinit.asm'
include	'kernel/kinterrupt.asm'
include	'kernel/kirq.asm'
include	'kernel/kwatchdog.asm'
include	'kernel/kpower.asm'
include	'kernel/kthread.asm'
include	'kernel/kqueue.asm'
include	'kernel/ksignal.asm'
include	'kernel/ktimer.asm'
include	'kernel/katomic.asm'
include	'kernel/kmsg.asm'
include	'kernel/kmmu.asm'
 rb	$0220A8-$
include	'kernel/knmi.asm'
include	'kernel/kflash.asm'
;include	'kernel/kvfs.asm'

include	'kernel/fpu/idiv.asm'
include	'kernel/exec/kexec.asm'
include	'kernel/exec/kso.asm'
include	'kernel/exec/kelf.asm'
include	'kernel/crypto/kcrc.asm'

include	'kernel/driver/video.asm'
include	'kernel/driver/rtc.asm'
include	'kernel/driver/hrtimer.asm'
include	'kernel/driver/keyboard.asm'


elf_frozen_example:
file	'executable.hex'

elf_frozen_library:
file	'libtest.hex'

; rb	$060000 - $
org $060000
_endos:

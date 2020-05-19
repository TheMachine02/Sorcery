include	'include/ez80.inc'
include	'include/tiformat.inc'
format	ti executable 'ZEPHYR'
include	'include/os.inc'

;-------------------------------------------------------------------------------
	os_create
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
	os_rom
;-------------------------------------------------------------------------------

include 'zephyr_page0.asm'
	db	$5a,$a5,$ff,$00
	jp	$030000
KERNEL_JUMP_TABLE:
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
include	'kernel/ksignal.asm'
include	'kernel/kqueue.asm'
include	'kernel/katomic.asm'
include	'kernel/kmmu.asm'
 rb	$0220A8-$
include	'kernel/kpanic.asm'
include	'kernel/kflash.asm'
include	'kernel/kcachefs.asm'


include	'kernel/exec/kexec.asm'
include	'kernel/crypto/kcrc.asm'
include	'kernel/driver/video.asm'
;include	'kernel/driver/rtc.asm'
;include	'kernel/driver/timer.asm'
include	'kernel/driver/keyboard.asm'

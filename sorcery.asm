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
	jp	kinterrupt.rst10
	jp	kinterrupt.rst18
	jp	kinterrupt.rst20
	jp	kinterrupt.rst28
	jp	kinterrupt.rst30
	jp	kinterrupt.nmi
; system
	jp	kname
; mutex syscall
	jp	kmutex.init
	jp	kmutex.try_lock
	jp	kmutex.lock
	jp	kmutex.unlock
; irq syscall
	jp	kirq.request
	jp	kirq.free
	jp	kirq.enable
	jp	kirq.disable
; queue function
	jp	kqueue.insert_current
	jp	kqueue.insert_end
	jp	kqueue.remove
; thread
	jp	kthread.yield
	jp	kthread.create
	jp	kthread.wait_on_IRQ
	jp	kthread.resume_from_IRQ
	jp	kthread.suspend
	jp	kthread.resume
	jp	kthread.once
	jp	kthread.core
	jp	kthread.exit
	jp	kthread.sleep
	jp	kthread.get_pid
	jp	kthread.get_ppid
	jp	kthread.get_heap_size
; signal
	jp	ksignal.abort
	jp	ksignal.raise
	jp	ksignal.kill
	jp	ksignal.wait
	jp	ksignal.timed_wait
	jp	ksignal.procmask_single
	jp	ksignal.procmask
; timer
	jp	klocal_timer.create
	jp	klocal_timer.delete
; mmu syscall
	jp	kmmu.map_page
	jp	kmmu.map_page_thread
	jp	kmmu.map_block
	jp	kmmu.map_block_thread
	jp	kmmu.unmap_page
	jp	kmmu.unmap_page_thread
	jp	kmmu.unmap_block
	jp	kmmu.unmap_block_thread
	jp	kmmu.zero_page
	jp	kmalloc
	jp	kfree
; printk
	jp	kmsg.printk
	jp	kmsg.dmesg
; power	
	jp	kpower.get_battery_charging_status
	jp	kcstate.get_clock
	jp	kcstate.set_clock
	
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

include	'kernel/compress/lz4.asm'

elf_frozen_example:
file	'executable.hex'

elf_frozen_library:
file	'libtest.hex'

lz4_frozen:
file	'kernel/kthread.asm.lz4'

; rb	$060000 - $
org $060000
_endos:

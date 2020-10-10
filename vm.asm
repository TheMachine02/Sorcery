include	'header/include/ez80.inc'
include	'header/include/tiformat.inc'
include	'header/asm-leaf-def.inc'

format	ti executable 'VMLOADER'

define	LOADER_RAM		$D30000
define	LOADER_OS_PATCH		$020000
define	LOADER_OS_APPEND	$0B0000

virtual at LOADER_RAM
vm_string:
 rb 32
vm_tios_version:
 db 0, 0
vm_tios_rev: 
 db 0
end virtual

virtual at LOADER_RAM
	rb	256
	db	$5A, $A5, $FF, $FF
_os_size:=$+1
	jp	$0C0000
_os_init:=$+1
	jp	$0
_os_irq:=$+1
	jp	$0
	rb	$D320A8-$
_os_nmi:=$+1
	jp	$0
end virtual

sulphur:

.detect_patch:
	ld	hl, ($020109)
	ld	de, hypervisor.init
	or	a, a
	sbc	hl, de
	jr	nz, .detect_use_OS__path
; read data from the hypervisor	
	ld	hl, (guest_tios_interrupt_jp)
	ld	(guest_tios_interrupt_jp_ram), hl
	ld	hl, (guest_tios_nmi_jp)
	ld	(guest_tios_nmi_jp_ram), hl
	ld	hl, (guest_tios_boot_jp)
	ld	(guest_tios_boot_jp_ram), hl
	jr	.detect_unlock
.detect_use_OS__path:
	ld	hl, ($02010D)
	ld	(guest_tios_interrupt_jp_ram), hl
	ld	hl, ($0220A9)
	ld	(guest_tios_nmi_jp_ram), hl
	ld	hl, ($020109)
	ld	(guest_tios_boot_jp_ram), hl
.detect_unlock:
	di
	call	.unlock
.detect_os_version:
; this all reside in RAM
	call    _os_GetSystemStats
	push	hl
	pop	ix
; version  = hl
	ld	de, (ix+6)
; $010505 is OS 5.5.1 for exemple
	ld	(vm_tios_version), de
	or	a, a
	sbc	hl, hl
	ld	a, (vm_tios_rev)
	ld	l, a
	push	hl
	ld	l, d
	push	hl
	ld	l, e
	push	hl
	ld	hl, .tios_version
	push	hl
	ld	hl, vm_string
	push	hl
	call	_sprintf
	ld	hl, 5*3
	add	hl, sp
; copy the detected OS string to the correct area
	ld	hl, vm_string
	ld	de, guest_tios_name_ram
	ld	bc, 19
	ldir
.append_os:
	ld	hl, LOADER_OS_APPEND
	ld	de, LOADER_RAM
	ld	bc, 65536
	ldir
	ld	hl, hypervisor_ram
	ld	de, VM_HYPERVISOR_RAM_ADRESS
	ld	bc, $1000
	ldir
	ld	a, $0B
	call	.erase_sector
	ld	hl, LOADER_RAM
	ld	de, LOADER_OS_APPEND
	ld	bc, 65536
	call	$0002E0
.patch_os:
; now we need to patch the OS sector $020000
; use $D30000 as temporary page
	ld	hl, LOADER_OS_PATCH
	ld	de, LOADER_RAM
	ld	bc, 65536
	ldir
; patch adress
; change the entry point of the OS (init, interrupt, nmi $0220A8) 
; start of kernel : $0C8000
; 32K free up to $0D000
; set end of OS pointer to this
	ld	hl, $0C0000
	ld	(_os_size), hl
	ld	hl, hypervisor.nmi
	ld	(_os_nmi), hl
	ld	hl, hypervisor.init
	ld	(_os_init), hl
	ld	hl, hypervisor.interrupt
	ld	(_os_irq), hl
	ld	a, $02
	call	.erase_sector
	ld	hl, LOADER_RAM
	ld	de, LOADER_OS_PATCH
	ld	bc, 65536
	call	$0002E0
; lock and reset
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
	
.tios_version:
 db "TI-os version %d.%d.%d", 0
 
include	'hypervisor/hypervisor.asm'
include	'hypervisor/video.asm'
include	'hypervisor/gohufont.inc'
include	'hypervisor/boot.asm'
 rb	$0C0000 - $
 db	$0

define	VM_HYPERVISOR_FLAG	$D00080
define	VM_HYPERVISOR_DATA	-8
define	VM_HYPERVISOR_ADRESS	$0BE000

hypervisor_ram:=$
hypervisor_offset:= $ - hypervisor
guest_tios_interrupt_jp_ram:= guest_tios_interrupt_ptr + hypervisor_offset
guest_tios_nmi_jp_ram:= guest_tios_nmi_jp + hypervisor_offset
guest_tios_boot_jp_ram:= guest_tios_boot_jp + hypervisor_offset

org	VM_HYPERVISOR_ADRESS

hypervisor:

.interrupt:
	ld	hl, (iy+VM_HYPERVISOR_DATA)
	ld	hl, (hl)
	or	a, a
	add	hl, de
	sbc	hl, de
	jr	z, .interrupt_failure
	jp	(hl)
.interrupt_failure:
; we'll need to acknowledge interrupt ourselves if we are in this very special case where interrupt are on, but we have not yet reached boot code (stupid boot 5.0.0)
	ld	hl, $F00014
	ld	bc, (hl)
	ld	l, $F00008 and $FF
	ld	(hl), bc
	pop	hl
	pop	iy
	pop	ix
	exx
	ex	af, af'
	ei
	ret

.nmi:
	push	hl
	push	af
	push	iy
	ld	iy, VM_HYPERVISOR_FLAG
	ld	hl, (iy+VM_HYPERVISOR_DATA)
	inc	hl
	inc	hl
	inc	hl
	ld	hl, (hl)
	or	a, a
	add	hl, de
	sbc	hl, de
	pop	iy
	jr	z, .restart
	pop	af
	ex	(sp), hl
	ret
.restart:
	pop	af
	pop	hl
; nothing loaded ? Boot reset
	rst	$08
	
guest_tios:
.interrupt:
guest_tios_interrupt_jp:=$+1
	jp	$0
.nmi:
guest_tios_nmi_jp:=$+1
	jp	$0
.init:
; cleanup LCD state
	ld	hl, $E40000
	ld	de, $D40000
	ld	bc, 76800*2
	ldir
	ld	a,$2D
	ld	($E30018), a
; actual jump pointer
guest_tios_boot_jp:=$+1
	jp	$0
	
guest_sorcery:
; none, sorcery expose itself the correct pointer table

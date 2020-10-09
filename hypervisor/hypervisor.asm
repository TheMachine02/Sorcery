define	VM_HYPERVISOR_FLAG		$D00080
define	VM_HYPERVISOR_SETTINGS		-1
define	VM_HYPERVISOR_DATA		-4
define	VM_HYPERVISOR_ADRESS		$0BE000
define	VM_HYPERVISOR_RAM_ADRESS	$D3E000
define	VM_HYPERVISOR_RAM		$D00000		; some scratch RAM
define	VM_HYPERVISOR_LUT		0
define	VM_HYPERVISOR_AWARE		$DEC0DAED

_sprintf                   equ 00000BCh
_os_GetSystemStats         equ 0021ED4h

virtual at VM_HYPERVISOR_RAM
vm_guest_count:
 db 0
; guest table pointing to "header" of leaf file
vm_guest_table:
 rb 54
vm_cursor:
 db 0
end virtual

hypervisor_ram:=$
guest_tios_offset:= $ - guest_tios
guest_tios_interrupt_jp_ram:= guest_tios_interrupt_jp + guest_tios_offset
guest_tios_nmi_jp_ram:= guest_tios_nmi_jp + guest_tios_offset
guest_tios_boot_jp_ram:= guest_tios_boot_jp + guest_tios_offset
guest_tios_name_ram:= guest_tios_name + guest_tios_offset

org	VM_HYPERVISOR_ADRESS

guest_tios:
; header
	jr	.init
	dw	$0000
.interrupt:
guest_tios_interrupt_jp:=$+1
	jp	$0
.nmi:
guest_tios_nmi_jp:=$+1
	jp	$0
	dd	VM_HYPERVISOR_AWARE
guest_tios_name:=$
	db "TI-os version 0.0.0", 0
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

guest_custom:
; custom image should be leaf file exposing a 'special' header at entry point
; jp .init / jp .interrupt / jp .nmi / dd VM_HYPERVISOR_AWARE / NAME / db 0

hypervisor:
; NOTE : we check for value = 0, but overriding the value in RAM could be *very* bad either way

.init:
	call	.boot_detect
	bit	VM_HYPERVISOR_LUT, (iy+VM_HYPERVISOR_SETTINGS)
	jr	z, guest_tios.init
	ld	hl, (iy+VM_HYPERVISOR_DATA)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .init_failure
	ld	bc, 8
	add	hl, bc
	ld	hl, (hl)
	jp	(hl)
.init_failure:
; hum hum
	rst	0

.interrupt:
	bit	VM_HYPERVISOR_LUT, (iy+VM_HYPERVISOR_SETTINGS)
	jr	z, guest_tios.interrupt
	ld	hl, (iy+VM_HYPERVISOR_DATA)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .interrupt_failure
	ld	hl, (hl)
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
	bit	VM_HYPERVISOR_LUT, (iy+VM_HYPERVISOR_SETTINGS)
	jr	z, guest_tios.nmi
	push	hl
	push	af
	push	iy
	ld	iy, VM_HYPERVISOR_FLAG
	ld	hl, (iy+VM_HYPERVISOR_DATA)
	add	hl, de
	or	a, a
	sbc	hl, de
	pop	iy
	jr	z, .nmi_restart
	pop	af
	ld	hl, (hl)
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	ex	(sp), hl
	ret
.nmi_restart:
	pop	af
	pop	hl
; nothing loaded ? Boot reset
	rst	$08
	
.boot_detect:
	di
	or	a, a
	sbc	hl, hl
	ld	(VM_HYPERVISOR_DATA), hl
; NOTE : does there is even a TI OS installed ? 
; (in theory, we answer always here, since we chained ourselves to the TIOS, and we will fall with it)
; try to detect ti os version
	ld	hl, guest_tios
	ld	(vm_guest_table), hl
	ld	hl, guest_tios
	ld	(vm_guest_table+4), hl
	ld	hl, guest_tios
	ld	(vm_guest_table+8), hl
	ld	a, 1
	ld	(vm_guest_count), a
	xor	a, a
	ld	(vm_cursor), a
; we have the correct substring version, and entry point with guest_tios
; we need to parse tifs and find leaf file that could be launched
	call	.boot_search_leaf
; the table was filled
; minimal LCD init
	ld	hl, $D40000
	ld	($E30010), hl
	ld	a,$27
	ld	($E30018), a
	or	a, a
	sbc	hl, hl
	ld	($E30200), hl
	dec	hl
	ld	($E30202), hl
; palette cleanup
	ld	hl, $E40000
	ld	de, $E30204
	ld	bc, 508
	ldir
	ld	ix, $000100
	ld	hl, 0
	ld	bc, .boot_string_choose
	call	.putstring
	ld	hl, 19*256+0
	ld	bc, .boot_string_enter
	call	.putstring
	
.boot_choose_loop:
	ld	b, 8
.wait:
	push	bc
	call	.vsync
	pop	bc
	djnz	.wait

	ld	hl, 1*256+3
.boot_display_name:
	ld	a, (vm_guest_count)
	ld	b, a
.boot_display_loop:
	push	hl
	push	bc
	ld	a, (vm_cursor)
	inc	a
	ld	ix, $000100
	cp	a, h
	jr	nz, .boot_reverse_color
	ld	ix, $010001
.boot_reverse_color:
;;	ld	hl, 2*256+3
	push	hl
	ld	a, h
	dec	a
	or	a, a
	sbc	hl, hl
	ld	l, a
	add	hl, hl
	add	hl, hl
	ld	bc, vm_guest_table
	add	hl, bc
	ld	hl, (hl)
	ld	bc, 16
	add	hl, bc
	push	hl
	pop	bc	
	pop	hl
	call	.putstring
	pop	bc
	pop	hl
	inc	h
	djnz	.boot_display_loop
	ld	hl, $F50000
	ld	(hl), 2
	xor	a, a
.scan_wait:
	cp	a, (hl)
	jr	nz, .scan_wait

	ld	hl, vm_cursor
	ld	a, ($F5001E)
	bit	0, a
	jr	z, $+3
	inc	(hl)
	bit	3, a
	jr	z, $+3
	dec	(hl)
		
	ld	hl, $F5001C
	bit	0, (hl)
	jr	z, .boot_choose_loop
	
	ld	iy, VM_HYPERVISOR_FLAG
	ld	a, (vm_cursor)
	or	a, a
	res	VM_HYPERVISOR_LUT, (iy+VM_HYPERVISOR_SETTINGS)
	ret	z
	or	a, a
	sbc	hl, hl
	ld	l, a
	add	hl, hl
	add	hl, hl
	ld	bc, vm_guest_table
	add	hl, bc
	ld	hl, (hl)
	ld	(iy+VM_HYPERVISOR_DATA), hl
	ret

.boot_search_leaf:
	ret
	
.boot_string_choose:
 db "Choose OS to boot from :", 0 
.boot_string_enter:
 db "Press enter to boot selected entry", 0 


boot:
	di
; ti os = bit reset
; kernel = bit set
; nice little boot loader
; LCD to 8 bits
	ld	hl, $D40000
	ld	($E30010), hl
	ld	a,$27
	ld	($E30018), a
; colors 0, 1
	or	a, a
	sbc	hl, hl
	ld	($E30200), hl
	dec	hl
	ld	($E30202), hl
	
	ld	hl, $E40000
	ld	de, $E30204
	ld	bc, 508
	ldir
	
	ld	ix, $000100
	
	ld	hl, 0
	ld	bc, .string_boot0
	call	_video.string
	
	ld	hl, 19*256+0
	ld	bc, .string_enter
	call	_video.string
	
	xor	a, a
.boot_choose_loop:
	push	af
	ld	b, 8
.wait:
	push	bc
	call	_video.vsync
	pop	bc
	djnz	.wait
	pop	af
	push	af
	ld	ix, $000100
	or	a, a
	jr	nz, .not_reverse
	ld	ix, $010001
.not_reverse:
	ld	hl, 1*256+3
	ld	bc, .string_boot1
	call	_video.string
	pop	af
	push	af
	ld	ix, $000100
	or	a, a
	jr	z, .not_reverse2
	ld	ix, $010001
.not_reverse2:
	ld	hl, 2*256+3
	ld	bc, .string_boot2
	call	_video.string
	ld	hl, $F50000
	ld	(hl), 2
	xor	a, a
.scan_wait:
	cp	a, (hl)
	jr	nz, .scan_wait
	pop	af
	ld	hl, $F5001E
	bit	0, (hl)
	jr	z, $+3
	cpl
	bit	3, (hl)
	jr	z, $+3
	cpl
	ld	hl, $F5001C
	bit	0, (hl)
	jr	z, .boot_choose_loop
	
	or	a, a
	jr	z, .tios_init
	ld	iy, $D00080
	set	VMM_HYPERVISOR_BIT, (iy+VMM_HYPERVISOR_OFFSET)
	jp	init
.tios_init:
; FIXME : we need to explain to the OS that he is smaller
; invisible variable taking up to $0D0000 ??
	ld	hl, $E40000
	ld	de, $D40000
	ld	bc, 76800*2
	ldir
	ld	a,$2D
	ld	($E30018), a
	jp	vmm.guest_init

.string_boot0:
 db "Choose OS to boot from :", 0
.string_boot1:
 db "TI-os version x.x.x", 0
.string_boot2:
 db "Sorcery version x.x.x", 0
 
.string_enter:
 db "Press enter to boot selected entry", 0 

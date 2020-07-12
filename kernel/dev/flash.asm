define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_RAM_CACHE		$D00000

define	KERNEL_FLASH_SIZE		$400000

flash:

.phy_mem_op:
	jp	.phy_read
	jp	.phy_write

.phy_abort:
	ld	a, $F0
	ld	($0), a

.init:
; set flash wait state
	di
	rsmix
	ld	hl, KERNEL_FLASH_CTRL
	ld	(hl), $03
	ld	l, KERNEL_FLASH_MAPPING and $FF
	ld	(hl), $06

	ld	hl, .phy_write_base
	ld	de, $D18800
	ld	bc, 256
	ldir
	
; lock it on init

; flash unlock and lock
.phy_lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret
	
.phy_unlock:
	in0	a, ($06)
	or	a, 4
	out0	($06), a
	ld	a, 4
	di 
	jr	$+2
	di
	rsmix 
	im 1
	out0	($28),a
	in0	a,($28)
	bit	2,a
	ret
 
.phy_read:
	ret

.phy_write_base:

org $D18800
	
.phy_write:
; write hl to flash for bc bytes
; + set status as uninterruptible maybe ?
	di
	rsmix
	call	.phy_unlock

; we will write hl to de address
.phy_write_loop:
	ld	a, (hl)
	push	hl
	ld	hl, $000AAA
	ld	(hl), l
	ld	hl, $000555
	ld	(hl), l
	add	hl, hl
	ld	(hl), $A0
	ld	hl, (KERNEL_INTERRUPT_STATUS_MASKED)
	ex	de, hl
	and	a, (hl)
; byte to program = A
	ld	(hl), a
; now we need to check for the write to complete
.phy_write_busy_wait:
	cp	a, (hl)
	jr	nz, .phy_write_busy_wait
.phy_write_continue:
; schedule if need for an interrupt
	ld	a, d
	or	a, e
	ex	de, hl
	pop	hl
	jr	z, .phy_write_tail
; perform interrupt
; save all ?
	call	.phy_lock
	ei
	halt
	di
; re unlock
	call	.phy_unlock
.phy_write_tail:
	inc	de
	cpi
	jp	pe, .phy_write_loop
	jp	.phy_lock

; _flash_write:
; 	push hl
; 	ld hl,$AAA
; 	ld (hl),$AA
; 	ld a,$55
; 	ld ($555),a
; 	ld (hl),$A0
; 	pop hl
; 
; 	push bc
; 	ld a,(de)
; 	and a,(hl)
; 	ld (de),a
; 	ld c,a
; .wait:
; 	ld a,(de)
; 	cp a,c
; 	jr nz,.wait
; 	pop bc
; 	inc hl
; 	inc de
; 	xor a,a
; 	dec bc
; 	ld (ScrapMem),bc
; 	ld a,(ScrapMem+2)
; 	or a,b
; 	or a,c
; 	jr nz,__flash_write
; 	ret
; 
; __sector_erase:
; 	ex hl,de
; 	ld hl,$AAA
; 	ld	c,$AA
; 	ld	(hl),c
; 	ld	a,$55
; 	ld	($555),a
; 	ld	(hl),$80
; 	ld	(hl),c
; 	ld	($555),a
; 	ex hl,de
; 	ld	(hl),$30 ; Do not change this value. You could superbrick your calculator.
; 	ld h,$FF
; 	ld l,h
; .loop:
; 	ld a,(hl)
; 	cp a,$FF
; 	jr nz,.loop
; 	ret	
	
.phy_erase_sector:
	ret
	

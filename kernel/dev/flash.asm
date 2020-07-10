define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_RAM_CACHE		$D00000

define	KERNEL_FLASH_SIZE		$400000

flash:

.phy_mem_op:
	jp	.phy_read_page
	jp	.phy_write_page
	jp	.phy_create_inode
	jp	.phy_destroy_inode
	jp	.phy_read_inode
	jp	.phy_write_inode

.init:
; set flash wait state
	di
	ld	hl, KERNEL_FLASH_CTRL
	ld	(hl), $03
	ld	l, KERNEL_FLASH_MAPPING and $FF
	ld	(hl), $06
; lock it on init

; flash unlock and lock
.phy_lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ld	a, $88
	out0	($24), a
	ret

.phy_unlock:
	ld	a, $8C
	out0	($24), a
	ld	c, 4
	in0	a, ($06)
	or	a, c
	out0	($06), a
	out0	($28), c
	ret
	
.phy_read_page:
; 24 bits key adress = hl, page index = b
	ret

.phy_write_page:
; page index = b, return 24 bits key adress
	ret

.phy_erase_sector:
	ret
	
.phy_create_inode:
	ret
	
.phy_destroy_inode:
	ret
	
.phy_write_inode:
	ret
	
.phy_read_inode:
	ret


	
.phy_write:	
; write hl to flash for bc bytes
	push	hl
	ld	hl, $0AAA
	ld	(hl), l
	ld	hl, $0555
	ld	(hl), l
	ld	hl, $0AAA
	ld	(hl), $A0
	pop	hl
	
	
	
	
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
	

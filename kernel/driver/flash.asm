define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_SIZE		$400000

flash:

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
	call	.phy_init

; flash unlock and lock
.lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret
	
.unlock:
; need to be in privileged flash actually
	in0	a, ($06)
	or	a, 4
	out0	($06), a
	ld	a, 4
	di 
	jr	$+2
	di
	rsmix 
	im 1
	out0	($28), a
	in0	a, ($28)
	bit	2, a
	ret

define KERNEL_FLASH_MAPPING           $E00003
define KERNEL_FLASH_WAITSTATE                3
define KERNEL_FLASH_CTRL              $E00005

kflashfs:
.init:
; set flash wait state
	ld	a, KERNEL_FLASH_WAITSTATE
	ld	(KERNEL_FLASH_CTRL), a
	ret

.eraseSector:
; ** to handle myself cause it is NOT nice with my RAM **
	scf
	ret
	ld	bc, $F8
	push	bc
	jp	_boot_EraseFlashSector

.unlock:
	ld	a, $8C
	out0	($24), a
	ld	c, 4
	in0	a, ($06)
	or	c
	out0	($06), a
	out0($28), c
	ret

.lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ld	a, $88
	out0	($24), a
	ret 

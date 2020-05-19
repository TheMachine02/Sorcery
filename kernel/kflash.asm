define KERNEL_FLASH_MAPPING           0xE00003
define KERNEL_FLASH_WAITSTATE                3
define KERNEL_FLASH_CTRL              0xE00005

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
	ld	bc, 0xF8
	push	bc
	jp	_boot_EraseFlashSector

.unlock:
	ld	a, 0x8C
	out0	(0x24), a
	ld	c, 4
	in0	a, (0x06)
	or	c
	out0	(0x06), a
	out0(0x28), c
	ret

.lock:
	xor	a, a
	out0	(0x28), a
	in0	a, (0x06)
	res	2, a
	out0	(0x06), a
	ld	a, 0x88
	out0	(0x24), a
	ret 

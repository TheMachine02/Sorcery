define KERNEL_FLASH_MAPPING		$1003
define KERNEL_FLASH_WAIT_STATE		3
define KERNEL_FLASH_CTRL		$1005

kflash:

.init:
; set flash wait state
	ld	a, KERNEL_FLASH_WAIT_STATE
	ld.sis	bc, KERNEL_FLASH_CTRL
	out	(bc), a
	ret
	
; flash unlock and lock
.lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ld	a, $88
	out0	($24), a
	ret 
.unlock:
	ld	a, $8C
	out0	($24), a
	ld	c, 4
	in0	a, ($06)
	or	a, c
	out0	($06), a
	out0	($28), c
	ret
	
.erase_sector:
	ret

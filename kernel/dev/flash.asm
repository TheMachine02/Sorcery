define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_WAIT_STATE		2
define	KERNEL_FLASH_RAM_CACHE		$D00000

define	KERNEL_FLASH_SIZE		$400000

kflash:

.init:
; set flash wait state
	di
	ld	hl, KERNEL_FLASH_CTRL
	ld	a, KERNEL_FLASH_WAIT_STATE
	ld	(hl), a
	ld	a, $06
	ld	l, KERNEL_FLASH_MAPPING and $FF
	ld	(hl), a
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
	
.phy_write_page:
	ret
	
.phy_read_page:
	ret
	
.phy_erase_sector:
	ret

define	KERNEL_FLASH_MAPPING		$E00003
define	KERNEL_FLASH_CTRL		$E00005
define	KERNEL_FLASH_WAIT_STATE		2
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
	ld	(hl), KERNEL_FLASH_WAIT_STATE
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

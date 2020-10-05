null:

.init:
.phy_init:
	ld	hl, .NULL_DEV
	ld	bc, KERNEL_VFS_PERMISSION_RW or KERNEL_VFS_TYPE_CHARACTER_DEVICE
	ld	de, .phy_mem_ops
	jp	_mknod

.NULL_DEV:
 db "/dev/null", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	jp	.phy_ioctl
	
.phy_read:
; offset hl to de for bc size
; return hl = bc
	sbc	hl, hl
	adc	hl, bc
	ret

.phy_write:
	or	a, a
	sbc	hl, hl
	ret
	
.phy_ioctl:
	ld	a, ENOTTY
	jp	syserror

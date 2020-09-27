null:

.init:
.phy_init:
	ld	bc, .phy_mem_ops
	ld	hl, .NULL_DEV
; inode capabilities flags
; single char dev, (so write / read / ioctl only)
	ld	a, KERNEL_VFS_TYPE_CHARACTER_DEVICE
	jp	kvfs.inode_device

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
	push	iy
	ld	hl, $FFFF00 or ENOTTY
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
	pop	iy
	ret

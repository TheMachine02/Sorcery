null:

.init:
.phy_init:
	ld	bc, .phy_mem_ops
	ld	hl, .NULL_DEV
; inode capabilities flags
; single dev block, (so write / read / seek only), seek capabilities not exposed
	ld	a, KERNEL_VFS_BLOCK_DEVICE
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
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), ENOTTY
	scf
	sbc	hl, hl
	ld	l, ENOTTY
	pop	iy
	ret

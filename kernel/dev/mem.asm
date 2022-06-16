mem:
.init:
	ld	hl, random.RAND_DEV
	ld	bc, KERNEL_VFS_PERMISSION_R or KERNEL_VFS_TYPE_CHARACTER_DEVICE
	ld	de, random.phy_mem_ops
	call	_mknod
	ld	hl, null.NULL_DEV
	ld	bc, KERNEL_VFS_PERMISSION_RW or KERNEL_VFS_TYPE_CHARACTER_DEVICE
	ld	de, null.phy_mem_ops
	call	_mknod
	ld	hl, zero.ZERO_DEV
	ld	bc, KERNEL_VFS_PERMISSION_RW or KERNEL_VFS_TYPE_CHARACTER_DEVICE
	ld	de, zero.phy_mem_ops
	jp	_mknod

null:

.NULL_DEV:
 db "/dev/null", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	jp	.phy_ioctl
; 	ret
; 	dl	0
; 	ret
; 	dl	0
; 	ret
	
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
	jp	user_error
	
zero:

.ZERO_DEV:
 db "/dev/zero", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	jp	.phy_ioctl
	ret
	dl	0
	ret
	dl	0
	ret
	
.phy_read:
; offset hl to de for bc size
; return hl = bc
	push	bc
	ld	hl, $E40000
	ldir
	pop	hl
	ret

.phy_write:
	or	a, a
	sbc	hl, hl
	ret
	
.phy_ioctl:
	ld	a, ENOTTY
	jp	user_error

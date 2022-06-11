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

.init:
.phy_init:
	ld	hl, .ZERO_DEV
	ld	bc, KERNEL_VFS_PERMISSION_RW or KERNEL_VFS_TYPE_CHARACTER_DEVICE
	ld	de, .phy_mem_ops
	jp	_mknod

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

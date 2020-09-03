null:

.init:

.phy_init:
	ld	hl, .phy_mem_ops
	ld	bc, .NULL_DEV
; inode capabilities flags
; single dev block, (so write / read / seek only), seek capabilities not exposed
	ld	a, KERNEL_VFS_BLOCK_DEVICE
	jp	kvfs.inode_create

.NULL_DEV:
 db "/dev/null", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write

.phy_read:
; offset hl to de for bc size
	ld	hl, KERNEL_MM_NULL
	ldir
	
.phy_write:
; no op
	ret
 

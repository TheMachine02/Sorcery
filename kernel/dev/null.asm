null:

.init:

.phy_init:
	ld	bc, .phy_mem_ops
	ld	hl, .NULL_DEV
; inode capabilities flags
; single dev block, (so write / read / seek only), seek capabilities not exposed
	ld	a, KERNEL_VFS_BLOCK_DEVICE
	jp	kvfs.inode_device
	ret

.NULL_DEV:
 db "/dev/null", 0

.phy_mem_ops:
	jp	.phy_read
	jp	.phy_write
	ret		; phy_sync (sync file)
	dl	$0
	ret		; phy_seek (do a seek in file)
	dl	$0
	ret		; phy_read_inode (from backing device)
	dl	$0
	ret		; phy_write_inode (from backing device)
	dl	$00
	ret		; phy_create_inode
	dl	$00
	ret		; phy_destroy_inode

.phy_read:
; offset hl to de for bc size
	ld	hl, KERNEL_MM_NULL
	ldir
	
.phy_write:
	ret
 

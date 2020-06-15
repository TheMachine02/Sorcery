define	KERNEL_RAMFS_MAX_SIZE		65536
define	KERNEL_RAMFS_HUGEPAGE		768

ramfs:

.phy_mem_op:
	jp	.phy_read_page
	jp	.phy_write_page
	jp	.phy_create_inode
	jp	.phy_destroy_inode
	jp	.phy_read_inode
	jp	.phy_write_inode

.init:
	ret
	
.phy_read_page:
; 24 bits key adress = hl, page index = b
	ret

.phy_write_page:
; page index = b, return 24 bits key adress
	ld	hl, kmm_ptlb_map
	ld	l, b
	ld	a, (hl)
	or	KERNEL_MM_PAGE_UNEVICTABLE_MASK
	and	not KERNEL_MM_PAGE_DIRTY_MASK
	ld	(hl), a
	ret
	
.phy_write_compressed_page:
	ret
	
.phy_read_compressed_page:
	push	bc
	push	hl
	call	kmm.page_lock_write
	pop	de
	ex	de, hl
; hl (source) -> de (page)
	call	lz4.decompress_raw
	pop	bc
	jp	kmm.page_unlock_write
	
.phy_create_inode:
	ret
	
.phy_destroy_inode:
; iy = inode cleaned
; cache page will be dropped and writted for dirty by the vfs.destroy_inode
	ret

.phy_read_inode:
	ret

.phy_write_inode:
	ret

vfs_cache:

.map_page:
; doesnt destroy hl, bc
; return page in a or error in a with carry set
; iy should be the inode
	push	hl
	push	bc
; cache page within kernel memory in priority
	ld	de, KERNEL_MM_PAGE_CACHE_MASK
	ld	b, KERNEL_MM_GFP_KERNEL
	call	kmm.map_page
; if carry : try to reclaim some memory pages
	pop	bc
	pop	hl
	ret

.dirty_page:
; a is page
	ld	hl, kmm_ptlb_map
	ld	l, a
	set	KERNEL_MM_PAGE_DIRTY, (hl)
	ret	
	
.drop_page:
	ret
	
.evict_page:
	ret 

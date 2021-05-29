vfs_cache:

.map_page:
; doesnt destroy hl, bc
; return page in a or error in a with carry set
; iy should be the inode
	push	hl
	push	bc
	push	de
	push	iy
; cache page within kernel memory in priority
	ld	de, KERNEL_MM_PAGE_CACHE_MASK
; for inode, we need to extract the 12 bits of information and merge it with the tlb
; (inode are 64 aligned, 2 bits in lower, 2 bits in upper, 8 bits for high)
	add	iy, iy
	add	iy, iy
	ld	e, iyh
	push	iy
	dec	sp
	pop	bc
	inc	sp
	ld	a, b
	and	a, KERNEL_MM_PAGE_USER_MASK
	or	a, d
	ld	d, a
	ld	b, KERNEL_MM_GFP_KERNEL
	call	kmm.map_page
; TODO : if carry : try to reclaim some memory pages
	pop	iy
	pop	de
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

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
	ld	d, iyh
	push	iy
	dec	sp
	pop	bc
	inc	sp
	ld	a, b
	and	a, KERNEL_MM_PAGE_USER_MASK
	or	a, e
	ld	e, a
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
; unmap all pages belonging to an inode (de should be inode flags)
; compute the id from inode number
; for inode, we need to extract the 12 bits of information and merge it with the tlb
; (inode are 64 aligned, 2 bits in lower, 2 bits in upper, 8 bits for high)
	add	iy, iy
	add	iy, iy
	ld	d, iyh
	push	iy
	dec	sp
	pop	bc
	inc	sp
	ld	a, b
	and	a, KERNEL_MM_PAGE_USER_MASK
	ld	e, a
	ld	a, d
; de is the full 2 bytes value to search
; let's go
	ld	hl, kmm_ptlb_map + KERNEL_MM_PAGE_MAX + KERNEL_MM_GFP_KERNEL
	ld	bc, KERNEL_MM_PAGE_MAX - KERNEL_MM_GFP_KERNEL
	jr	.__drop_page_parse
.__drop_page_flush:
	push	af
	dec	hl
	dec	h
; check if (hl) and KERNEL_MM_PAGE_USER_MASK is correctly equal to e
	ld	a, (hl)
	and	a, KERNEL_MM_PAGE_USER_MASK
	cp	a, e
	call	z, kmm.flush_page
	inc	h
	inc	hl
	pop	af
.__drop_page_parse:
	cpir
	jp	pe, .__drop_page_flush
	ret
	
.evict_page:
	ret 

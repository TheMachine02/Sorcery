define	KERNEL_MM_CACHE_PRESSURE		32	; if we use more than 224KiB, try to reclaim cache page to get under this limit
define	KERNEL_MM_CACHE_WRITEBACK_TIME		256	; number in jiffies where we run the writeback
define	KERNEL_MM_CACHE_WRITEBACK_SIZE		8	; writeback 8KiB max each time jiffies


.map_cache_page:
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
	call	.map_page
; if carry : try to reclaim some memory pages
; 	jr	c, .evict_cache_page
	pop	iy
	pop	de
	pop	bc
	pop	hl
	ret
	
.dirty_cache_page:
; a is page
	ld	hl, kmm_ptlb_map
	ld	l, a
	set	KERNEL_MM_PAGE_DIRTY, (hl)
	ret	
	
.drop_cache_page:
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
	jr	.__drop_cache_page_parse
.__drop_cache_page_flush:
	push	af
	dec	hl
	dec	h
; check if (hl) and KERNEL_MM_PAGE_USER_MASK is correctly equal to e
	ld	a, (hl)
	and	a, KERNEL_MM_PAGE_USER_MASK
	cp	a, e
	call	z, .flush_page
	inc	h
	inc	hl
	pop	af
.__drop_cache_page_parse:
	cpir
	jp	pe, .__drop_cache_page_flush
	ret
; 
; .evict_cache_page:
; ; reclaim some page due to memory pressure
; 	scf
; 	ret 
; 
; .reclaim_cache_page:
; ; reclaim non dirty oldest page periodically
; ; only run is there is memory pressure, to get back under memory pressure level
; 	ld	a, i
; 	push	af
; 	ld	de, klru_pages
; 	ld	hl, kmm_ptlb_map
; 	ld	l, KERNEL_MM_GFP_KERNEL
; 	ld	a, l
; 	cpl
; 	ld	b, 0
; 	ld	c, a
; 	inc.s	bc
; ; search for exactly KERNEL_MM_PAGE_CACHE_MASK
; 	ld	a, KERNEL_MM_PAGE_CACHE_MASK
; 	di
; .__reclaim_cache_parse:
; 	cpir
; 	jp	po, .__reclaim_cache_flush
; 	push	hl
; 	push	bc
; 	ld	e, klru_pages and 255
; 	ld	b, 4
; ; insert in page based of distance of pltb lru with kinterrupt_lru_page
; .reclaim_cache_list:
; 	inc	h
; 	inc	h
; 	ld	a, (kinterrupt_lru_page)
; 	sub	a, (hl)
; 	dec	h
; 	dec	h
; ; a = absolute distance
; 	ex	de, hl
; 	cp	a, (hl)
; 	ex	de, hl
; 	jr	nc, .__reclaim_cache_mark_page
; 	inc	de
; 	inc	de
; 	djnz	.reclaim_cache_list
; 	jr	.__reclaim_cache_continue
; .__reclaim_cache_mark_page:
; 	ld	(de), a
; 	inc	de
; 	ld	a, l
; 	ld	(de), a
; .__reclaim_cache_continue:
; 	pop	bc
; 	pop	hl
; 	jr	.__reclaim_cache_parse
; .__reclaim_cache_flush:
; 	pop	af
; 	ret	po
; 	ei
; 	ret
; 	
; .writeback_cache_page:
; ; writeback oldest dirty page to backing device and mark them as non dirty (don't reclaim page cache)
; ; occurs every ~256 ticks (full kinterrupt_lru_page cycle)
; 	ret

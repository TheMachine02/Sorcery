
.cache_page_map:
; iy is inode
; destroy bc, destroy hl
; interrupt should be disabled
; get kmm_ptlb_map adress
	di
	ld	hl, kmm_ptlb_map
	ld	bc, 256
	ld	a, KERNEL_MM_PAGE_FREE_MASK
; fast search for free page
	cpir
	jp	po, .cache_page_ram_full
	dec	hl
	ld	(hl), KERNEL_MM_PAGE_SHARED_MASK or KERNEL_MM_PAGE_CACHE_MASK or KERNEL_MM_PAGE_LOCK_MASK
	inc	h
	ld	(hl), 1
	ld	a, l
	or	a, a
	sbc	hl, hl
	ld	l, a
	add	hl, hl
	add	hl, hl
	ld	bc, kcache_inode_map
	add	hl, bc
	ld	(hl), iy
	ld	b, a
	ret
.cache_page_ram_full:
	scf
	sbc	hl, hl
	ret

.cache_phy_read:
	ld	ix, (iy+KERNEL_VFS_INODE_OP)
	jp	(ix)
	
.cache_phy_write:
	ld	ix, (iy+KERNEL_VFS_INODE_OP)
	lea	ix, ix+3
	jp	(ix)
	
.cache_get_page_read:
; iy = node, hl = offset
; compute hl/1024 and get actual inode entrie
	ld	a, i
	push	af
	di
	call	kvfs.inode_page_entry
; hl = entry of the node
	ld	a, (hl)
	or	a, a
; zero = no cache page mapped
	jr	nz, .cache_page_hit_read
	push	hl
	call	.cache_page_map
; TODO check for error
; b = page
	pop	hl
	ld	(hl), b
	inc	hl
	ld	hl, (hl)
	pop	af
	jp	po, $+5
	ei
	push	bc
	call	.cache_phy_read
	pop	bc
; ; hardcore lock change
; ; atomically, this is okay, since we were locked on write and operating on a own page, so nothing should have changed. I need to notify though ....
; 	ld	hl, kmm_ptlb_map
; 	ld	l, b
; 	ld	(hl), KERNEL_MM_PAGE_SHARED_MASK or KERNEL_MM_PAGE_CACHE_MASK or 1
	push	bc
	call	.page_relock
	pop	bc
	or	a, a
	sbc	hl, hl
	ld	h, b
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	ret
.cache_page_hit_read:
	ld	b, a
	call	.page_lock_read
	or	a, a
	ld	a, l
	sbc	hl, hl
	ld	h, a
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	pop	af
	ret	po
	ei
	ret

.cache_get_page_write:
; iy = node, hl = offset
; destroy all except iy, hl is RAM adress in theory
; compute hl/1024 and get actual inode entrie
	ld	a, i
	push	af
	di
	call	kvfs.inode_page_entry
; hl = entry of the node
	ld	a, (hl)
	or	a, a
; zero = no cache page mapped
	jr	nz, .cache_page_hit_write
	push	hl
	call	.cache_page_map
; TODO check for error
; b = page
	pop	hl
	ld	(hl), b
	inc	hl
	ld	hl, (hl)
	pop	af
	jp	po, $+5
	ei
	push	bc
	call	.cache_phy_write
	pop	bc
; we are locked for write, so give back the adress and pray
	or	a, a
	sbc	hl, hl
	ld	h, b
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	ret
.cache_page_hit_write:
	ld	b, a
	call	.page_lock_write
	or	a, a
	ld	a, l
	sbc	hl, hl
	ld	h, a
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MM_RAM
	add	hl, bc
	pop	af
	ret	po
	ei
	ret

.cache_set_dirty:
; b is page
	ld	hl, kmm_ptlb_map
	ld	l, b
	set	KERNEL_MM_PAGE_DIRTY, (hl)
	ret

.cache_drop_page:
	ret
	
.cache_evict_page:
	ret 

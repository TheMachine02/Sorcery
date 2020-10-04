cache:

.page_map:
; return a = page
; destroy hl
; carry if error
; interrupt should be disabled
; get kmm_ptlb_map adress
	push	hl
	tsti
	push	bc
	ld	hl, kmm_ptlb_map
	ld	bc, 256
	ld	a, KERNEL_MM_PAGE_FREE_MASK
; fast search for free page
	cpir
	jp	po, .page_ram_full
	dec	hl
	ld	(hl), KERNEL_MM_PAGE_SHARED_MASK or KERNEL_MM_PAGE_CACHE_MASK
	inc	h
	ld	(hl), 1
	pop	bc
	rsti
	ld	a, l
	pop	hl
	ret
.page_ram_full:
	rsti
	pop	hl
	ld	a, ENOMEM
	scf
	ret

.set_dirty:
; a is page
	ld	hl, kmm_ptlb_map
	ld	l, a
	set	KERNEL_MM_PAGE_DIRTY, (hl)
	ret

.drop_page:
	ret
	
.evict_page:
	ret 

; 8 bytes per cache structure
define	KERNEL_SLAB_CACHE		0
define	KERNEL_SLAB_CACHE_SIZE		8	
define	KERNEL_SLAB_CACHE_COUNT		0	; queue info
define	KERNEL_SLAB_CACHE_QUEUE		1	; queue info
define	KERNEL_SLAB_CACHE_DATA_SIZE	4	; size of block (2 bytes)
define	KERNEL_SLAB_CACHE_DATA_COUNT	6	; maximum number of block
define	KERNEL_SLAB_CACHE_DATA_PAGE	7	; number of page currently used

; per slab structure
; 7 bytes + 3 special
define	KERNEL_SLAB_PAGE_HEADER		0	; header
define	KERNEL_SLAB_PAGE_HEADER_SIZE	8	; size
define	KERNEL_SLAB_PAGE_PTLB		0	; ptlb identifier
define	KERNEL_SLAB_PAGE_NEXT		1	; queue pointer
define	KERNEL_SLAB_PAGE_PREVIOUS	4	; queue pointer
define	KERNEL_SLAB_PAGE_POINTER	8	; free pointer reside in the *next* free block
; as such :
; if we are allocating
; count = 2, return the pointer free block and decrement (should point to itself)
; count = 1, free from the queue and return the header block
; if we are freeing
; count = 0, create the header block and add slab to the structure queue
; count = 1, create the free pointer and made it point itself
; count > 1, update the free pointer
; count = max_count, free the slab entirely and remove it from queue

kmalloc	= kmem.cache_malloc
kfree	= kmem.cache_free

kmem:

.__cache_malloc_error_null:
	pop	af
	scf
	sbc	hl, hl
	ret

.cache_malloc:
; hl is size
; find highest bit set, and if lower bit are set, do + 1
	push	af
	ld	a, l
	or	a, a
	jr	z, .__cache_malloc_error_null
	ld	hl, kmem_cache_buffctl shr 3 + 5	; no 1, 2, 4 bytes caches
.__get_cache_log:
	dec	l
	add	a, a
	jr	nc, .__get_cache_log
	jr	z, .__get_cache_lowbit
	inc	l
.__get_cache_lowbit:
; can get l < 0
	ld	a, l
	add	a, a
	jr	nc, .__get_cache_default
	xor	a, a
	ld	l, a
.__get_cache_default:
	add	hl, hl
	add	hl, hl
	add	hl, hl
	pop	af
	
.cache_alloc:
	push	af
	push	de
	push	bc
	push	iy
	tsti
; allocate from cache pointed by hl
; first, check if there is some free pages to use
; just ld a, (hl) / inc a, but we also need to clear carry flag in case of nz
	xor	a, a
	or	a, (hl)
	inc	a
	call	z, .cache_grow
; return z if allocated, nz if not
	jr	c, .__cache_alloc_error
	inc	hl
	ld	iy, (hl)
; block size now
	ld	bc, 3
	add	hl, bc
	ld	c, (hl)
	inc	hl
	ld	b, (hl)
; quickly save hl, we may not be using it, but anyway
	ex	de, hl
; get the ptlb of the page and the count
	ld	hl, kmm_ptlb_map + 256
	ld	l, (iy+KERNEL_SLAB_PAGE_PTLB)
	dec	(hl)
	jr	z, .__cache_alloc_full_page
; grab the current free pointer and write the next free pointer
	ld	hl, (iy+KERNEL_SLAB_PAGE_POINTER)
	ld	de, (hl)
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), de
	ex	de, hl
.__cache_alloc_zero:
; we can restore interrupts now
	rsti
	push	de
	ld	hl, KERNEL_MM_NULL
	ldir
	pop	hl
.__cache_alloc_restore:
	pop	iy
	pop	bc
	pop	de
	pop	af
	or	a, a
	ret

.__cache_alloc_full_page:
	ex	de, hl
	ld	de, -5
	add	hl, de
	call	kqueue.remove_head
; the last one in the slab
	lea	de, iy+KERNEL_SLAB_PAGE_HEADER
	jr	.__cache_alloc_zero 

.__cache_alloc_error:
	rsti
	pop	iy
	pop	bc
	pop	de
	pop	af
	scf
	sbc	hl, hl
	ret
	
.__cache_grow_error:
	pop	ix
	pop	hl
	scf
	ret

.cache_grow:
; hl is cache structure
	di
; save the cache structure for later
	push	hl
	ex	(sp), ix
; ix = cache structure
	ld	a, (ix+KERNEL_SLAB_CACHE_DATA_PAGE)
	inc	a
	jp	m, .__cache_grow_error
	ld	(ix+KERNEL_SLAB_CACHE_DATA_PAGE), a
	ld	a, l
	rra
	rra
	rra
	and	a, KERNEL_MM_PAGE_OWNER_MASK
	or	a, KERNEL_MM_PAGE_CACHE_MASK
	ld	e, a
	ld	a, (ix+KERNEL_SLAB_CACHE_DATA_COUNT)
	ld	b, KERNEL_MM_GFP_KERNEL
	call	kmm.page_map_single
	jr	c, .__cache_grow_error
	push	hl
	ld	bc, -$D00000
	add	hl, bc
	ex	(sp), hl
	inc	sp
	pop	bc
	dec	sp
	ld	a, c
	srl	b
	rra
	srl	b
	rra
; a is tlb, hl is page, ix is our cache structure
; write KERNEL_SLAB_PAGE_PTLB
	ld	(hl), a
	ld	de, KERNEL_MM_PAGE_SIZE
	add	hl, de
	ex	de, hl
	sbc	hl, hl
	ld	bc, 0
	ld	c, (ix+KERNEL_SLAB_CACHE_DATA_SIZE)
	ld	b, (ix+KERNEL_SLAB_CACHE_DATA_SIZE+1)
	sbc	hl, bc
; hl = negated bloc size
	ex	de, hl
; hl = end, de = page pointer
	ld	b,  (ix+KERNEL_SLAB_CACHE_DATA_COUNT)
	dec	b
; hl = end of page, de offset, b size
	add	hl, de
	push	hl
	ex	(sp), iy
	push	hl
	add	hl, de
.__cache_grow_init:
	ld	(iy+0), hl
	add	iy, de
	add	hl, de
	djnz	.__cache_grow_init
; mark the KERNEL_SLAB_PAGE_POINTER with the *last* page block
	pop	hl
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), hl
	lea	hl, ix+KERNEL_SLAB_CACHE
	call	kqueue.insert_head
	pop	iy
	pop	ix
	or	a, a
	ret

.cache_free:
; hl is free data adress
	push	af
	tsti
	push	bc
	push	de
	push	hl
	ld	bc, -$D00000
	add	hl, bc
	ex	(sp), hl
	ex	de, hl
	inc	sp
	pop	hl
	dec	sp
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	ld	hl, KERNEL_MM_RAM shr 2
	ld	h, a
	add	hl, hl
	add	hl, hl
	push	hl
	ex	(sp), iy
	ld	bc, kmm_ptlb_map
	ld	c, a
	ld	a, (bc)
	and	a, KERNEL_MM_PAGE_OWNER_MASK
	ld	hl, kmem_cache_buffctl shr 3
	or	a, l
	ld	l, a
	add	hl, hl
	add	hl, hl
	add	hl, hl
	push	hl
	ex	(sp), ix
	inc	b
; de is pointer, hl is our slab, bc is ptlb
; iy is our *base* page adress
; de is pointer, hl is our slab, bc is ptlb
	ld	a, (bc)
; count = 0, create the header block and add slab to the structure queue
; count = 1, create the free pointer and made it point itself
; count > 1, update the free pointer
	inc	a
	ld	(bc), a
	dec	b
	dec	a
	jr	z, .__cache_free_link
	dec	a
	jr	z, .__cache_free_ptr
	inc	a
	inc	a
	cp	a, (ix+KERNEL_SLAB_CACHE_DATA_COUNT)
	jr	z, .__cache_shrink
; default pointer updating
; grab page base adress	(mask 1024)
; hl = our free pointer
	ex	de, hl
	ld	bc, (iy+KERNEL_SLAB_PAGE_POINTER)
	ld	(hl), bc
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), hl
.__cache_free_restore:
	pop	ix
	pop	iy
	pop	de
	pop	bc
	rsti
	pop	af
	or	a, a
	sbc	hl, hl
	ret

.__cache_free_ptr:
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), de
	jr	.__cache_free_restore

.__cache_free_link:
	lea	hl, ix+KERNEL_SLAB_CACHE
	call	kqueue.insert_head
	ld	(iy+KERNEL_SLAB_PAGE_PTLB), b
	jr	.__cache_free_restore

.__cache_shrink:
	lea	hl, ix+KERNEL_SLAB_CACHE
	call	kqueue.remove
	sbc	hl, hl
	adc	hl, bc
	call	kmm.page_flush
	jr	.__cache_free_restore

.cache_create:
	push	iy
	push	de
	push	bc
	ld	iy, kmem_cache_user
	ld	de, KERNEL_SLAB_CACHE_SIZE
; 9 users defined cache are possible
	ld	b, 9
.__find_free:
	ld	a, (iy+KERNEL_SLAB_CACHE_DATA_COUNT) 
	or	a, a
	jr	z, .__find_slot
	lea	iy, iy+KERNEL_SLAB_CACHE_SIZE
	djnz	.__find_free
	pop	bc
	pop	de
	pop	iy
	sbc	hl, hl
	scf
	ret
.__find_slot:
; hl is the block size of the cache
	ld	(iy+KERNEL_SLAB_CACHE_COUNT), $FF
	ld	(iy+KERNEL_SLAB_CACHE_DATA_SIZE), hl
	ld	(iy+KERNEL_SLAB_CACHE_DATA_PAGE), a
; TODO : KERNEL_SLAB_CACHE_DATA_COUNT= 1024 / hl rounded to down
	pop	bc
	pop	de
	pop	iy
	ret

; kmem_cache_destroy:
; ; hl is cache, just null it and free all the page allocate to it ?
; 	ret

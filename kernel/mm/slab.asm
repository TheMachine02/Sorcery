; 8 bytes per cache structure
define	KERNEL_SLAB_CACHE		0
define	KERNEL_SLAB_CACHE_SIZE		8
define	KERNEL_SLAB_CACHE_COUNT		0
define	KERNEL_SLAB_CACHE_QUEUE		1
define	KERNEL_SLAB_CACHE_MAX_COUNT	4	; 1 byte, max number of block per slab (-2)
define	KERNEL_SLAB_CACHE_MAX_SIZE	5	; 3 bytes, max size of block per slab (negated)

; bss defined location
define	kmem_cache_buffctl		$D00340
define	kmem_cache_s8			$D00340
define	kmem_cache_s16			$D00348
define	kmem_cache_s32			$D00350
define	kmem_cache_s64			$D00358
define	kmem_cache_s128			$D00360
define	kmem_cache_s256			$D00368
define	kmem_cache_user			$D00370

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

;define	KERNEL_MM_PAGE_FREE		7
;define	KERNEL_MM_PAGE_CACHE		6
define	KERNEL_MM_PAGE_OWNER_MASK	31	; owner mask in first byte of ptlb
define	KERNEL_MM_PAGE_COUNTER		0	; the counter is the second byte of ptlb

define	KERNEL_MEMORY_BLOCK_DATA	0
define	KERNEL_MEMORY_BLOCK_FREE	2
define	KERNEL_MEMORY_BLOCK_PREV	3
define	KERNEL_MEMORY_BLOCK_NEXT	6
define	KERNEL_MEMORY_BLOCK_PTR		9
define	KERNEL_MEMORY_BLOCK_SIZE	12
define	KERNEL_MEMORY_MALLOC_THRESHOLD	64


kmalloc:
	push	de
	push	bc
	push	ix
	push	iy
	ld	b, a
	push	bc
	call	kmalloc_a
	pop	bc
	ld	a, b
	pop	iy
	pop	ix
	pop	bc
	pop	de
	ret

kfree:
	push	de
	push	bc
	push	ix
	push	iy
	ld	b, a
	push	bc
	call	kfree_a
	pop	bc
	ld	a, b
	pop	iy
	pop	ix
	pop	bc
	pop	de
	ret
	
kmalloc_a:
.get_cache:
; hl is size
; find highest bit set, and if lower bit are set, do + 1
	ld	a, l
	or	a, a
	ret	z
	ld	hl, kmem_cache_buffctl shr 3 + 5	; no 1, 2, 4 bytes caches
.get_cache_log:
	dec	l
	add	a, a
	jr	nc, .get_cache_log
	jr	z, .get_cache_lowbit
	inc	l
.get_cache_lowbit:
; can get l < 0
	ld	a, l
	add	a, a
	jr	nc, .get_cache_default
	xor	a, a
	ld	l, a
.get_cache_default:	
	add	hl, hl
	add	hl, hl
	add	hl, hl

kmem_cache_alloc:
	tsti
; alloc from cache (hl)
	or	a, a
	ld	a, (hl)
	inc	a
	call	z, kmem_cache_grow
	jr	c, .cache_exit
	inc	hl
	push	iy
	push	de
; grab first usable slab
	ld	iy, (hl)
	ex	de, hl
; get the ptlb of the page
	ld	hl, kmm_ptlb_map + 256
	ld	l, (iy+KERNEL_SLAB_PAGE_PTLB)
; get the counter
	dec	(hl)
	jr	z, .cache_full_page
; grab the free pointer
	ld	hl, (iy+KERNEL_SLAB_PAGE_POINTER)
; get the *next* free pointer
	ld	de, (hl)
; and write it
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), de
; note that if now count = 1, those last two operation are useless, and could be skipped (but we'll lose cycles in the main case). No side effects anyway
.cache_zero_data:
; clean up the data (hl) for data_size
; TODO
	pop	de
	pop	iy
.cache_exit:
	rstiRET
.cache_full_page:
	ex	de, hl
	dec	hl
	call	kqueue.remove_head
; the last one in the slab
	lea	hl, iy+KERNEL_SLAB_PAGE_HEADER
	jr	.cache_zero_data

kmem_cache_grow:
	di
; allocate a page, prepare it
	ld	a, l
	rra
	rra
	rra
	and	a, KERNEL_MM_PAGE_OWNER_MASK
	or	a, KERNEL_MM_PAGE_CACHE_MASK
	ld	e, a
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	ld	a, (hl)
	add	a, 2
	push	hl
	ld	b, 0
	call	kmm.page_map_single
	push	hl
	pop	iy
	pop	hl
	ret	c
	push	iy
	ld	bc, -$D00000
	add	iy, bc
	ex	(sp), iy
	inc	sp
	pop	bc
	dec	sp
	ld	a, c
	srl	b
	rra
	srl	b
	rra
; a is tlb
; iy is page, hl is still slab
; de is -block size
; b is count of block
	push	iy
	ld	de, 1024
	add	iy, de
	ld	b, (hl)
	inc	hl
	ld	de, (hl)
	add	iy, de
	push	iy
; iy is first block, point to block - 1
.cache_grow_init:
	lea	ix, iy+0
	add	ix, de
	ld	(iy+0), ix
	lea	iy, ix+0
	djnz	.cache_grow_init
; last pointer, point to last data block
	ld	(iy+0), iy
	pop	ix
	pop	iy
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), ix
	ld	(iy+KERNEL_SLAB_PAGE_PTLB), a
	ld	bc, -5
	add	hl, bc
	call	kqueue.insert_head
	or	a, a
	ret

kfree_a:
kmem_cache_free:
; hl is free data adress
	tsti
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
	ld	bc, kmm_ptlb_map
	ld	c, a
	ld	iy, KERNEL_MM_RAM shr 2
	ld	iyh, a
	add	iy, iy
	add	iy, iy
	ex	de, hl
; iy is our *base* page adress
	ld	a, (bc)
	and	a, KERNEL_MM_PAGE_OWNER_MASK
	ld	hl, kmem_cache_buffctl shr 3
	or	a, l
	ld	l, a
	add	hl, hl
	inc	hl	; +4, KERNEL_SLAB_CACHE_MAX_COUNT
	add	hl, hl
	add	hl, hl
; de is pointer, hl is our slab, bc is ptlb
	inc	b
; get counter
	ld	a, (bc)
; count = 0, create the header block and add slab to the structure queue
; count = 1, create the free pointer and made it point itself
; count > 1, update the free pointer
	inc	a
	ld	(bc), a
	dec	a
	jr	z, .cache_free_link
	dec	a
	jr	z, .cache_free_ptr
	cp	a, (hl)	; max - 2
	dec	hl
	dec	hl
	dec	hl
	dec	hl
	jr	z, kmem_cache_shrink
; default pointer updating
; grab page base adress	(mask 1024)
; hl = our free pointer
	ex	de, hl
	ld	de, (iy+KERNEL_SLAB_PAGE_POINTER)
	ld	(hl), de
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), hl
	rstiRET
.cache_free_ptr:
	ld	(iy+KERNEL_SLAB_PAGE_POINTER), de
	rstiRET

.cache_free_link:
	dec	b
	ld	(iy+KERNEL_SLAB_PAGE_PTLB), b
	call	kqueue.insert_head
	rstiRET

kmem_cache_shrink:
	call	kqueue.remove
	dec	b
	push	bc
	pop	hl
	call	kmm.page_flush
	rstiRET

kmem_cache_create:
	push	iy
	push	de
	push	bc
	ld	iy, kmem_cache_user
	ld	de, KERNEL_SLAB_CACHE_SIZE
; 10 users defined cache are possible
	ld	b, 10
.find_free:
	ld	hl, (iy)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .find_slot
	lea	iy, iy+KERNEL_SLAB_CACHE_SIZE
	djnz	.find_free
	or	a, a
	sbc	hl, hl
	pop	bc
	pop	de
	pop	iy
	ret
.find_slot:
; hl is the block size of the cache
	lea	hl, iy+KERNEL_SLAB_CACHE_COUNT 		; = "lea hl, iy+KERNEL_SLAB_CACHE"
	ld	(hl), $FF
; 1024 / hl -2 = KERNEL_SLAB_CACHE_MAX_COUNT
; -hl = KERNEL_SLAB_CACHE_MAX_SIZE
	ld	(iy+KERNEL_SLAB_CACHE_MAX_SIZE), -64
	ld	(iy+KERNEL_SLAB_CACHE_MAX_COUNT), 14
	pop	bc
	pop	de
	pop	iy
	ret

kmem_cache_destroy:
; hl is cache, just null it and free all the page allocate to it ?
; assert(no_page_left)=true
	ret

define	KERNEL_SLAB_SIZE		0
define	KERNEL_SLAB_FREE		1
define	KERNEL_SLAB_PREVIOUS		2
define	KERNEL_SLAB_NEXT		5
define	KERNEL_SLAB_ENTRY_SIZE		8

define	KERNEL_SLAB_CTL			0
define	KERNEL_SLAB_SIZE		0	; 1 bytes, size of the slab block
define	KERNEL_SLAB_STACK		1	; 2 bytes, use sps
define	KERNEL_SLAB_NEXT		3	; 3 bytes, next slab page


kslab:

.init:
	ret
 
.malloc:
	ret

.free:
	ret

define	KERNEL_MEMORY_BLOCK_DATA	0
define	KERNEL_MEMORY_BLOCK_FREE	2
define	KERNEL_MEMORY_BLOCK_PREV	3
define	KERNEL_MEMORY_BLOCK_NEXT	6
define	KERNEL_MEMORY_BLOCK_PTR		9
define	KERNEL_MEMORY_BLOCK_SIZE	12
define	KERNEL_MEMORY_MALLOC_THRESHOLD	64

kmalloc:
; Memory allocation routine
; REGSAFE and ERRNO compliant
; void* malloc(size_t size)
; register HL is size
; return NULL if failed and errno set or void* otherwise
; also set carry if failed
	push	af
	push	de
	ex	de, hl
	push	ix
	push	bc
	ld	ix, (kthread_current)
	ld	ix, (ix+KERNEL_THREAD_HEAP)
; reset carry flag for loop sbc
	or	a, a
.malloc_loop:
	bit	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	jr	z, .malloc_test_block
.malloc_next_block:
	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
	or	a, a
	jr	z, .malloc_errno
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	jr	.malloc_loop
; so, we didn't find any memory block large enough for us
; let's try to map more memory to the thread
; first, get size+BLOCK_HEADER / block size 
; ix is the last block, it's important !
; .malloc_break:
; 	ld	hl, KERNEL_MEMORY_BLOCK_SIZE
; 	add	hl, de
; 	dec	sp
; 	push	hl
; 	ld	a, l
; 	inc	sp
; 	ex	(sp), hl
; ; we need to round UP here	
; 	or	a, a
; 	jr	z, $+3
; 	inc	hl
; 	srl	h
; 	rr	l
; 	jr	nc, $+3
; 	inc	hl
; 	srl	h
; 	rr	l
; 	jr	nc, $+3
; 	inc	hl
; 	ld	b, l
; 	pop	hl
; 	ld	hl, KERNEL_MMU_RAM
; 	call	kmmu.map_block
; ; block a certain number of block
; ; return hl as the adress
; ; de is still size
; 	jp	c, .malloc_errno
; 	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), hl
; ; there is a *new block*
; ; create the block, point it to ix, and then jump to test block
; 	push	hl
; ; b * KERNEL_MMU_PAGE_SIZE/256 > bc
; 	or	a, a
; 	sbc	hl, hl
; 	ld	h, b
; 	add	hl, hl
; 	add	hl, hl
; 	ld	bc, -KERNEL_MEMORY_BLOCK_SIZE
; 	add	hl, bc
; ; this is the size of the block
; 	lea	bc, ix+0
; 	pop	ix
; 	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), hl
; 	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), bc
; 	ld	hl, NULL
; 	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), hl
; 	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
; 	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
.malloc_test_block:
	ld	hl, (ix+KERNEL_MEMORY_BLOCK_DATA)
	sbc	hl, de
	jr	c, .malloc_next_block    
.malloc_mark_block:
; thresold to slipt the block. If the size left is >= 64 bytes, then slipt
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD
	sbc	hl, bc
	jr	nc, .malloc_split_block
; no split, so just return current block \o/ mark it used
	set	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
	pop	bc
	pop	ix
	pop	de
	pop	af
	or	a, a
	ret
.malloc_split_block:
	push	iy
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD - KERNEL_MEMORY_BLOCK_SIZE
	add	hl, bc
	lea	iy, ix+KERNEL_MEMORY_BLOCK_SIZE
	add	iy, de	; this is the new block adress
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), de
	set	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	ld	(iy+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	hl, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), iy
	ld	(iy+KERNEL_MEMORY_BLOCK_PREV), ix
	ld	(iy+KERNEL_MEMORY_BLOCK_NEXT), hl
	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
	lea	bc, iy+KERNEL_MEMORY_BLOCK_SIZE
	ld	(iy+KERNEL_MEMORY_BLOCK_PTR), bc
	pop	iy
	pop	bc
	pop	ix
	pop	de
	pop	af
	or	a, a
	ret
.malloc_errno:
	ld	ix, (kthread_current)
	ld	(ix+KERNEL_THREAD_ERRNO), ENOMEM
	pop	bc
	pop	ix
	pop	de
	pop	af
	scf
	sbc	hl, hl
	ret

; krealloc:
; ; Memory realloc routine
; ; REGSAFE and ERRNO compliant
; ; void* realloc(void* ptr, size_t newsize)
; ; if ptr is NULL, return silently
; 	push	ix
; 	push	de
; 	push	hl
; 	pop	ix
; ; try to mask the adress, ie >= D00000
; 	ex	de, hl
; 	ld	hl, $300000
; 	add	hl, de
; 	jr	nc, .realloc_error
; ; check if adress is valid
; 	ld	hl, (ix-3)
; 	or	a, a
; 	sbc	hl, de
; 	jr	nz, .realloc_error
; ; invalid adress, return quietly
; ; TODO try to merge with the next block, if free, to avoid copy
; ; TODO if resize to smaller size, shrink the current block instead allocating new one
; ; read the next block size and if it is free
; ; else, malloc and copy and free
; ; 	lea	ix, ix-KERNEL_MEMORY_BLOCK_SIZE
; ; 	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
; ; 	or	a, a
; ; 	jr	z, .realloc_malloc_cpy
; ; 	ld	iy, (iy+KERNEL_MEMORY_BLOCK_NEXT)
; ; 	bit	7, (iy+KERNEL_MEMORY_BLOCK_FREE)
; ; 	jr	nz, .realloc_malloc_cpy
; ; is size enough ?
; ; 	ld	hl, (ix+KERNEL_MEMORY_BLOCK_DATA)
; ; 	ld	de, (iy+KERNEL_MEMORY_BLOCK_DATA)
; ; 	add	hl, de
; ; clean out the *used* mask
; ; 	ld	de, $800000
; ; 	add	hl, de
; ; 	or	a, a
; ; 	sbc	hl, bc	; if nc, we are good ! merge ix and iy, return ix+12
; ; 	jr	c, .realloc_malloc_cpy
; .realloc_malloc_cpy:
; 	or	a, a
; 	sbc	hl, hl
; 	adc	hl, bc
; 	jr	z, .realloc_free
; 	call	kmalloc
; 	jr	c, .realloc_error
; 	push	hl
; 	ex	de, hl
; 	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
; ; copy for the new size only
; 	ldir
; 	pop	de
; .realloc_free:
; 	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
; 	call	kfree
; 	ex	de, hl
; 	pop	de
; 	pop	ix
; 	or	a, a
; 	ret
; .realloc_error:
; ; set hl = NULL, ERRNO set appropriately
; 	or	a, a
; 	sbc	hl, hl
; 	pop	de
; 	pop	ix
; 	scf
; 	ret
	
kfree:
; Memory free routine
; REGSAFE and ERRNO compliant
; void free(void* ptr)
; if ptr is NULL, return silently
; behaviour is undetermined if ptr wasn't malloc'ed before
	push	af
	push	ix
	push	iy
	push	de
	push	hl
; try to mask the adress, ie >= D00000
	ex	de, hl
	ld	hl, $300000
	add	hl, de
	jr	nc, .free_exit
; check if adress is valid
	push	de
	pop	ix
	ld	hl, (ix-3)
	xor	a, a
	sbc	hl, de
	jr	nz, .free_exit	; invalid adress, return quietly
; else, free the block and try to merge with prev & next
	lea	ix, ix-KERNEL_MEMORY_BLOCK_SIZE
	res	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	ld	iy, (ix+KERNEL_MEMORY_BLOCK_PREV)
	or	a, (ix+KERNEL_MEMORY_BLOCK_PREV+2)
	jr	z, .free_merge_pblock
	bit	7, (iy+KERNEL_MEMORY_BLOCK_FREE)
	jr	nz, .free_merge_pblock	
	ld	hl, (iy+KERNEL_MEMORY_BLOCK_DATA)
	ld	de, (ix+KERNEL_MEMORY_BLOCK_DATA)
	add	hl, de
	ld	de, KERNEL_MEMORY_BLOCK_SIZE
	add	hl, de
	ld	(iy+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(iy+KERNEL_MEMORY_BLOCK_NEXT), ix
; changed the prev of the next block
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), iy
	lea	ix, iy+0
.free_merge_pblock:
	ld	iy, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	ld	a, (ix+KERNEL_MEMORY_BLOCK_NEXT+2)
	or	a, a
	jr	z, .free_exit
	bit	7, (iy+KERNEL_MEMORY_BLOCK_FREE)
	jr	nz, .free_exit
	ld	hl, (iy+KERNEL_MEMORY_BLOCK_DATA)
	ld	de, (ix+KERNEL_MEMORY_BLOCK_DATA)
	add	hl, de
	ld	de, KERNEL_MEMORY_BLOCK_SIZE
	add	hl, de
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	iy, (iy+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), iy
; changed the prev of the next block
	ld	(iy+KERNEL_MEMORY_BLOCK_PREV), ix
.free_exit:
	pop	hl
	pop	de
	pop	iy
	pop	ix
	pop	af
	ret

define	KERNEL_MMU_USED_BIT                7
define	KERNEL_MMU_USED_MASK             128
define	KERNEL_MMU_PAGE_SIZE            1024
define	KERNEL_MMU_MAP              0xD00F00
define	KERNEL_MMU_RAM              0xD00000
define	KERNEL_MMU_RAM_SIZE         0x040000

define	RESERVED 0xFF

define	KERNEL_MEMORY_BLOCK_DATA         0
define	KERNEL_MEMORY_BLOCK_FREE         2
define	KERNEL_MEMORY_BLOCK_PREV         3
define	KERNEL_MEMORY_BLOCK_NEXT         6
define	KERNEL_MEMORY_BLOCK_PTR          9
define	KERNEL_MEMORY_BLOCK_SIZE        12
define	KERNEL_MEMORY_MALLOC_THRESHOLD  64 

assert (KERNEL_MMU_RAM_SIZE / KERNEL_MMU_PAGE_SIZE) < 257
assert KERNEL_MMU_PAGE_SIZE/256 = 4

kmmu:
.init:
; setup memory protection
; 0xD00000 to 0xD00FFF
	tstdi
	ld	a, 0x00
	out0	(0x20), a
	ld	a, 0x00
	out0	(0x21), a
	ld	a, 0xD0
	out0	(0x22), a
	ld	a, 0xFF
	out0	(0x23), a
	ld	a, 0x0F
	out0	(0x24), a
	ld	a, 0xD0
	out0	(0x25), a
; setup previleged executable code
	ld	a, 0x03
	out0	(0x1F), a
	ld	a, 0x00
	out0	(0x1D), a
	out0	(0x1E), a
	ld	hl, KERNEL_MMU_RAM + 256
	ld	de, KERNEL_MMU_RAM + 1 + 256
	ld	(hl), 0
	ld	bc, KERNEL_MMU_RAM_SIZE - 256
	ldir
	ld	hl, .MEMORY_PAGE
	ld	de, KERNEL_MMU_MAP
	ld	bc, 256
	ldir
	retei

.map_page:
	push	bc
	ld	bc, (kthread_current)
	ld	a, (bc)
	jr	.map_page_jump

.map_page_thread:
; void* :: hint adress for block mapping, a = thread_id
; map a single RAM page to current thread
; [register SAFE]
	push	bc
.map_page_jump:
	ld	c, a
	dec	sp
	push	hl    ; this version is interrupt safe, as we always have two bytes pushed on the stack
	inc	sp
	ex	(sp), hl
	ld	a, h
	sub	a, KERNEL_MMU_RAM shr 16
	ld	h, a
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	pop	hl
	ld	hl, KERNEL_MMU_MAP
	ld	l, a
	cpl
	add	a, (KERNEL_MMU_RAM_SIZE / KERNEL_MMU_PAGE_SIZE) mod 256 + 1
	ld	b, a
; !! critical code section !!
	tstdi
	ld	a, c
.map_page_loop:
	bit	KERNEL_MMU_USED_BIT,(hl)
	jr	z, .map_page_mark
	inc	hl
	djnz	.map_page_loop
	tstei
	ld	a, c
	pop	bc
;    ld  hl, NULL
	or	a, a
	sbc	hl, hl
	scf
	ret
.map_page_mark:
	or	a, KERNEL_MMU_USED_MASK
	ld	(hl), a
	tstei
	ld	a, l
	or	a, a
	sbc	hl, hl
	ld	h, a
	add	hl, hl
	add	hl, hl
	ld	a, c
	ld	bc, KERNEL_MMU_RAM
	add	hl, bc
	pop	bc
	xor	a, KERNEL_MMU_USED_MASK
	ret

.map_block:
	push	bc
	ld	bc, (kthread_current)
	ld	a, (bc)
	pop	bc

; try map b memory block (each are 2048)
.map_block_thread:
; void*, thread_id, block_count
; REGSAFE
; hl , a , b
	push	bc
	dec	b
	jr	z, .map_page_jump
	inc	b
	ld	c, b
	push	de
	ld	e, a
	dec	sp
	push	hl
	inc	sp
	ex	(sp), hl
	ld	a, h
	sub	a, KERNEL_MMU_RAM shr 16
	ld	h, a
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	pop	hl
	ld	hl, KERNEL_MMU_MAP
	ld	l, a
	cpl
	add	a, (KERNEL_MMU_RAM_SIZE / KERNEL_MMU_PAGE_SIZE) mod 256 + 1
	ld	b, a
; critical code section ;
	tstdi
	ld	a, e
; for b count, c is block count, a is thread id
	ld	e, c
	inc	e
	ld	d, l
.map_block_loop:
	bit	KERNEL_MMU_USED_BIT,(hl)
	jr	z, .map_block_advance
	ld	c, e
	inc	d
.map_block_advance:
	dec	c
	jr	z, .map_block_mark
	inc	hl
	djnz	.map_block_loop
	ld	b, a
	tstei
	ld	a, b
	pop	de
	pop	bc
	or	a, a
	sbc	hl, hl
	scf
	ret
; found my blocks, mark them as used
.map_block_mark:
	ld	l, d
	ld	b, e
	dec	b	; we need to reduce this by one !
	or	a, KERNEL_MMU_USED_MASK
.map_block_mark_loop:
	ld	(hl), a
	inc	hl
	djnz	.map_block_mark_loop
; generate the adress
	ld	b, a
	tstei
	ld	a, b
	xor	a, KERNEL_MMU_USED_MASK
	sbc	hl, hl
	ld	h, d
	add	hl, hl
	add	hl, hl
	ld	bc, KERNEL_MMU_RAM
	add	hl, bc
	pop	de
	pop	bc
	ret

.unmap_page:
; REGSAFE, return a = thread id
	push	hl
	push	bc
	ld	bc, (kthread_current)
	ld	a, (bc)
	jr	.unmap_page_jump
    
.unmap_page_thread:
; void* (hl) : any adress within an aligned page
; unmap the memory page
; REGSAFE, return a = thread id
	push	hl
	push	bc
.unmap_page_jump:
	or	a, KERNEL_MMU_USED_MASK
	ld	c, a
	dec	sp
	push	hl
	inc	sp
	ex	(sp), hl
	ld	a, h
	sub	a, KERNEL_MMU_RAM shr 16
	ld	h, a
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	pop	hl
	ld	hl, KERNEL_MMU_MAP
	ld	l, a
	ld	a, c
	cp	a, (hl)
	jr	nz, .unmap_skip
; need to zero out all the page
	call	.zero_page
	ld	(hl), 0
.unmap_skip:
	xor	a, KERNEL_MMU_USED_MASK
	pop	bc
	pop	hl
	ret

.unmap_block:
	push	hl
	push	bc
	ld	hl, (kthread_current)
	ld	a, (hl)
	jr	.unmap_block_jump
    
.unmap_block_thread:
; unmap all block of the current thread
; marking block as free doesn't require atomic, since we check if we own them.
; if we schedule out, we will continue to free anyway when we'll be here again
; mark free ONLY after clearing it, to avoid data left out
; REGSAFE, return a = current thread
	push	hl
	push	bc
.unmap_block_jump:
	or	a, KERNEL_MMU_USED_MASK
	ld	b, (KERNEL_MMU_RAM_SIZE / KERNEL_MMU_PAGE_SIZE) mod 256
	ld	hl, KERNEL_MMU_MAP
.unmap_block_loop:
	cp	a, (hl)
	jr	nz, .unmap_block_skip
	call	.zero_page
	ld	(hl), 0
.unmap_block_skip:
	inc	hl
	djnz	.unmap_block_loop
	xor	a, KERNEL_MMU_USED_MASK
	pop	bc
	pop	hl
	ret
    
.zero_page:
; hl is MAP adress
; REGSAFE
	push	bc
	push	hl
	ld	e, l
	or	a, a
	sbc	hl, hl
	ld	h, e
	add	hl, hl
	add	hl, hl
	ld	de, KERNEL_MMU_RAM
	add	hl, de
	ex	de, hl
	ld	hl, 0xE40000
	ld	bc, KERNEL_MMU_PAGE_SIZE
	ldir
	pop	hl
	pop	bc
	ret

if CONFIG_USE_BOOT_PATCH
.MEMORY_PAGE:
 db 4 dup RESERVED
 db 252 dup 0x00
else
.MEMORY_PAGE:
 db 4  dup RESERVED
 db 88 dup 0x00
 db RESERVED ; 0xD17000 > stupid interrupt check (one day, with some boot patch ..)
 db 163 dup 0x00
end if

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
	jr	z, .malloc_break
	ld	ix, (ix+KERNEL_MEMORY_BLOCK_NEXT)
	jr	.malloc_loop
; so, we didn't find any memory block large enough for us
; let's try to map more memory to the thread
; first, get size+BLOCK_HEADER / block size 
; ix is the last block, it's important !
.malloc_break:
	ld	hl, KERNEL_MEMORY_BLOCK_SIZE
	add	hl, de
	dec	sp
	push	hl
	ld	a, l
	inc	sp
	ex	(sp), hl
; we need to round UP here	
	or	a, a
	jr	z, $+3
	inc	hl
	srl	h
	rr	l
	jr	nc, $+3
	inc	hl
	srl	h
	rr	l
	jr	nc, $+3
	inc	hl
	ld	b, l
	pop	hl
	ld	hl, KERNEL_MMU_RAM
	call	kmmu.map_block
; block a certain number of block
; return hl as the adress
; de is still size
	jp	c, .malloc_errno
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), hl
; there is a *new block*
; create the block, point it to ix, and then jump to test block
	push	hl
; b * KERNEL_MMU_PAGE_SIZE/256 > bc
	or	a, a
	sbc	hl, hl
	ld	h, b
	add	hl, hl
	add	hl, hl
	ld	bc, -KERNEL_MEMORY_BLOCK_SIZE
	add	hl, bc
; this is the size of the block
	lea	bc, ix+0
	pop	ix
	ld	(ix+KERNEL_MEMORY_BLOCK_DATA), hl
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), bc
	ld	hl, NULL
	ld	(ix+KERNEL_MEMORY_BLOCK_NEXT), hl
	lea	hl, ix+KERNEL_MEMORY_BLOCK_SIZE
	ld	(ix+KERNEL_MEMORY_BLOCK_PTR), hl
.malloc_test_block:
	ld	hl, (ix+KERNEL_MEMORY_BLOCK_DATA)
	sbc	hl, de
	jr	c, .malloc_next_block    
.malloc_mark_block:
; thresold to slipt the block. If the size left is >= 64 bytes, then slipt
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD
	or	a, a
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
	ld	ix, (iy+KERNEL_MEMORY_BLOCK_NEXT)
	ld	(ix+KERNEL_MEMORY_BLOCK_PREV), iy
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
; 	ld	hl, 0x300000
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
; ; 	ld	de, 0x800000
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
	ld	hl, 0x300000
	add	hl, de
	jr	nc, .free_exit
; check if adress is valid
	ld	hl, (ix-3)
	or	a, a
	sbc	hl, de
	jr	nz, .free_exit	; invalid adress, return quietly
; else, free the block and try to merge with prev & next
	push	de
	pop	ix
	lea	ix, ix-KERNEL_MEMORY_BLOCK_SIZE
	res	7, (ix+KERNEL_MEMORY_BLOCK_FREE)
	ld	iy, (ix+KERNEL_MEMORY_BLOCK_PREV)
	ld	a, (ix+KERNEL_MEMORY_BLOCK_PREV+2)
	or	a, a
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

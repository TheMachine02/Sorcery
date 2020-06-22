define	KERNEL_SLAB_SIZE		0
define	KERNEL_SLAB_FREE		1
define	KERNEL_SLAB_PREVIOUS		2
define	KERNEL_SLAB_NEXT		5
define	KERNEL_SLAB_ENTRY_SIZE		8

define	kslab_heap	$D00040

; kernel slab allocator ;

kslab:

.init:
; map a kernel page please
	ld	bc, 1
	xor	a, a	; owner is kernel
	call	kmm.thread_map
	ld	(kslab_heap), hl
	push	hl
	pop	iy
	ld	hl, KERNEL_MM_PAGE_SIZE
	ld	(iy+KERNEL_SLAB_SIZE), hl
	ld	h, l
	ld	(iy+KERNEL_SLAB_NEXT), hl
	ld	(iy+KERNEL_SLAB_PREVIOUS), hl
	ret
 
.malloc:
	ex	de, hl
	ld	iy, (kslab_heap)
	or	a, a
.malloc_loop:
	bit	7, (iy+KERNEL_SLAB_FREE)
	jr	z, .malloc_test_block
.malloc_next_block:
	ld	a, (iy+KERNEL_SLAB_NEXT+2)
	or	a, a
	jr	z, .malloc_break
	ld	iy, (iy+KERNEL_SLAB_NEXT)
	jr	.malloc_loop
; so, we didn't find any memory block large enough for us
; let's try to map more memory to the thread
; ix is the last block, it's important !
.malloc_break:
	push	de
	ld	bc, 1
	call	kmm.thread_map
	pop	de
; return hl as the adress
; de is still size
	jp	c, .malloc_errno
	ld	(iy+KERNEL_SLAB_NEXT), hl
; there is a *new block*
; create the block, point it to ix, and then jump to test block
	push	hl
	ld	hl, KERNEL_MM_PAGE_SIZE-KERNEL_SLAB_ENTRY_SIZE
; this is the size of the block
	lea	bc, iy+0
	pop	iy
	ld	(iy+KERNEL_SLAB_SIZE), hl	; write 16 bits in fact
	ld	(iy+KERNEL_SLAB_PREVIOUS), bc
	ld	hl, NULL
	ld	(iy+KERNEL_SLAB_NEXT), hl
.malloc_test_block:
	ld	hl, (iy+KERNEL_SLAB_SIZE)
	sbc.s	hl, de
	jr	c, .malloc_next_block    
.malloc_mark_block:
; thresold to slipt the block. If the size left is >= 64 bytes, then slipt
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD
	sbc	hl, bc
	jr	nc, .malloc_split_block
; no split, so just return current block \o/ mark it used
	set	7, (iy+KERNEL_SLAB_FREE)
	lea	hl, iy+KERNEL_SLAB_ENTRY_SIZE
	or	a, a
	ret
.malloc_split_block:
	push	ix
	ld	bc, KERNEL_MEMORY_MALLOC_THRESHOLD - KERNEL_SLAB_ENTRY_SIZE
	add	hl, bc
	lea	ix, iy+KERNEL_SLAB_ENTRY_SIZE
	add	ix, de	; this is the new block adress
	ld	(iy+KERNEL_SLAB_SIZE), e
	set	7, d
	ld	(iy+KERNEL_SLAB_SIZE+1), d
; will be overwrited in the next write
	ld	(ix+KERNEL_SLAB_SIZE), hl
	ld	hl, (iy+KERNEL_SLAB_NEXT)
	ld	(iy+KERNEL_SLAB_NEXT), ix
	ld	(ix+KERNEL_SLAB_PREVIOUS), iy
	ld	(ix+KERNEL_SLAB_NEXT), hl
	lea	hl, iy+KERNEL_SLAB_ENTRY_SIZE
	pop	ix
	or	a, a
	ret
.malloc_errno:
	scf
	sbc	hl, hl
	ret

.free:
; free > simply mark slab as free, don't merge
	ld	bc, -KERNEL_SLAB_ENTRY_SIZE + 1
	add	hl, bc
	res	7, (hl)
	ret

; virtual mmu context for anonymous page of thread
define	KERNEL_VMMU_PERMISSION_R	1 shl 0
define	KERNEL_VMMU_PERMISSION_W	1 shl 1
define	KERNEL_VMMU_PERMISSION_X	1 shl 2

vmmu:

.map_page:
	ld	de, 256
	call	mm.map_page
; a is ptlb, hl physical adress
	ret	c
; set bit a within the thread context
	lea	de, iy+KERNEL_THREAD_VMMU_CONTEXT
	sub	a, 32
	ld	c, a
	rra
	rra
	rra
	and	a, 31
	add	a, e
	ld	e, a
; byte e is set to context byte
; get the mask now
	ld	a, c
	and	a, 7
	ld	b, a
	inc	b
	xor	a, a
	scf
.__map_page_context_mask:
	rla
	djnz	.__map_page_context_mask
	ex	de, hl
	or	a, (hl)
	ld	(hl), a
	ex	de, hl
	or	a, a
	ret

.map_pages:
	ld	de, 256
	push	bc
	call	mm.map_pages
	pop	bc
; a is ptlb, hl physical adress
	ret	c
.__raw_or_context:
	lea	de, iy+KERNEL_THREAD_VMMU_CONTEXT
	sub	a, 32
	ld	b, a
	rra
	rra
	rra
	and	a, 31
	add	a, e
	ld	e, a
; byte e is set to context byte
; get the mask now
	ld	a, b
	and	a, 7
	ld	b, a
	inc	b
	xor	a, a
	scf
.__map_pages_context_mask:
	rla
	djnz	.__map_pages_context_mask
; byte is de, first mask is a, count is c
	ld	b, c
	ld	c, a
	ex	de, hl
.__map_pages_context_bit:
	ld	a, c
	or	a, (hl)
	ld	(hl), a
	ld	a, c
	rlca
	ld	c, a
	jr	nc, $+3
	inc	hl
	djnz	.__map_pages_context_bit
	ex	de, hl
	or	a, a
	ret
	
.add_context:
; from adress hl, size de, add page to the current context
	ld	a, i
	push	af
	di
	push	de
	push	hl
	call	mm.physical_to_ptlb
	ld	hl, kmm_ptlb_map + KERNEL_MM_PAGE_MAX
	ld	l, a
	ex	de, hl
	call	mm.physical_to_ptlb
	ex	de, hl
	inc	a
	ld	b, a
	ld	c, a
	ld	a, l
.__add_context_reference:
	inc	(hl)
	inc	l
	djnz	.__add_context_reference
; we have c = count, a = pltb
	call	.__raw_or_context
	pop	hl
	pop	de
	pop	af
	ret	po
	ei
	ret

.dup_context:
; duplicate the context
; copy the vmmu of the tls
; increase reference count of the mapped pages
; iy is thread
	ld	a, i
	push	af
	di
	ld	hl, kmm_ptlb_map + KERNEL_MM_GFP_KERNEL + KERNEL_MM_PAGE_MAX
	ld	b, 28
	lea	de, iy+KERNEL_THREAD_VMMU_CONTEXT
.__dup_context_reference:
	ld	a, (de)
	inc	de
	or	a, a
	jr	z, .__dup_context_null
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	rra
	jr	nc, $+3
	inc	(hl)
	inc	l
	djnz	.__dup_context_reference
	pop	af
	ret	po
	ei
	ret
.__dup_context_null:
	ld	a, 8
	add	a, l
	ld	l, a
	djnz	.__dup_context_reference
	pop	af
	ret	po
	ei
	ret
	
.drop_context:
; parse context & flush pages if needed 
; iy is thread
	ld	a, i
	push	af
	di
	ld	hl, kmm_ptlb_map + KERNEL_MM_GFP_KERNEL + KERNEL_MM_PAGE_MAX
	ld	b, 28
	lea	de, iy+KERNEL_THREAD_VMMU_CONTEXT
.__drop_context_reference:
	ld	a, (de)
	inc	de
	or	a, a
	jr	z, .__drop_context_null
	rra
	jr	nc, .__drop_bit_0
	dec	(hl)
	jr	nz, .__drop_bit_0
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_0:
	inc	l
	rra
	jr	nc, .__drop_bit_1
	dec	(hl)
	jr	nz, .__drop_bit_1
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_1:
	inc	l
	rra
	jr	nc, .__drop_bit_2
	dec	(hl)
	jr	nz, .__drop_bit_2
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_2:
	inc	l
	rra
	jr	nc, .__drop_bit_3
	dec	(hl)
	jr	nz, .__drop_bit_3
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_3:
	inc	l
	rra
	jr	nc, .__drop_bit_4
	dec	(hl)
	jr	nz, .__drop_bit_4
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_4:
	inc	l
	rra
	jr	nc, .__drop_bit_5
	dec	(hl)
	jr	nz, .__drop_bit_5
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_5:
	inc	l
	rra
	jr	nc, .__drop_bit_6
	dec	(hl)
	jr	nz, .__drop_bit_6
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_6:
	inc	l
	rra
	jr	nc, .__drop_bit_7
	dec	(hl)
	jr	nz, .__drop_bit_7
	dec	h
	call	mm.flush_page
	inc	h
.__drop_bit_7:
	inc	l
	djnz	.__drop_context_reference
	pop	af
	ret	po
	ei
	ret
.__drop_context_null:
	ld	a, 8
	add	a, l
	ld	l, a
	djnz	.__drop_context_reference
	pop	af
	ret	po
	ei
	ret

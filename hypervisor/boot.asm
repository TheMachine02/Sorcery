define	leaf_bound_lower	$D000FA
define	leaf_bound_upper	$D000FD

leaf:
 
.check_file:
; iy = file adress (static)
	ld	a, (iy+LEAF_IDENT_MAG0)
	cp	a, $7F
	ret	nz
	ld	hl, (iy+LEAF_IDENT_MAG1)
	ld	de, ('A'*65536)+('E'*256)+'L'
	sbc	hl, de
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG4)
	cp	a, 'F'
	ret	nz
	
.check_supported:
	ld	a, (iy+LEAF_HEADER_MACHINE)
	or	a, a	; =LM_EZ80_ADL=0 ?
	ret	nz
	ld	a, (iy+LEAF_HEADER_TYPE)
	cp	a, LT_EXEC
	ret	nz
	ld	a, (iy+LEAF_HEADER_FLAGS)
	cpl
	bit	LF_STATIC_BIT, a
	ret

.exec_static:
; grab the entry point of the program and jump to it
; make section protected for the kernel ?
; execute in place
; we need to reallocate here
; read section table and copy at correct location (for those needed)
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; read section now
	ld	b, (iy+LEAF_HEADER_SHNUM)
.alloc_prog_loop:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	z, .alloc_next_section
	push	bc
	ld	hl, $E40000+SHT_NOBITS
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, l
	jr	z, .copy_null
	ld	hl, (ix+LEAF_SECTION_OFFSET)
	lea	bc, iy+0
	add	hl, bc
.copy_null:
	ld	bc, (ix+LEAF_SECTION_SIZE)
; we are a static file, the addr is RAM adress
	ld	de, (ix+LEAF_SECTION_ADDR)
	ldir
	pop	bc
.alloc_next_section:
	lea	ix, ix+16
	djnz    .alloc_prog_loop
	bit	LF_PROTECTED_BIT, (iy+LEAF_HEADER_FLAGS)
	call	nz, .protected_static
; load up entry
; and jump !
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	jp	(hl)

.protected_static:
; find execution bound for a static program
	ld	hl, $D00000
	ld	(leaf_bound_lower), hl
	ld	(leaf_bound_upper), hl
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; read section now
	ld	b, (iy+LEAF_HEADER_SHNUM)
.bound_loop:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	z, .bound_next_section
	ld	de, (ix+LEAF_SECTION_ADDR)
	ld	hl, (leaf_bound_lower)
	sbc	hl, de
	jr	c, .bound_upper
	ld	(leaf_bound_lower), de
.bound_upper:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	add	hl, de
	ex	de, hl
	ld	hl, (leaf_bound_upper)
	or	a, a
	sbc	hl, de
	jr	nc, .bound_lower
	ld	(leaf_bound_upper), de
.bound_lower:
.bound_next_section:
	lea	ix, ix+16
	djnz	.bound_loop
	ld	hl, leaf_bound_lower
	ld	bc, $620
	otimr
	ret

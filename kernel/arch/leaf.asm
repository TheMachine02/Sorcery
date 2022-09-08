leaf:

.check_file:
; iy = file adress
	ld	a, (iy+LEAF_IDENT_MAG0)
	cp	a, $C9
	ret	nz
	ld	hl, (iy+LEAF_IDENT_MAG1)
	ld	de, 'L'+('E'*256)+('A'*65536)
	sbc	hl, de
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG4)
	cp	a, 'F'
.check_supported:
	ld	a, (iy+LEAF_HEADER_TYPE)
	sub	a, LT_EXEC
	ret	nz
	or	a, (iy+LEAF_HEADER_MACHINE)
	ret

.exec_dma:
; iy is pointer to start of the file (either through mmap or direct flash reading)
	call	.check_file
	ld	hl, -ENOEXEC
	ret	nz
; execute the leaf file
	ld	a, (iy+LEAF_HEADER_FLAGS)
	and	a, LF_REALLOC
	ret	z
; we need to reallocate here
; read section table and allocate all section, including symbol section (will hold address of reallocated)
; write allocated section address to the symbol table ? > all symbol refering to section, make it abs + add section
; perform realloc with symsh and rel section, it hold offset within section + section
; if section = abs, paste directly symbol value + offset within realloc
; section = undef, need to find within shared lib
; first, find symbol section and allocate it
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; ix = section header, iy is file header
; read section now
	call	.__exec_alloc_symtab
	ld	hl, -ENOMEM
	ret	c
	call	.__exec_alloc_section
	ld	hl, -ENOMEM
	ret	c
.__exec_realloc:
; de  = symbol table, ix = section table, iy = file header
	ld	b, (iy+LEAF_HEADER_SHNUM)
; we shouldn't need iy anymore
.__exec_realloc_section_loop:
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, SHT_REL
	call	z, .__exec_realloc_section
	lea	ix, ix+16
	djnz	.__exec_realloc_section_loop
; program is "loaded"
; find entry
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	add	hl, de
	jp	.__exec_realloc_sym

.__exec_alloc_symtab:
	push	ix
	ld	b, (iy+LEAF_HEADER_SHNUM)
.__exec_alloc_symtab_loop:
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, SHT_SYMTAB
	jr	z, .__exec_alloc_symtab_bits
	lea	ix, ix+16
	djnz	.__exec_alloc_symtab_loop
.__exec_alloc_generic_error:
	pop	ix
	scf
	ret
.__exec_alloc_symtab_bits:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	call	.__vmalloc
	jr	c, .__exec_alloc_generic_error
; hl = address
	push	hl
	ex	de, hl
	lea	bc, iy+0
	ld	hl, (ix+LEAF_SECTION_OFFSET)
	add	hl, bc
	ld	bc, (ix+LEAF_SECTION_SIZE)
	ldir
	pop	de
	pop	ix
; de = symtab, we'll need to keep it safe
	or	a, a
	ret
	
.__exec_alloc_section:
; ix = section headers, iy = file headers
	push	ix
	ld	b, (iy+LEAF_HEADER_SHNUM)
.__exec_alloc_section_loop:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	nz, .__exec_alloc_section_bits
.__exec_alloc_section_next:
	lea	ix, ix+16
	djnz	.__exec_alloc_section_loop
	pop	ix
	or	a, a
	ret
.__exec_alloc_section_bits:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	call	.__vmalloc
	jr	c, .__exec_alloc_generic_error
; hl = section address, need to paste it into symbol table for the section address
; section symbol is in section adr
	push	ix
	ld	ix, (ix+LEAF_SECTION_ADDR)
	add	ix, de
; section symbol value, and SHN_ABS, so all good
	ld	(ix+LEAF_SYMBOL_VALUE), hl
	ld	(ix+LEAF_SYMBOL_SHNDX), SHN_ABS
	pop	ix
; now, do we need to copy or not ?
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, SHT_NOBITS
	jr	z, .__exec_alloc_section_next
; yup, copy
	cp	a, SHT_PROGBITS
	jr	nz, .__exec_alloc_section_next
; copy the section data to hl
	ex	de, hl
	push	hl
	push	bc
	lea	bc, iy+0
	ld	hl, (ix+LEAF_SECTION_OFFSET)
	add	hl, bc
	ld	bc, (ix+LEAF_SECTION_SIZE)
	ldir
	pop	bc
	pop	de
	jr	.__exec_alloc_section_next

.__exec_realloc_section:
; ix is a realloc section
; retrieve the reallocation data
	push	bc
	push	iy
	push	ix
	ld	bc, (ix+LEAF_SECTION_OFFSET)
	add	iy, bc
; iy point to section offset, de to symtab
	ld	hl, (ix+LEAF_SECTION_ADDR)
	add	hl, de
	inc	hl
	ld	hl, (hl)	; this is section base address
	ld	bc, (ix+LEAF_SECTION_SIZE)
	ld	a, (ix+LEAF_SECTION_SIZE+2)
	rra
	rr	b
	rr	c
	rra
	rr	b
	rr	c
	rra
 	rr	b
	rr	c
.__exec_realloc_sym_loop:
	push	bc
	push	hl
	ld	bc, (iy+LEAF_REL_OFFSET)
	add	hl, bc
; hl is the offset in section
; get symbol of the rel
	ld	ix, (iy+LEAF_REL_INFO)
	add	ix, de
; ix is the symbol of the rel, get the value of the symbol
; first type
	ld	a, (ix+LEAF_SYMBOL_SHNDX)
	cp	a, SHN_ABS
	jr	nz, .__exec_realloc_sym_external
	ld	ix, (ix+LEAF_SYMBOL_VALUE)
	ld	bc, (hl)
	add	ix, bc
	ld	(hl), ix
.__exec_realloc_sym_next:
	lea	iy, iy+8
	pop	hl
	pop	bc
	dec	bc
	ld	a, b
	or	a, c
	jr	nz, .__exec_realloc_sym_loop
	pop	ix
	pop	iy
	pop	bc
	ret

.__exec_realloc_sym_external:
; not implemented yet
	jr	.__exec_realloc_sym_next

.__exec_realloc_sym:
; hl is symbol
	ld	a, (hl)
	cp	a, SHN_ABS
	jr	z, .__exec_realloc_sym_absolute
	cp	a, SHN_UNDEF
	jr	z, .__exec_realloc_sym_external
; else, find section index, grab it's address and push
	inc	hl
; offset within section
	ld	bc, (hl)
	ld	h, a
	ld	l, 8
	mlt	hl
	add	hl, de
	inc	hl
	ld	hl, (hl)
	add	hl, bc
; hl is symbol true value
	ret
.__exec_realloc_sym_absolute:
	inc	hl
	ld	hl, (hl)
	ret

.__vmalloc:
	push	bc
	push	de
	push	hl
	inc	sp
	pop	hl
	dec	sp
	ld	a, l
	srl	h
	rra
	srl	h
	rra
	ld	c, a
	inc	c
	ld	b, KERNEL_MM_GFP_USER
	call	vmmu.map_pages
	pop	de
	pop	bc
	ret
	
.__exec_realloc_section_index:
; section symbol are always first in symbol table to ease computation
	ld	h, a
	ld	l, 8
	mlt	hl
	add	hl, de
	inc	hl
	ld	hl, (hl)
	ret

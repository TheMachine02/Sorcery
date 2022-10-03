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
; NOTE : return carry set if an error occured
	call	.check_file
	scf
	ld	hl, -ENOEXEC
	ret	nz
; execute the leaf file
	ld	a, (iy+LEAF_HEADER_FLAGS)
	and	a, LF_REALLOC
	scf
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
	push	ix
; de  = symbol table, ix = section table, iy = file header
	ld	b, (iy+LEAF_HEADER_SHNUM)
; we shouldn't need iy anymore
.__exec_realloc_section_loop:
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, SHT_REL
	call	z, .__exec_realloc_section
	lea	ix, ix+16
	djnz	.__exec_realloc_section_loop
	pop	ix
; program is "loaded"
; find entry
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	add	hl, de

; realloc a symbol (hl is symbol adress in symtab)
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
	push	ix
	ld	b, 16
	ld	c, a
	mlt	bc
	add	ix, bc
; offset within section
	ld	bc, (hl)
; grab symbol of the section
	ld	hl, (ix+LEAF_SECTION_ADDR)
	add	hl, de
	inc	hl
	ld	hl, (hl)
	add	hl, bc
	pop	ix
; hl is symbol true value
	or	a, a
	ret
.__exec_realloc_sym_absolute:
	inc	hl
	ld	hl, (hl)
	or	a, a
	ret
.__exec_realloc_sym_external:
; not implemented yet
	scf
	sbc	hl, hl
	ret	
	
; allocate the symtab found in the exec file
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

; allocate all the needed section in RAM
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

; apply realloc section data
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
	jr	nz, .__exec_realloc_sym_lib
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
.__exec_realloc_sym_lib:
	call	.__exec_realloc_sym_external
	jr	.__exec_realloc_sym_next

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

.exec_dma_static:
	ld	hl, .microcode
	ld	de, exec_microcode
	ld	bc, EXEC_MICROCODE_SIZE
	ldir
	jp	.exec_load
	
.microcode:
 org	exec_microcode
; for boundary
 rb	6
 
.exec_load:
; only for static program (kernel)
; read section table and copy at correct location (for those needed)
; NOTE : this is for kernel execution
; TODO : also support non kernel program (we must allocate when copying at exact location)
	call	.check_file
	ld	hl, -ENOEXEC
	scf
	ret	nz
; execute the leaf file
	ld	a, (iy+LEAF_HEADER_FLAGS)
	and	a, LF_REALLOC
	scf
	ret	z
	bit	LF_STATIC_BIT, (iy+LEAF_HEADER_FLAGS)
	ret	z
; do we truly have a kernel ? ENTRY POINT must be equal to $D01000
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	ld	de, $D01000
	or	a, a
	sbc	hl, de
	ld	hl, -ENOEXEC
	scf
	ret	nz
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; read section now
	ld	b, (iy+LEAF_HEADER_SHNUM)
.alloc_prog_section:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	z, .alloc_next_section
	push	bc
	ld	hl, $E40000+SHT_NOBITS
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, l
	jr	z, .alloc_nobits
	ld	hl, (ix+LEAF_SECTION_OFFSET)
	lea	bc, iy+0
	add	hl, bc
.alloc_nobits:
	ld	bc, (ix+LEAF_SECTION_SIZE)
; we are a static file, the addr is RAM adress
	ld	de, (ix+LEAF_SECTION_ADDR)
	ldir
	pop	bc
.alloc_next_section:
	lea	ix, ix+16
	djnz    .alloc_prog_section
	bit	LF_PROTECTED_BIT, (iy+LEAF_HEADER_FLAGS)
	call	nz, .protected_static
; load up entry
; and jump !
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	jp	(hl)

.protected_static:
; find execution bound for a static program
	ld	hl, $D00000
	ld	(leaf_boundary_lower), hl
	ld	(leaf_boundary_upper), hl
	lea	bc, iy+0
	ld	ix, (iy+LEAF_HEADER_SHOFF)
	add	ix, bc
; read section now
	ld	b, (iy+LEAF_HEADER_SHNUM)
.protected_boundary:
	bit	1, (ix+LEAF_SECTION_FLAGS)
	jr	z, .protected_next_section
	ld	de, (ix+LEAF_SECTION_ADDR)
	ld	hl, (leaf_boundary_lower)
	or	a, a
	sbc	hl, de
	jr	c, .protected_bound_upper
	ld	(leaf_boundary_lower), de
.protected_bound_upper:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	add	hl, de
	ex	de, hl
	ld	hl, (leaf_boundary_upper)
	or	a, a
	sbc	hl, de
	jr	nc, .protected_bound_lower
	ld	(leaf_boundary_upper), de
.protected_bound_lower:
.protected_next_section:
	lea	ix, ix+16
	djnz	.protected_boundary
	ld	hl, leaf_boundary_lower
	ld	bc, $620
	otimr
	ret

 align	256
 org	.microcode + EXEC_MICROCODE_SIZE

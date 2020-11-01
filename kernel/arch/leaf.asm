leaf:
 
.program:
 
sysdef _execve
.execve:
; .BINARY_PATH:	hl
; .BIN_ENVP:	de
; .BIN_ARGV:	bc
	push	de
	push	bc
	call	kvfs.inode_get_lock
	pop	bc
	pop	de
	ret	c
; check if the inode is executable
	ld	a, (iy+KERNEL_VFS_INODE_FLAGS)
	ld	l, a
	and	a, KERNEL_VFS_TYPE_MASK
	ld	a, ENOEXEC
	jp	nz, kvfs.inode_atomic_write_error
	bit	KERNEL_VFS_PERMISSION_X_BIT, l
	jp	z, kvfs.inode_atomic_write_error
; check if inode is DMA, else allocate the header and make it point to ix
	bit	KERNEL_VFS_CAPABILITY_DMA_BIT, l
	jr	z, .execve_no_dma_xip
; does the file support XIP ?
	ld	ix, (iy+KERNEL_VFS_INODE_DMA_DATA)
	ld	ix, (ix+KERNEL_VFS_INODE_DMA_POINTER)
	ld	a, (ix+LEAF_HEADER_FLAGS)
	and	a, LF_XIP
; if not, well need to reallocate anyway, so fall back into the default section
; reading could be simpler, but that mean duplicating some code...
	jr	z, .execve_no_dma_xip
; we have both DMA and XIP (can't use XIP with realloc, they are exclusive)
; TODO : load necessary lib & ptl page & data page
	call	.aux_data
; right now, XIP ONLY with RO data only works
; de & bc are environnement
	call	.aux_environnement
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write	
; find entry point ?
	ld	hl, (ix+LEAF_HEADER_ENTRY)
	jp	(hl)
.execve_no_dma_xip:
; 	ld	hl, LEAF_HEADER_SIZE
; 	call	kmalloc
; 	ret	c
; 	push	de
; 	push	bc
; 	ex	de, hl
; 	push	de
; 	pop	ix
; 	xor	a, a
; 	sbc	hl, hl
; ; a, de, bc, hl are all set (iy is inode)
; ; 	call	kvfs.read_buff
; ; leaf header is ix
; 	pop	bc
; 	pop	de
; 	lea	hl, ix+0
; 	call	kfree
	lea	hl, iy+KERNEL_VFS_INODE_ATOMIC_LOCK
	call	atomic_rw.unlock_write
	scf
	ret
.aux_environnement:
	ret
.aux_data:
	ret
.aux_prog:
	ret

.check_file:
; iy = file adress (static for now, we'll need read syscall)
	ld	a, (iy+LEAF_IDENT_MAG0)
	cp	a, 0x7F
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG1)
	cp	a, 'L'
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG2)
	cp	a, 'E'
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG3)
	cp	a, 'A'
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG4)
	cp	a, 'F'
	ret	nz
.check_supported:
	ld	a, (iy+LEAF_HEADER_TYPE)
	cp	a, LT_EXEC
	ret	nz
	ld	a, (iy+LEAF_HEADER_MACHINE)
	cp	a, LM_EZ80_ADL
	ret
	
.BROKEN:
	call	.check_file
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
	call	.alloc_symtab
	ret	c
	call	.alloc_section
	ret	c
.reallocate:
; de  = symbol table, ix = section table, iy = file header
	ld	b, (iy+LEAF_HEADER_SHNUM)
; we shouldn't need iy anymore
.realloc_section_loop:
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, SHT_REL
	call	z, .realloc_section
	lea	ix, ix+16
	djnz	.realloc_section_loop
; program is "loaded"
; find entry
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	add	hl, de
	call	.realloc_sym
	jp	(hl)

.alloc_symtab:
	push	ix
	ld	b, (iy+LEAF_HEADER_SHNUM)
.alloc_symtab_loop:
	ld	a, (ix+LEAF_SECTION_TYPE)
	cp	a, SHT_SYMTAB
	jr	z, .alloc_symtab_bits
	lea	ix, ix+16
	djnz	.alloc_symtab_loop
.alloc_generic_error:
	pop	ix
	scf
	ret
.alloc_symtab_bits:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	call	.malloc
	jr	c, .alloc_generic_error
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
	
.alloc_section:
; ix = section headers, iy = file headers
	push	ix
	ld	b, (iy+LEAF_HEADER_SHNUM)
.alloc_section_loop:
	ld	a, (ix+LEAF_SECTION_FLAGS)
	and	a, SHF_ALLOC
	jr	nz, .alloc_section_bits
.alloc_section_next:
	lea	ix, ix+16
	djnz	.alloc_section_loop
	pop	ix
	or	a, a
	ret
.alloc_section_bits:
	ld	hl, (ix+LEAF_SECTION_SIZE)
	call	.malloc
	jr	c, .alloc_generic_error
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
	jr	z, .alloc_section_next
; yup, copy
	cp	a, SHT_PROGBITS
	jr	nz, .alloc_section_next
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
	jr	.alloc_section_next

.realloc_section:
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
.realloc_sym_loop:
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
	jr	nz, .realloc_sym_external
	ld	ix, (ix+LEAF_SYMBOL_VALUE)
	ld	bc, (hl)
	add	ix, bc
	ld	(hl), ix
.realloc_sym_next:
	lea	iy, iy+8
	pop	hl
	pop	bc
	dec	bc
	ld	a, b
	or	a, c
	jr	nz, .realloc_sym_loop
	pop	ix
	pop	iy
	pop	bc
	ret

.realloc_sym_external:
; not implemented yet
	jr	.realloc_sym_next

.realloc_sym:
; hl is symbol
	ld	a, (hl)
	cp	a, SHN_ABS
	jr	z, .realloc_sym_absolute
	cp	a, SHN_UNDEF
	jr	z, .realloc_sym_external
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
.realloc_sym_absolute:
	inc	hl
	ld	hl, (hl)
	ret

.malloc:
	jp	kmalloc

.realloc_section_index:
; section symbol are always first in symbol table to ease computation
	ld	h, a
	ld	l, 8
	mlt	hl
	add	hl, de
	inc	hl
	ld	hl, (hl)
	ret

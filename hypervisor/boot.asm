define	LEAF_HEADER		0
define	LEAF_HEADER_IDENT	0	; 5 bytes
define	LEAF_IDENT		0	; start
define	LEAF_IDENT_MAG0		0	; $7F
define	LEAF_IDENT_MAG1		1	; 'L'
define	LEAF_IDENT_MAG2		2	; 'E'
define	LEAF_IDENT_MAG3		3	; 'A'
define	LEAF_IDENT_MAG4		4	; 'F'
define	LEAF_HEADER_TYPE	5	; 1 byte, LT_EXEC
define	LEAF_HEADER_MACHINE	6	; 1 byte, default, LM_EZ80_ADL
define	LEAF_HEADER_FLAGS	7	; 1 byte (most if reallocatable or static + specific)
define	LEAF_HEADER_ENTRY	8	; 3 bytes, symbol if REALLOC, else direct address
define	LEAF_HEADER_SHOFF	11	; 3 bytes, section offset in file (usually at the end)
define	LEAF_HEADER_SHNUM	14	; 1 bytes, number of section
define	LEAF_HEADER_SHSTRNDX	15	; 1 bytes, string section index

; header is 16 bytes

define	LEAF_SECTION		0
define	LEAF_SECTION_NAME	0	; 3 bytes, offset into the str table
define	LEAF_SECTION_TYPE	3	; 1 byte, type
define	LEAF_SECTION_FLAGS	4	; flags, 1 byte
define	LEAF_SECTION_ADDR	5	; virtual adress
define	LEAF_SECTION_OFFSET	8	; offset in file 
define	LEAF_SECTION_SIZE	11	; size of the section
define	LEAF_SECTION_INFO	14	; link to an other section (for rel section)
define	LEAF_SECTION_PAD	15	; pad to 16 bytes

; relocation, 6 bytes ;
define	LEAF_REL		0
define	LEAF_REL_OFFSET		0	; offset within section of the data to realloc (rel section are section defined with INFO
define	LEAF_REL_INFO		3	; more info (symbol index)

; symbol structure, 8 bytes
define	LEAF_SYMBOL		0
define	LEAF_SYMBOL_NAME	0	; 3 bytes, index is str table
define	LEAF_SYMBOL_VALUE	3	; 3 bytes, value : either 0 or offset in section
define	LEAF_SYMBOL_INFO	6	; 1 byte, type (func, global etc)
define	LEAF_SYMBOL_SHNDX	7	; 1 bytes, section index, 0 is UNDEF, 0xFF is SHN_ABS

;define	LEAF_ST_BIND(INFO)	((INFO) >> 4)
;define	LEAF_ST_TYPE(INFO)	((INFO) & $0F)

; machine
define	LM_EZ80_ADL		0
define	LM_EZ80_COMP		1
define	LM_Z80			2
; type
define	LT_NONE			0
define	LT_REL			1
define	LT_EXEC			2
define	LT_DYN			3
define	LT_CORE			4
; flags
define	LF_COMPRESSED		$1
define	LF_STATIC		$2
define	LF_REALLOC		$4
 
; section type
define	SHT_NULL		0
define	SHT_PROGBITS		1
define	SHT_SYMTAB		2
define	SHT_STRTAB		3
define	SHT_HASH		4
define	SHT_DYNAMIC		5
define	SHT_NOBITS		6
define	SHT_REL			7
define	SHT_INTERP		8

; section flags
define	SHF_WRITE		$1
define	SHF_ALLOC		$2
define	SHF_EXECINSTR		$4

; special section indexes
define	SHN_UNDEF		0
define	SHN_ABS			0xFF

define	STB_LOCAL		0
define	STB_GLOBAL		1
define	STB_WEAK		2

define	STT_NOTYPE		0
define	STT_OBJECT		1
define	STT_FUNC		2
define	STT_SECTION		3
define	STT_FILE		4
define	STT_COMMON		5
define	STT_TLS			6

define	leaf_bound_lower	$D0000A
define	leaf_bound_upper	$D0000D

leaf:
 
.check_file:
; iy = file adress (static)
	ld	hl, (iy+LEAF_IDENT_MAG0)
	ld	de, -(('E'*65536)+('L'*256)+$7F)
	add	hl, de
	ret	nz
	ld	a, (iy+LEAF_IDENT_MAG3)
	cp	a, 'A'
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
; execute the leaf file. It is static ?
	;ld	a, LF_STATIC	; LF_STATIC=LT_EXEC=2
	xor	a, (iy+LEAF_HEADER_FLAGS)
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
	push	bc
	ld	a, (ix+LEAF_SECTION_FLAGS)
	and	a, SHF_ALLOC
	jr	z, .alloc_next_section
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
.alloc_next_section:
	lea	ix, ix+16
	pop	bc
	djnz	.alloc_prog_loop	
	call	.bound_static
.priviligied_static:
	ld	hl, leaf_bound_lower
	ld	bc, $620
	otimr
; load up entry
; and jump !
	ld	hl, (iy+LEAF_HEADER_ENTRY)
	jp	(hl)

.bound_static:
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
	push	bc
	ld	a, (ix+LEAF_SECTION_FLAGS)
	and	a, SHF_ALLOC
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
	pop	bc
	djnz	.bound_loop
	ret

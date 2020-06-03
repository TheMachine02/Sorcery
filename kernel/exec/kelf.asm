; type ;
define	ELF_EXEC		1
define	ELF_SO			2
; section type ;
define	ELF_RW_DATA		2
define	ELF_RW_INSTR		2
define	ELF_RO_DATA		3
define	ELF_RW_ZERO		4
define	ELF_DYNAMIC		5
; header size ;
define	ELF_HEADER_SIZE		6
; section ;
define	ELF_SECTION_HEADER	0
define	ELF_SECTION_HEADER_SIZE	8
define	ELF_SECTION_TYPE	0
define	ELF_SECTION_OFFSET	2
define	ELF_SECTION_SIZE	5

define	ELF_REALLOC_SIZE	4
define	ELF_REALLOC_OFFSET	0
define	ELF_REALLOC_SECTION	3

define	ELF_MAG0		0
define	ELF_MAG1		1
define	ELF_MAG2		2
define	ELF_MAG3		3
define	ELF_TYPE		4
define	ELF_VERSION		5

define	kelf_section_ptr	$D0000D
define	kelf_section_owner	$D0000C

kelf:
.load_section:
; read section table, generate malloc table
; section is : 
; type, 0x0
; section_file offset
; section_size
	push	hl
	pop	ix
	ld	hl, KERNEL_MMU_RAM
	ld	a, (kelf_section_owner)
	call	kmmu.map_page_thread
	jp	c, kthread.exit
	ld	(kelf_section_ptr), hl
	lea	iy, ix + 0
	lea	ix, ix+ELF_HEADER_SIZE+1
	ld	b, (ix-1)   ; section count
; hl = ELF_TEMPORARY_SECTION_ADRESS
; iy = elf_start
.section_parse:
	push	hl
	ld	a, (ix+ELF_SECTION_TYPE)
	cp	a, ELF_RW_ZERO
	jr	z, .section_rw_zero
	cp	a, ELF_RW_DATA
	jr	z, .section_rw
	cp	a, ELF_DYNAMIC
	jr	z, .section_dynamic
; ELF_RO_DATA / ELF_RO_INSTR
.section_ro:
	ld	de, (ix+ELF_SECTION_OFFSET)
	lea	hl, iy+1    ; beware offset of count of reallocation
	add	hl, de
; adress of the section for the program execution = hl (there IS NO REALLOCATION DATA for RO type)
	ex	de, hl
	jr	.section_continue
.section_dynamic:
	push	bc
	push	iy
	push	ix
	ld	hl, (ix+ELF_SECTION_SIZE)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .section_empty
	ld	hl, (kelf_section_ptr)
	push	hl
	ld	a, (kelf_section_owner)
	push	af
	ld	de, (ix+ELF_SECTION_OFFSET)
	lea	hl, iy+1    ; beware offset of count of reallocation
	add	hl, de
; hl = string of the name
	call	kso.load_elf
	pop	af
	ld	(kelf_section_owner), a
	pop	hl
	ld	(kelf_section_ptr), hl
	lea	de, iy+0
.section_empty:
	pop	ix
	pop	iy
	pop	bc
	jr	.section_continue
.section_rw_zero:
; save iy too, but malloc doesn't destroy iy
	ld	hl, (ix+ELF_SECTION_SIZE)
	call	.section_alloc
	jp	c, kthread.exit
; adress of the section for the program execution = hl (there IS NO REALLOCATION DATA for RW_ZERO type)
	ex	de, hl
	jr	.section_continue
.section_rw:
	push	bc
	ld	hl, (ix+ELF_SECTION_SIZE)
	call	.section_alloc
	jp	c, kthread.exit
	ex	de, hl
	ld	bc, (ix+ELF_SECTION_OFFSET)
	lea	hl, iy+0
	add	hl, bc
; number of adress reallocation
	ld	a, (hl)
	ld	b, a
	ld	c, ELF_REALLOC_SIZE
	mlt	bc
	add	hl, bc
	inc	hl
; this is the true start of the section
; de = malloc
	ld	bc, (ix+ELF_SECTION_SIZE)
	push	de
	ldir
	pop	de    
	pop	bc
.section_continue:
	pop	hl
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	lea	ix, ix+ELF_SECTION_HEADER_SIZE
;	djnz	.section_parse
	dec	b
	jp	nz, .section_parse
; I have section loaded, now I need to realloc stuff.
.section_realloc:
; so parse back the section table, jump to realloc table
	lea	de, iy+0
	lea	ix, iy+ELF_HEADER_SIZE + 1
	ld	b, (ix-1)   ; section count
	ld	hl, (kelf_section_ptr)
.section_realloc_loop:
	ld	iy, (ix+ELF_SECTION_OFFSET)
	add	iy, de
	ld	a, (iy+0)
	inc	iy
	or	a, a
	jp	z, .section_realloc_skip
	ld	c, a
	push	de
	push	hl
	ld	hl, (hl)	; this is section adress
.section_realloc_mark:
	push	hl
	ld	de, (iy+ELF_REALLOC_OFFSET)
	add	hl, de
	ld	de, (hl)	; this is READVALUE, add up the section adress
	push	hl
	push	de
	ld	a, (iy+ELF_REALLOC_SECTION)
	or	a, a
	sbc	hl, hl
	ld	l, a
	add	hl, hl
	add	hl, hl
	ld	de, (kelf_section_ptr)
	add	hl, de
	ld	hl, (hl)
	pop	de
	add	hl, de
	ex	de, hl
	pop	hl
	ld	(hl), de
	pop	hl
	lea	iy, iy+ELF_REALLOC_SIZE
	dec	c
	jr	nz, .section_realloc_mark
	pop	hl
	pop	de
.section_realloc_skip:
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	lea	ix, ix+ELF_SECTION_HEADER_SIZE
	djnz	.section_realloc_loop
	ld	hl, (kelf_section_ptr)
	ld	iy, (hl)
	ld	a, (kelf_section_owner)
	jp	kmmu.unmap_page_thread
.section_alloc:
	push	bc
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
	ld	a, (kelf_section_owner)
	call	kmmu.map_block_thread
	pop	bc
	ret

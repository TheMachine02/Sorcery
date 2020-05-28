kexec:

.load_elf16_ptr:
; Load an elf16 program
; REGSAFE and ERRNO compliant
; int load_elf16_ptr(void* ptr)
; register HL is ptr
; error -1 and c set, 0 and nc otherwise, ERRNO set
; HL, BC, DE, IX is zero, IY is start program adress, A is zero and flag reset
	push	iy
	ld	a, (hl)
	cp	0x8F
	jr	nz, .load_elf16_no_exec
	inc	hl
	ld	a, (hl)
	cp	'E'
	jr	nz, .load_elf16_no_exec
	inc	hl
	ld	a, (hl)
	cp	'L'
	jr	nz, .load_elf16_no_exec
	inc	hl
	ld	a, (hl)
	cp	'F'
	jr	nz, .load_elf16_no_exec
	inc	hl
	ld	a, (hl)
	cp	ELF_EXEC
	jr	nz, .load_elf16_no_exec
	dec	hl
	dec	hl
	dec	hl
	dec	hl
	ld	iy, .load_program
; pass through error from kthread.create
	call	kthread.create
	pop	iy
	ret
.load_elf16_no_exec:
	ld	l, ENOEXEC
.load_elf16_errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
	pop	iy
	scf
	sbc	hl, hl
	ret
	
.load_program:
	call	kelf.load_section
	ld	ix, NULL
	lea	hl, ix+0
	lea	de, ix+0
	lea	bc, ix+0
	xor	a, a
	jp	(iy)

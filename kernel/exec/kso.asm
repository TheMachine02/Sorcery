kso:

.load_elf16_ptr:
; Load an elf16 shared object
; REGSAFE and ERRNO compliant
; int load_elf16_ptr(void* ptr)
; register HL is ptr
; error -1 and c set, 0 and nc otherwise, ERRNO set
	ld	a, (hl)
	cp	0x8F
	jr	nz, .load_elf16_no_so
	inc	hl
	ld	a, (hl)
	cp	'E'
	jr	nz, .load_elf16_no_so
	inc	hl
	ld	a, (hl)
	cp	'L'
	jr	nz, .load_elf16_no_so
	inc	hl
	ld	a, (hl)
	cp	'F'
	jr	nz, .load_elf16_no_so
	inc	hl
	ld	a, (hl)
	cp	ELF_SO
	jr	nz, .load_elf16_no_so
	dec	hl
	dec	hl
	dec	hl
	dec	hl
	call	kelf.load_section
; iy = first section or jump table
	ret
.load_elf16_no_so:
	ld	l, ELIBACC
.load_elf16_errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), l
	pop	iy
	scf
	sbc	hl, hl
	ret

; .load_elf16:
; ; give the name and try to find it on path (/lib/ and LD_LIBRARY)
; 	ld	ix, .FROZEN_LIBTEST
; 	call	.load_elf16_ptr
; ; iy = first section or jump table section
; 	ret
; 	
; .FROZEN_LIBTEST:
; include 'libtest.so'

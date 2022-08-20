virtual at 0
	PROFIL_BUFFSIZE:	rb 3
	PROFIL_BUFF:		rb 3
	PROFIL_OFFSET:		rb 3
	PROFIL_SCALE:		rb 3
end virtual

; hypervisor call
define	VM_HYPERVISOR_ADRESS	$0BF000

macro	hyperjump x
	jp	x*4+VM_HYPERVISOR_ADRESS
end macro

macro	hypercall x
	call	x*4+VM_HYPERVISOR_ADRESS
end macro

; ABI specification :
; all 24 bits registers are paramaters, in order :
; hl, de, bc, ix, iy
; more than 5 parameters need to pass other parameters in stack
; all register are preserved across syscall except for the return register hl
; flags are preserved across syscall
macro sysdef label
	label = $
	push	ix
	push	iy
	push	de
	push	bc
	push	af
	push	hl
	ld	hl, user_return
	ex	(sp), hl
end macro

; for the kernel, syscall are simply calling the label (without preserving register, if possible)
; for external libc, it is calling the kernel jump table, which will jump to the preserving registers & specific return function
macro syscall label
	call	label
end macro

sysdef _enosys
user_enosys:
	ld	a, ENOSYS

user_error:
	neg
	scf
	sbc	hl, hl
	ld	l, a
	ret

sysdef	_kmalloc
; those are kinda special since they don't have many error, and already save and restore register
; you can call them directly if you wish
; may destroy a if there is an error (please note kernel routine should call kmalloc directly and handle error themselves)
	call	kmalloc
	ret	nc
	ld	hl, -ENOMEM
	ret

sysdef	_kfree
	call	kfree
	ret	nc
	ld	hl, -EFAULT
	ret

sysdef _brk
	ld	iy, (kthread_current)
.brk_extend:
; now check : that sp - 512 > hl
	push	hl
	ld	hl, -512
	add	hl, sp
	pop	bc
	or	a, a
	sbc	hl, bc
	ld	hl, -ENOMEM
	ret	c
; all good, return the old break value
	ld	hl, (iy+KERNEL_THREAD_BREAK)
	ld	(iy+KERNEL_THREAD_BREAK), bc
	ret

sysdef _sbrk
; increment as hl
	ld	iy, (kthread_current)
	ld	de, (iy+KERNEL_THREAD_BREAK)
	add	hl, de
	jr	.brk_extend
	
sysdef _uadmin
; TODO : implement
; cmd, fn, mdep
uadmin:
	call	user_perm
	ret

; priority
sysdef _nice
nice:
	call	user_perm
; hl = nice, return the new nice value
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_NICE)
	add	a, l
; between -20 and 19
	jp	m, .check_max
	cp	a, 20
	jr	c, .return
	ld	a, NICE_PRIO_MIN
	jr	.return
.check_max:
	cp	a, -20
	jr	nc, .return
	ld	a, NICE_PRIO_MAX
.return:
	ld	(iy+KERNEL_THREAD_NICE), a
	add	a, a
	sbc	hl, hl
	rra
	ld	l, a
	ret

; flash unlock and lock

sysdef _flash_unlock
flash.unlock:
if $ > $D00000
	hyperjump	0
else
; need to be in privileged flash actually
	in0	a, ($06)
	or	a, 4
	out0	($06), a
; flash sequence
	ld	a, 4
	di 
	jr	$+2
	di
	rsmix 
	im 1
	out0	($28), a
	in0	a, ($28)
	bit	2, a
	ret
end if

sysdef _flash_lock
flash.lock:
if $ > $D00000
	hyperjump	1
else
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret
end if

sysdef _profil
profil:
; int profil(unsigned short *buf, size_t bufsiz, size_t offset, unsigned int scale);
; disable profiling if buf == NULL
;  Every virtual 10 milliseconds, the user's program counter (PC)
;  is examined: offset is subtracted and the result is multiplied by
;  scale and divided by 65536.  If the resulting value is less than
;  bufsiz, then the corresponding entry in buf is incremented
.syscall:
; hl : buf, de : bufsize, bc : offset, ix : scale
	ld	iy, (kthread_current)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .__profil_reset
; also reset if there was already profiling
	bit	THREAD_PROFIL_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	jr	nz, .__profil_reset
	push	hl
	ld	hl, kmem_cache_s16
	call	kmem.cache_alloc
	ld	(iy+KERNEL_THREAD_PROFIL_STRUCTURE), hl
	jr	c, .__profil_error
; fill in the structure
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
	pop	de
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
	ld	(hl), bc
	inc	hl
	inc	hl
	inc	hl
	dec	sp
	push	ix
	inc	sp
	pop	de
; ix / 256
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	xor	a, a
	ld	(hl), a
; set the profiler
	set	THREAD_PROFIL_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	sbc	hl, hl
	ret
.__profil_reset:
	res	THREAD_PROFIL_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	ld	hl, (iy+KERNEL_THREAD_PROFIL_STRUCTURE)
	call	kfree
	or	a, a
	sbc	hl, hl
	ld	(iy+KERNEL_THREAD_PROFIL_STRUCTURE), hl
	ret
.__profil_error:
	pop	hl
	ld	hl, -ENOMEM
	ret

.scheduler:
; Preserve af and iy and hl++++, also, pc is push on the stack at a very precise adress
	push	af
	push	iy
	push	hl
; get the pc
	ld	hl, 18
	add	hl, sp
	ld	hl, (hl)
; hl = pc
	ld	iy, (iy+KERNEL_THREAD_PROFIL_STRUCTURE)
	ld	de, (iy+PROFIL_OFFSET)
	or	a, a
	sbc	hl, de
; multiply by scale/65536
; best is (a)*(b/256)/256 right now
	ld	bc, (iy+PROFIL_SCALE)
; hl = hl/256
; hl * bc = hl
	call	__imulu
	dec	sp
	push	hl
	inc	sp
	pop	hl
	inc.s	hl
	dec.s	hl
; check hl against buffsize
	ld	de, (iy+PROFIL_BUFFSIZE)
	or	a, a
	sbc	hl, de
; nc : not taken in account
	jr	nc, .__scheduler_restore
; else increment the entrie in buffsize
	add	hl, de
	add	hl, hl
	ld	de, (iy+PROFIL_BUFF)
	add	hl, de
; entrie are unsigned short
	ld	de, (hl)
	inc	de
	ld	(hl), e
	inc	hl
	ld	(hl), d
.__scheduler_restore:
	pop	hl
	pop	iy
	pop	af
	ret

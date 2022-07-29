define	VM_HYPERVISOR_ADRESS	$0BF000

virtual at 0
	PROFIL_BUFFSIZE:	rb 3
	PROFIL_BUFF:		rb 3
	PROFIL_OFFSET:		rb 3
	PROFIL_SCALE:		rb 3
end virtual

macro sysdef label
	label = $
; all register are paramaters (a,de,bc,hl,iy,ix)
; all register are preserved across syscall (except hl as return register)
	push	ix
	push	iy
	push	de
	push	bc
	push	af
	push	hl
	ld	hl, user_return
	ex	(sp), hl
end macro

macro syscall label
; for the kernel, syscall are simply calling the label
; for external libc, it is calling the *JUMP TABLE*
	call	label
end macro

macro	hyperjump x
	jp	x*4+VM_HYPERVISOR_ADRESS
end macro

macro	hypercall x
	call	x*4+VM_HYPERVISOR_ADRESS
end macro

user_perm:
; NOTE : expect to return to the trampoline at the current code level (so, first routine to be called in the routine, and will exit the routine itself)
; check for the thread permission currently executing this code span
; is it superuser or not ?
	push	af
	push	hl
	ld	hl, (kthread_current)
assert KERNEL_THREAD_PID = 0
	ld	a, (hl)
	add	a, a
	add	a, a
	ld	hl, kthread_pid_map
	ld	l, a
	bit	SUPER_USER_BIT, (hl)
	pop	hl
	jr	z, .permission_failed
	pop	af
	ret
.permission_failed:
	pop	af
	pop	af	; throw away the return adress
	ld	hl, -EPERM
	ret

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

; those actually set the stack limit
; TODO : actualize those to be actually * correct *
	
sysdef _brk
	ld	iy, (kthread_current)
	jr	.brk_check
	
sysdef _sbrk
; increment as hl
	ld	iy, (kthread_current)
	ld	de, (iy+KERNEL_THREAD_BREAK)
	add	hl, de
.brk_check:
	ld	a, ENOMEM
; now check : that sp - 512 > hl and that hl > iy + 256+13
	lea	bc, iy+13
	inc	d
	or	a, a
	sbc	hl, bc
	jr	c, user_error
	add	hl, bc
; now check with sp
	push	hl
	ld	hl, -512
	add	hl, sp
	pop	bc
	or	a, a
	sbc	hl, bc
	jp	c, user_error
; all good, return the old break value
	ld	(iy+KERNEL_THREAD_BREAK), bc
	ex	de, hl
	ret

sysdef _getpid
; pid_t getpid()
; return value is register hl
getpid:
	ld	hl, (kthread_current)
	ld	l, (hl)
	ld	h, 1
	mlt	hl
	ret
  
sysdef _getppid
; pid_t getppid()
; return value is register hl
getppid:
	ld	hl, (kthread_current)
	ld	de, KERNEL_THREAD_PPID
	add	hl, de
	ld	e, (hl)
	ex	de, hl
	ret

sysdef _getuid
; uid_t getuid()
; return value is register hl, -1 if super user, 0 is normal user
getuid:
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	hl, kthread_pid_map
	add	a, a
	add	a, a
	ld	l, a
	ld	a, (hl)
assert SUPER_USER_BIT = 7
	rla
	sbc	hl, hl
	ret
	
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
	bit	THREAD_PROFIL, (iy+KERNEL_THREAD_ATTRIBUTE)
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
	set	THREAD_PROFIL, (iy+KERNEL_THREAD_ATTRIBUTE)
	sbc	hl, hl
	ret
.__profil_reset:
	res	THREAD_PROFIL, (iy+KERNEL_THREAD_ATTRIBUTE)
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

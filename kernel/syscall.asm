define	PROFIL_BUFFSIZE		0
define	PROFIL_BUFF		3
define	PROFIL_OFFSET		6
define	PROFIL_SCALE		9

macro align number
	rb number - ($ mod number)
end macro

macro sysdef label
	label = $
end macro

syscall:
; a is the syscall number, other register are paramaters (de,bc,hl,iy)
; all register are preserved across syscall (except hl as return register)
; use ix for jumping
	push	ix
	push	iy
	push	de
	push	bc
	push	af
; stack is : sysret / syscall adress, we also need to preserve hl
	push	hl
	ld	hl, sysret
	ex	(sp), hl
	push	hl
	ld	hl, sysjump shr 2
	ld	l, a
	add	hl, hl
	add	hl, hl
; restore and save hl
	ex	(sp), hl
	ret

sysret:
	ei
; end syscall here
	pop	af
	pop	bc
	pop	de
	pop	iy
	pop	ix
	or	a, a
	ret	
	
sysdef _enosys
sysno:
	ld	a, ENOSYS

syserror:
	push	ix
	ld	ix, (kthread_current)
	ld	(ix+KERNEL_THREAD_ERRNO), a
	pop	ix
	scf
	sbc	hl, hl
	ret

sysdef	_kmalloc
; those are kinda special since they don't have many error, and already save and restore register
; you can call them directly if you wish
; may destroy a if there is an error (please note kernel routine should call kmalloc directly and handle error themselves)
	call	kmalloc
	ret	nc
	ld	a, ENOMEM
	jr	syserror

sysdef	_kfree
	call	kfree
	ret	nc
	ld	a, EFAULT
	jr	syserror

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
	jr	c, syserror
	add	hl, bc
; now check with sp
	push	hl
	ld	hl, -512
	add	hl, sp
	pop	bc
	or	a, a
	sbc	hl, bc
	jr	c, syserror
; all good, return the old break value
	ld	(iy+KERNEL_THREAD_BREAK), bc
	ex	de, hl
	ret

sysdef _pause
	call	kthread.suspend
	ld	a, EINTR
	jr	syserror
	
sysdef _usleep
; hl = time in ms, return 0 if sleept entirely or -1 with errno set if not
; EINTR, or EINVAL
	ld	iy, (kthread_current)
	di
	call	task_switch_sleep_ms
	call	task_yield
; we are back with interrupt
; this one is risky with interrupts, so disable them the time to do it
	di
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	ld	a, l
	or	a, h
	ld	a, EINTR
	jr	nz, syserror
	ei
	sbc	hl, hl
	ret

sysdef _getpid
; pid_t getpid()
; return value is register hl
	ld	hl, (kthread_current)
	ld	l, (hl)
	ld	h, 1
	mlt	hl
	ret
  
sysdef _getppid
; pid_t getppid()
; return value is register hl
	ld	hl, (kthread_current)
	ld	de, KERNEL_THREAD_PPID
	add	hl, de
	ld	e, (hl)
	ex	de, hl
	ret

sysdef _uadmin
; TODO : implement
; cmd, fn, mdep
	ret

; priority
sysdef _nice
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

sysdef _priv_unlock
; exemple, enable flash sequence and SHA256 port
	in0	a, ($06)
	set	2, a
	out0	($06), a
	ret

sysdef _priv_lock
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret

; TODO : put this in the certificate ?
; flash unlock and lock

sysdef _flash_unlock
flash.unlock:
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
	
sysdef _flash_lock
flash.lock:
	xor	a, a
	out0	($28), a
	in0	a, ($06)
	res	2, a
	out0	($06), a
	ret

sysdef _profil
profil:
; int profil(unsigned short *buf, size_t bufsiz, size_t offset, unsigned int scale);
; disable profiling if buf == NULL
;  Every virtual 10 milliseconds, the user's program counter (PC)
;  is examined: offset is subtracted and the result is multiplied by
;  scale and divided by 65536.  If the resulting value is less than
;  bufsiz, then the corresponding entry in buf is incremented
.syscall:
; TODO : to test
; hl : buf, de : bufsize, bc : offset, ix : scale
	ld	iy, (kthread_current)
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .reset
	push	hl
	ld	hl, 12
	call	kmalloc
	ld	a, ENOMEM
	ld	(iy+KERNEL_THREAD_PROFIL_STRUCTURE), hl
	jr	c, .error
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
	ld	(hl), 0
; set the profiler
	set	THREAD_PROFIL, (iy+KERNEL_THREAD_ATTRIBUTE)
	or	a, a
	sbc	hl, hl
	ret
.reset:
	res	THREAD_PROFIL, (iy+KERNEL_THREAD_ATTRIBUTE)
	ld	hl, (iy+KERNEL_THREAD_PROFIL_STRUCTURE)
	call	kfree
	or	a, a
	sbc	hl, hl
	ld	(iy+KERNEL_THREAD_PROFIL_STRUCTURE), hl
	ret
.error:
	pop	hl
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
	jr	nc, .restore
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
.restore:
	pop	hl
	pop	iy
	pop	af
	ret

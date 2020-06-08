define	KERNEL_MUTEX             0
define	KERNEL_MUTEX_SIZE        2
define	KERNEL_MUTEX_LOCK        0
define	KERNEL_MUTEX_LOCK_BIT    0
define	KERNEL_MUTEX_OWNER       1
define	KERNEL_MUTEX_MAGIC       $FE

macro tstdi
	ld	a, i
	di
	push	af
end macro

macro tstei
	pop	af
	jp	po, $+5
	ei
end macro

    
kmutex:
; POSIX errorcheck mutex implementation
.unlock:
	push	de
	ld	de, (kthread_current)
	inc	hl
	ld	a, (de)
	cp	a, (hl)
	dec	hl
; not current owning thread, you can't unlock ! (+ check if already locked, since it will be an toher thread value)
	ld	e, EPERM
	jr	nz, .errno
; go through init
	pop	de
	
.init:
	inc	hl
	ld	(hl), NULL
	dec	hl
	ld	(hl), KERNEL_MUTEX_MAGIC
	or	a, a
	sbc	hl, hl
	ret

.try_lock:
	push	de
	ld	e, EBUSY
	sra	(hl)
	jr	c, .errno
	jr	.lock_write
	
.lock:
; try lock fast
	push	de
	sra	(hl)
	ld	de, (kthread_current)
	jr	nc, .lock_write
; can't be acquired, already locked by us ?
	inc	hl
	ld	a, (de)
	cp	a, (hl)
	dec	hl
	ld	e, EDEADLK
	jr	z, .errno
; no, try again :
.lock_block:
; well, go to sleep a bit, 'kay ?
	call	task_yield
	sra	(hl)
	jr	c, .lock_block
; finally got it ! niiiiice	
.lock_write:
	ex	de, hl
	ld	l, (hl)
	ex	de, hl
	inc	hl
	ld	(hl), e
	dec	hl
	pop	de
	or	a, a
	sbc	hl, hl
	ret
; shared errno routine ;
.errno:
	push	iy
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), e
	or	a, a
	sbc	hl, hl
	ld	l, e
	pop	iy
	pop	de
	scf
	ret

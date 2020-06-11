define	KERNEL_MUTEX			0
define	KERNEL_MUTEX_SIZE		6
define	KERNEL_MUTEX_LOCK		0
define	KERNEL_MUTEX_LOCK_BIT		0
define	KERNEL_MUTEX_OWNER		1
define	KERNEL_MUTEX_LIST		2
define	KERNEL_MUTEX_LIST_COUNT		2
define	KERNEL_MUTEX_LIST_HEAD		3

define	KERNEL_MUTEX_MAGIC	$FE

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
	push	iy
	push	de
	ld	de, (kthread_current)
	inc	hl
	ld	a, (de)
	cp	a, (hl)
; not current owning thread, you can't unlock ! (+ check if already locked, since it will be an toher thread value)
	ld	e, EPERM
	jr	nz, .errno
; go through init
	inc	hl
	di
	call	klist.retire
	dec	hl
	ld	(hl), NULL
	dec	hl
	ld	(hl), KERNEL_MUTEX_MAGIC	; it's unlocked
; iy is thread_list or if z set, nothing
	lea	iy, iy-KERNEL_THREAD_LIST
	call	nz, task_switch_running
	ei
	pop	de
	pop	iy
	or	a, a
	sbc	hl, hl
	ret

.init:
	inc	hl
	ld	(hl), NULL
	dec	hl
	ld	(hl), KERNEL_MUTEX_MAGIC
	or	a, a
	sbc	hl, hl
	ret

.try_lock:
	push	iy
	push	de
	ld	e, EBUSY
	sra	(hl)
	jr	c, .errno
	jr	.lock_write
	
.lock:
; try lock fast
	push	iy
	push	de
	ld	iy, (kthread_current)
	sra	(hl)
	jr	nc, .lock_write
; can't be acquired, already locked by us ?
	inc	hl
	ld	a, (iy+KERNEL_THREAD_PID)
	cp	a, (hl)
	ld	e, EDEADLK
	jr	z, .errno
; no, try again
; we should dynamically boost thread priority owning the mutex based on the priority of waiting thread
; TODO
.lock_sleep:
; let's sleep
	di
	inc	hl
	ld	c, (iy+KERNEL_THREAD_PRIORITY)
	lea	iy, iy+KERNEL_THREAD_LIST
	call	klist.append
	lea	iy, iy-KERNEL_THREAD_LIST
	dec	hl
	dec	hl
.lock_block:
	di
	push	hl
	call	task_switch_interruptible
	call	task_yield
	pop	hl
	sra	(hl)
	jr	c, .lock_block
; finally got it ! niiiiice
.lock_write:
	inc	hl
	ld	a, (iy+0)
	ld	(hl), a
	pop	de
	pop	iy
	or	a, a
	sbc	hl, hl
	ret
; shared errno routine ;
.errno:
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_ERRNO), e
	or	a, a
	sbc	hl, hl
	ld	l, e
	pop	de
	pop	iy
	scf
	ret

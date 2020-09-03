define	KERNEL_MUTEX			0
define	KERNEL_MUTEX_SIZE		6
define	KERNEL_MUTEX_LOCK		0
define	KERNEL_MUTEX_LOCK_BIT		0
define	KERNEL_MUTEX_OWNER		1
define	KERNEL_MUTEX_LIST		2
define	KERNEL_MUTEX_LIST_COUNT		2
define	KERNEL_MUTEX_LIST_HEAD		3

define	KERNEL_MUTEX_MAGIC		$FE

macro	tsti
	ld	a, i
	di
	push	af
end	macro

macro	rsti
	pop	af
	jp	po, $+5
	ei
end	macro

atomic_rw:

define	KERNEL_ATOMIC_RW_SIZE		5
define	KERNEL_ATOMIC_RW_LOCK		0
define	KERNEL_ATOMIC_RW_WAIT_COUNT	1
define	KERNEL_ATOMIC_RW_WAIT_HEAD	2

define	KERNEL_ATOMIC_RW_MAGIC_READ	$00
define	KERNEL_ATOMIC_RW_MAGIC_WRITE	$FF

.lock_read:
	tsti
.lock_read_test:
	inc	(hl)
	jr	z, .rlock_wait
	rsti
	ret
	
.lock_write:
	tsti
.lock_write_test:
	ld	a, (hl)
	or	a, a
	jr	nz, .wlock_wait
	ld	(hl), $FF
	rsti
	ret

.unlock_read:
	tsti
	dec	(hl)
	jr	z, .unlock_notify
	rsti
	ret
	
.unlock_write:
	tsti
	ld	(hl), $00
.unlock_notify:
	inc	hl
	ld	a, (hl)
	inc	a
	jr	nz, .unlock_do_wake
	dec	hl
	rsti
	ret

.rlock_wait:
; make us wait on the lock
	dec	(hl)
	push	iy
	ld	iy, (kthread_current)
; add ourselves to lock structure
	ld	(iy+KERNEL_THREAD_LIST_DATA), KERNEL_ATOMIC_RW_MAGIC_READ
	inc	hl
	lea	iy, iy+KERNEL_THREAD_LIST_DATA
	call	kqueue.insert_tail
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
	dec	hl
	push	hl
	call	task_switch_interruptible
	pop	hl
	call	task_yield
	pop	iy
	di
	jr	.lock_read_test
	
.wlock_wait:
	push	iy
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_LIST_DATA), KERNEL_ATOMIC_RW_MAGIC_WRITE
	inc	hl
	lea	iy, iy+KERNEL_THREAD_LIST_DATA
	call	kqueue.insert_tail
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
	dec	hl
	push	hl
	call	task_switch_interruptible
	pop	hl
	call	task_yield
	pop	iy
	di
	jr	.lock_write_test
	
.unlock_do_wake:
; unqueue and wake thread while we dont have a WRITER thread
	push	iy
; grab the head and update
.unlock_do_loop:
	call	kqueue.retire_head
; m = no more to retire
	jp	m, .unlock_do_wake_exit
; iy is the thread
; first, wake it
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
	push	hl
	call	kthread.irq_resume
	pop	hl
	ld	a, (iy+KERNEL_THREAD_LIST_DATA)
	cp	a, KERNEL_ATOMIC_RW_MAGIC_WRITE	; stop at a writer
; TODO, optimize so we don't wake a writer if readers as been awake ?
	jr	nz, .unlock_do_loop
.unlock_do_wake_exit:
; no more thread or a blocker thread
	pop	iy
	dec	hl
	rsti
	jp	task_schedule

.init:
	push	de
	push	hl
	ld	(hl), $00
	inc	hl
	ld	(hl), $FF
	inc	hl
	ld	de, NULL
	ld	(hl), de
	pop	hl
	pop	de
	ret
	
atomic_op:
	ret

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

; atomic_rw structure : 5 bytes
define	KERNEL_ATOMIC_RW_SIZE		5
define	KERNEL_ATOMIC_RW_LOCK		0
define	KERNEL_ATOMIC_RW_WAIT_COUNT	1
define	KERNEL_ATOMIC_RW_WAIT_HEAD	2
define	KERNEL_ATOMIC_RW_MAGIC_READ	$00
define	KERNEL_ATOMIC_RW_MAGIC_WRITE	$FF

; mutex are quite similar : 8 bytes
define	KERNEL_ATOMIC_MUTEX_SIZE	8
define	KERNEL_ATOMIC_MUTEX_LOCK	0
define	KERNEL_ATOMIC_MUTEX_WAIT_COUNT	1
define	KERNEL_ATOMIC_MUTEX_WAIT_HEAD	2
define	KERNEL_ATOMIC_MUTEX_OWNER	5
define	KERNEL_ATOMIC_MUTEX_MAGIC	$FE

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

macro	rstiRET
	pop	af
	ret	po
	ei
	ret
end	macro

; TODO : crazily optimize all this segment please +++

atomic_rw:

.lock_read:
	tsti
.lock_read_test:
	inc	(hl)
	jr	z, .rlock_wait
	rstiRET
		
.lock_write:
	tsti
.lock_write_test:
	xor	a, a
	or	a, (hl)
	jr	nz, .wlock_wait
	ld	(hl), $FF
	rstiRET
	
.unlock_read:
	tsti
	dec	(hl)
	jr	z, .unlock_notify
	rstiRET
		
.unlock_write:
	tsti
	ld	(hl), $00
.unlock_notify:
	inc	hl
	ld	a, (hl)
	inc	a
	jr	nz, .unlock_do_wake
	dec	hl
	rstiRET
	
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
	ld	a, (hl)
	inc	a
	jr	z, .unlock_do_wake_exit
	inc	hl
	ld	iy, (hl)
	dec	hl
	call	kqueue.remove_head
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
	pop	af
	jp	pe, task_schedule
	ret

.init:
	ld	(hl), 0
	inc	hl
	ld	(hl), $FF
	inc	hl
	ld	(hl), 0
	inc	hl
	ld	(hl), 0
	inc	hl
	ld	(hl), 0
	dec	hl
	dec	hl
	dec	hl
	dec	hl
	ret
	
atomic_op:
	ret

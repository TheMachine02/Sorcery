; atomic_rw structure : 5 bytes
define	KERNEL_ATOMIC_RW_SIZE		5
define	KERNEL_ATOMIC_RW_LOCK		0
define	KERNEL_ATOMIC_RW_WAIT_COUNT	1
define	KERNEL_ATOMIC_RW_WAIT_HEAD	2
define	KERNEL_ATOMIC_RW_MAGIC_READ	$00	; or null
define	KERNEL_ATOMIC_RW_MAGIC_WRITE	$FF	; or any non zero

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

; TODO : crazily optimize all this segment please +++

atomic_rw:

.lock_read:
	di
	xor	a, a
	inc	(hl)
	call	z, .wait_read
	ei
	ret

.lock_write:
	di
	xor	a, a
	or	a, (hl)
	call	nz, .wait_write
; if arrive here, the lock is null, so dec it to make it = $FF
	dec	(hl)
	ei
	ret

.unlock_read:
	di
	dec	(hl)
	jr	z, .__unlock_slow_path
	ei
	ret

.unlock_write:
	di
	xor	a, a
	ld	(hl), a
.__unlock_slow_path:
	inc	hl
	ld	a, (hl)
	inc	a
	jr	nz, .wake
	dec	hl
	ei
	ret
	
; make us wait on the lock
.wait_read:
; restore first the lock
	dec	(hl)
.wait_write:
; get the return adress
	ex	(sp), iy
	pea	iy-5
	push	hl
	inc	hl
; add ourselves to lock structure
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_LIST_DATA), a
	lea	iy, iy+KERNEL_THREAD_LIST_DATA
	call	kqueue.insert_tail
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
; and switch to uninterruptible
	call	task_switch_uninterruptible
	pop	hl
	call	task_yield
	xor	a, a
; we were waked up if we are here, interrupt are on
; unwind stack to get the return adress and our saved iy
	pop	iy
	ex	(sp), iy
	di
; right here, we'll return exactly at the inc (hl) or the or a, (hl)
	ret

.wake:
; unqueue and wake thread while we dont have a WRITER thread
	push	bc
	ld	b, a
	push	iy
.__wake_waiter:
	inc	hl
	ld	iy, (hl)
	dec	hl
	call	kqueue.remove_head
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
	push	hl
	xor	a, a
	call	kthread.irq_resume
	pop	hl
; stop if the thread waked is a writer
; TODO, optimize so we don't wake a writer if readers as been awake ?
	ld	a, (iy+KERNEL_THREAD_LIST_DATA)
	or	a, a
	jr	nz, .__wake_done
	djnz	.__wake_waiter
.__wake_done:
	pop	iy
	pop	bc
; reschedule right now
	jp	task_schedule

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
	
atomic_mutex:

; please note :
; - one task can hold the mutex
; - only the owner can unlock the mutex.
; - Do not exit with a mutex held.
; - Do not use mutexes in irq or other interrupt disable area

.wait:
; signal to wait on the mutex
	push	ix
	push	iy
	push	af
	ld	iy, (kthread_current)
; save hl for later
.__wait_again:
	push	hl
	inc	hl
	lea	iy, iy+KERNEL_THREAD_LIST_DATA
; we delayed the critical section at our best
	di
	ld	a, (iy+KERNEL_THREAD_PRIORITY-KERNEL_THREAD_LIST_DATA)
; insert the node at the correct priority
	call	kqueue.insert_priority
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
; right here we should compare the arriving thread priority with the owner priority to alleviate priority inversion issue
	inc	hl
	inc	hl
	inc	hl
	inc	hl
	ld	ix, (hl)	; owner
; load priority of the current thread
	ld	a, (iy+KERNEL_THREAD_PRIORITY)
	sub	a, (ix+KERNEL_THREAD_PRIORITY)
; find a nice value to boost thread priority to be at least >= of the highest priority waiting thread
; if the result carry, the priority of waiter is > of owner. The diff *2 should be the nice value
	jr	nc, .__wait_switch
; TODO : save the previous (lowest) nice value
	add	a, a
	ld	(ix+KERNEL_THREAD_NICE), a
.__wait_switch:
	call	task_switch_uninterruptible
	pop	hl
	call	task_yield
; we are back, try to acquire the lock again
	sra	(hl)
	jr	c, .__wait_again
; mutex acquired, return
	pop	af
	pop	iy
	pop	ix
	ret

.unlock:
; unlock a mutex
; destroy a, bc
	di
	ld	(hl), $FE
	inc	hl
	ld	de, (kthread_current)
	ld	a, (de)
	cp	a, (hl)
; TODO broken, fix it	
	ld	a, (hl)
	inc	a
	jr	nz, .wake
	dec	hl
	ei
	ret
	
.wake:
; TODO : restore priority of owning thread (only if there is actual waiter)
; TODO : check if it is the correct owner
	push	iy
	inc	hl
	ld	iy, (hl)
	dec	hl
	call	kqueue.remove_head
	ei
	lea	iy, iy-KERNEL_THREAD_LIST_DATA
	push	hl
	call	kthread.resume
	pop	hl
	dec	hl
	pop	iy
	ret

.init:
	push	hl
	push	de
	push	bc
	ex	de, hl
	ld	hl, .init_data
	ld	bc, KERNEL_ATOMIC_MUTEX_SIZE
	ldir
	pop	bc
	pop	de
	pop	hl
	ret
	
.init_data:
 db	$FE, $FF, $00, $00, $00, $00, $00, $00

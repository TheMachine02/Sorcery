define	SIGEV_NONE			0
define 	SIGEV_SIGNAL			1
define	SIGEV_THREAD			2

define	SIGEV_SIZE			14
virtual	at 0
	SIGEV_SIGNOTIFY:	rb	1
	SIGEV_SIGNO:		rb	1
	SIGEV_VALUE:		rb	3	; actually a sigval
	SIGEV_NOTIFY_FUNCTION:	rb	3
	SIGEV_NOTIFY_ATTRIBUTE:	rb	3
	SIGEV_NOTIFY_THREAD:	rb	3	; pid, 1 byte
; padding, 2 bytes
	SIGEV_PADDING:		rb	2
end	virtual

define	TIMER_SIZE			22
virtual	at 0
	TIMER:
	TIMER_FLAGS:		rb	1
	TIMER_NEXT:		rb	3
	TIMER_PREVIOUS:		rb	3
	TIMER_COUNT:		rb	3
; here we have a pointer to a sigevent
	TIMER_SIGEV:
	TIMER_EV_SIGNOTIFY:	rb	1
	TIMER_EV_SIGNO:		rb	1
	TIMER_EV_VALUE:		rb	3	; actually a sigval
	TIMER_EV_NOTIFY_FUNCTION:	rb	3
	TIMER_EV_NOTIFY_ATTRIBUTE:	rb	3
	TIMER_EV_NOTIFY_THREAD:	rb	1	; pid, 1 byte
end	virtual
	
ktimer:
; TODO : use mem_cache for timer structure (

; please note, timer_next is still valid per timer queue
.notify_default = kthread.irq_resume

.set_time:
	ld	a, l
	dec	hl
	inc	h
	ld	l, a
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), hl
	ret

.get_time:
	ld	iy, (kthread_current)
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	ld	a, l
	inc	hl
	dec	h
	ld	l, a
	ret
	
; it timer attached to thread, used by sleep() and alarm() ;
.itset:
; create a timer attached to the current thread
; hl as a seig_ev structure (
; EV_SIGNOTIFY		$0
; EV_SIGNO		$1
; EV_NOTIFY_FUNCTION	$2
; EV_VALUE		$5
; pass NULL for default callback, ie resume thread
; de is timer count
; bc is ev value
	ld	iy, (kthread_current)
	lea	iy, iy+KERNEL_THREAD_TIMER
.create:
; iy = timer structure
	di
	ld	hl, (iy+TIMER_COUNT)
	ld	a, h
	or	a, l
	jr	nz, .create_failed
	ld	(iy+TIMER_COUNT), de
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .create_default
	lea	de, iy+TIMER_SIGEV
	ld	bc, SIGEV_SIZE
	ldir
	jr	.create_arm
.create_default:
; direct thread waking is the *faster* method than a costly SIGCONT
	ld	(iy+TIMER_EV_SIGNOTIFY), SIGEV_THREAD
	ld	hl, .notify_default
	ld	(iy+TIMER_EV_NOTIFY_FUNCTION), hl
.create_arm:
	ld	hl, ktimer_queue
	call	kqueue.insert_head
; will meet "or a, a" (line 23), so carry is null
	ei
	sbc	hl, hl
	ret
.create_failed:
	ld	a, EINVAL
	jp	user_error
	
.itreset:
; delete (or disarm) the current timer of the thread
	ld	iy, (kthread_current)
	lea	iy, iy+KERNEL_THREAD_TIMER
.delete:
	di
	ld	hl, (iy+TIMER_COUNT)
	ld	a, l
	or	a, h
	jr	z, .reset_errno
	ld	hl, ktimer_queue
	call	kqueue.remove_head
; won't modify Carry
	sbc	hl, hl
	ld	(iy+TIMER_COUNT), hl
	ei
	ret
.reset_errno:
	ei
; 	ld	(iy+KERNEL_THREAD_ERRNO), EINVAL
	dec	hl
	ret

sysdef _alarm
; TODO verify correct * invocation *
.alarm:
	ld	iy, (kthread_current)
	lea	iy, iy+KERNEL_THREAD_TIMER
	tsti
	ld	de, (iy+TIMER_COUNT)
	ld	a, e
	or	a, d
	jr	nz, .alarm_disarm
; convert second to jiffies
	ld	e, TIME_S_TO_JIFFIES
	ld	d, l
	ld	l, e
	mlt	de
	mlt	hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
if CONFIG_CRYSTAL_DIVISOR = 0
	add	hl, hl
end if
; add timer
; adapt to a pseudo 16 bits counter
	ld	e, l
	dec	hl
	inc	h
	ld	l, e
	ld	(iy+TIMER_COUNT), hl
	ld	(iy+TIMER_EV_SIGNOTIFY), SIGEV_SIGNAL
	ld	(iy+TIMER_EV_SIGNO), SIGALRM
	ld	hl, ktimer_queue
	call	kqueue.insert_head
	pop	af
	ret	po
	ei
	ret
.alarm_disarm:
	ld	hl, ktimer_queue
	call	kqueue.remove_head
; carry wasn't modified
	sbc	hl, hl
	ld	(iy+TIMER_COUNT), hl
	pop	af
	ret	po
	ei
	ret

.trigger:
; remove the timer from the queue
	ld	hl, ktimer_queue
	call	kqueue.remove_head
; switch based on what we should do
	ld	a, (iy+TIMER_EV_SIGNOTIFY)
	dec	a
	ret	m
	jr	nz, .crystal_thread
.crystal_signal:
	ld	hl, (iy+TIMER_EV_NOTIFY_THREAD)
	ld	c, (hl)
	ld	a, (iy+TIMER_EV_SIGNO)
	jp	signal.kill
.crystal_thread:
; callback
	push	iy
	push	bc
	pea	iy+TIMER_EV_VALUE
	call	.crystal_call
	pop	hl
	pop	bc
	pop	iy
	ret
.crystal_call:
	ld	hl, (iy+TIMER_EV_NOTIFY_FUNCTION)
	ld	iy, (iy+TIMER_EV_NOTIFY_THREAD)
	xor	a, a
	jp	(hl)


	
;        *  timer_create(): Create a timer.
; 
;        *  timer_settime(2): Arm (start) or disarm (stop) a timer.
; 
;        *  timer_gettime(2): Fetch the time remaining until the next
;           expiration of a timer, along with the interval setting of the
;           timer.
; 
;        *  timer_getoverrun(2): Return the overrun count for the last timer
;           expiration.
; 
;        *  timer_delete(2): Disarm and delete a timer.

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

sysdef	_timer_delete
; int timer_delete(timer_t timerid);
; check we have a RAM adress
	ld	bc, $D07FFF
	or	a, a
	sbc	hl, bc
	ex	de, hl
	ld	hl, -EINVAL
	ret	c
	ex	de, hl
	add	hl, bc
	push	hl
	pop	iy
	ld	a, (iy+TIMER_HASH)
	ld	c, TIMER_REDZONE
	sub	a, c
	ex	de, hl
	scf
	ret	nz
	di
; disarm the timer & then delete it
	ld	hl, ktimer_queue
	call	kqueue.remove_head
	ld	hl, (iy+TIMER_SIGEV)
	or	a, a
	sbc	hl, bc
	add	hl, bc
	call	nz, kmem.cache_free
	or	a, a
	sbc	hl, hl
	ret
	
sysdef	_timer_create
; int timer_create(clockid_t clockid, struct sigevent *restrict sevp, timer_t *restrict timerid)
; we have hl as the clockid wanted, de is sigevent pointer, and timerid is the buffer were we will store id
	ld	a, l
	cp	a, CLOCK_MONOTONIC
	ld	hl, -ENOTSUP
	scf
	ret	nz
; de and bc are important to keep right now
; sanitize input
; sigev_notify, sigev_signo and both timer_t and sigevent are not null
	ex	de, hl
	add	hl, bc
	or	a, a
	sbc	hl, bc
	ex	de, hl
	ld	hl, -EINVAL
	scf
	ret	z
	push	de
	pop	ix
	ld	a, (ix+SIGEV_SIGNO)
	cp	a, SIGMAX
	ccf
	ret	c
	ld	a, (ix+SIGEV_SIGNOTIFY)
	cp	a, SIGEV_THREAD+1
	ccf
	ret	c
	push	bc
	pop	de
	ex	de, hl
	add	hl, bc
	or	a, a
	sbc	hl, bc
	ex	de, hl
	ld	hl, -EFAULT
	scf
	ret	z
	ld	hl, kmem_cache_s16
	call	kmem.cache_alloc
	push	hl
	pop	iy
	ld	hl, -ENOMEM
	ret	c
	ex	de, hl
	ld	(hl), iy
	ld	(iy+TIMER_SIGEV), ix
	ld	(iy+TIMER_HASH), TIMER_REDZONE
	ld	hl, (kthread_current)
	ld	a, (hl)
	ld	(iy+TIMER_INTERNAL_THREAD), a
	or	a, a
	sbc	hl, hl
	ret

sysdef	_timer_getoverrun
; int timer_getoverrun(timer_t timerid);
	ld	bc, $D07FFF
	or	a, a
	sbc	hl, bc
	ex	de, hl
	ld	hl, -EINVAL
	ret	c
	ex	de, hl
	add	hl, bc
	push	hl
	pop	iy
	ld	a, (iy+TIMER_HASH)
	ld	c, TIMER_REDZONE
	sub	a, c
	ex	de, hl
	scf
	ret	nz
	di
	or	a, a
	sbc	hl, hl
	ld	l, (iy+TIMER_INTERNAL_OVERRUN)
	ret

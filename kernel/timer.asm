define	SIGEV_NONE			0
define 	SIGEV_SIGNAL			1
define	SIGEV_THREAD			2

define	SIGEV_SIZE			16
virtual	at 0
	SIGEV_SIGNOTIFY:		rb	1
	SIGEV_SIGNO:			rb	1
	SIGEV_VALUE:			rb	3	; actually a sigval (3 bytes)
	SIGEV_NOTIFY_FUNCTION:		rb	3
	SIGEV_NOTIFY_ATTRIBUTE:		rb	3
	SIGEV_NOTIFY_THREAD:		rb	3	;
; padding, 2 bytes
	SIGEV_PADDING:			rb	2
end	virtual

define	TIMER_SIZE			16
define	TIMER_REDZONE			$CF
virtual	at 0
	TIMER:
	TIMER_HASH:			rb	1
	TIMER_NEXT:			rb	3
	TIMER_PREVIOUS:			rb	3
	TIMER_INTERVAL:			rb	3
	TIMER_COUNT:			rb	2
	TIMER_INTERNAL_THREAD:		rb	1	; owner of the timer, pid
; here we have a pointer to a sigevent structure
	TIMER_SIGEV:			rb	3
end	virtual

define	ITIMER_REAL	0
define	ITIMER_VIRTUAL	1
define	ITIMER_PROF	2


; struct itimerval {
;   struct timeval it_interval; /* valeur suivante */
;   struct timeval it_value;    /* valeur actuelle */
; };
; 
; struct timeval {
;   long tv_sec;                /* secondes        */
;   long tv_usec;               /* micro secondes  */
; };

ktimer:

.itimer_sys:
 db	SIGEV_SIGNAL
 db	SIGALRM
 dl	0
 dl	0
 dl	0
 dl	0
 
.itimer_sleep:
 db	SIGEV_SIGNAL
 db	SIGCONT
 dl	0
 dl	0
 dl	0
 dl	0

; TODO : convert ticks from direct timer value to actual itimerval structure
sysdef	_setitimer
; setitimer(int which, const struct itimerval *restrict new_value, struct itimerval *restrict old_value);
.setitimer:
	ld	a, l
	or	a, a
	ld	hl, -EINVAL
	scf
	ret	nz
	ld	iy, (kthread_current)
	lea	iy, iy+KERNEL_THREAD_ITIMER
; check if de or bc is null
	sbc	hl, hl
	adc	hl, de
	ld	hl, -EFAULT
	scf
	ret	z
	sbc	hl, hl
	adc	hl, bc
	ld	hl, -EFAULT
	scf
	ret	z
; check if new value is null, if so disarm the timer
	ex	de, hl
	ld	a, (hl)
	inc	hl
	or	a, (hl)
	dec	hl
	ex	de, hl
	jr	z, .__setitimer_disarm
; arm the timer, enter critical interrupt space since we might modify the *thread timer*
	di
	ld	hl, .itimer_sys
	ld	(iy+TIMER_SIGEV), hl
; use de as new value buffer and bc as copy of old values
	push	de
	push	bc
	pop	de
	lea	hl, iy+TIMER_INTERVAL
	ld	bc, 5
	ldir
	pop	de
	lea	hl, iy+TIMER_INTERVAL
	ex	de, hl
	ld	c, 5
	ldir
	ld	a, (iy-KERNEL_THREAD_ITIMER+KERNEL_THREAD_PID)
	ld	(iy+TIMER_INTERNAL_THREAD), a
	ld	hl, ktimer_queue
	call	kqueue.insert_head
	or	a, a
	sbc	hl, hl
	ret
.__setitimer_disarm:
	di
	ld	hl, ktimer_queue
	call	kqueue.remove_head
	or	a, a
	sbc	hl, hl
	ld	(iy+TIMER_COUNT), l
	ld	(iy+TIMER_COUNT+1), h
	ld	(iy+TIMER_INTERVAL), hl
	ret 

; TODO : convert ticks from direct timer value to actual itimerval structure
sysdef	_getitimer
; int getitimer(int which, struct itimerval *curr_value);	
.getitimer:
	ld	a, l
	or	a, a
	ld	hl, -EINVAL
	scf
	ret	nz
	ld	iy, (kthread_current)
; check if de is null
	sbc	hl, hl
	adc	hl, de
	ld	hl, -EFAULT
	ret	z
; to keep a consistant reading, disable interrupts
	di
	lea	hl, iy+TIMER_INTERVAL + KERNEL_THREAD_ITIMER
	ld	bc, 5
	ldir
	or	a, a
	sbc	hl, hl
	ret

sysdef _alarm
.alarm:
	ld	iy, (kthread_current)
	lea	iy, iy+KERNEL_THREAD_ITIMER
	ld	a, l
	or	a, h
	jr	nz, .__setitimer_disarm
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
; write timer
	di
	ld	(iy+TIMER_COUNT), l
	ld	(iy+TIMER_COUNT+1), h
	or	a, a
	sbc	hl, hl
	ld	(iy+TIMER_INTERVAL), hl
	ld	hl, .itimer_sys
	ld	(iy+TIMER_SIGEV), hl
	ld	a, (iy-KERNEL_THREAD_ITIMER+KERNEL_THREAD_PID)
	ld	(iy+TIMER_INTERNAL_THREAD), a
	ld	hl, ktimer_queue
	jp	kqueue.insert_head

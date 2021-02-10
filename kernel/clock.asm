define	CLOCKS_PER_SEC	32768

define	TMS_UTIME	0
define	TMS_STIME	3
define	TMS_CUTIME	6
define	TMS_CSTIME	9

sysdef _clock
clock:
	ld	iy, (kthread_current)
	ld	hl, (iy+KERNEL_THREAD_TIME)
	or	a, a
	ret

sysdef _times
; struct tms {
; clock_t tms_utime;  /* user time */
; clock_t tms_stime;  /* system time */
; clock_t tms_cutime; /* user time of children */
; clock_t tms_cstime; /* system time of children */
; };
times:
; hl = buffer
	add	hl, de
	or	a, a
	sbc	hl, de
	ld	a, EFAULT
	jp	z, syserror
	ld	bc, NULL
	ld	iy, (kthread_current)
	ld	de, (iy+KERNEL_THREAD_TIME)
	push	de
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
; kernel time is not maintained, so NULL
	ld	(hl), bc
	inc	hl
	inc	hl
	inc	hl
; child time is valid only when the thread *waited* on the child
	ld	de, (iy+KERNEL_THREAD_TIME_CHILD)
	ld	(hl), de
	inc	hl
	inc	hl
	inc	hl
	ld	(hl), bc
	pop	hl
	or	a, a
	ret
	
sysdef _time
time:
; int time(time_t* time);
; get the current time since epoch 00:00:00 GMT januray 1, 1970
	ret
	
sysdef _stime
stime:
; stime() sets the system’s idea of the time and date. Time, pointed to by t, is measured in seconds from 00:00:00 GMT January 1, 1970. stime() may only be executed by the superuser. 
; int stime(time_t time)
	ret

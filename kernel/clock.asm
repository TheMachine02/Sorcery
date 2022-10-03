define	CLOCKS_PER_SEC	32768

virtual	at 0
	TMS_UTIME:	rb	3
	TMS_STIME:	rb	3
	TMS_CUTIME:	rb	3
	TMS_CSTIME:	rb	3
end	virtual

; (div/32768)*1000*16
; (32768/div)/1000*256

if CONFIG_CRYSTAL_DIVISOR = 3
	define	TIME_JIFFIES_TO_MS		153
	define	TIME_MS_TO_JIFFIES		27
	define	TIME_S_TO_JIFFIES		104
else if CONFIG_CRYSTAL_DIVISOR = 2
	define	TIME_JIFFIES_TO_MS		106
	define	TIME_MS_TO_JIFFIES		38
	define	TIME_S_TO_JIFFIES		150
else if CONFIG_CRYSTAL_DIVISOR = 1
	define	TIME_JIFFIES_TO_MS		75
	define	TIME_MS_TO_JIFFIES		54
	define	TIME_S_TO_JIFFIES		213
else if CONFIG_CRYSTAL_DIVISOR = 0
	define	TIME_JIFFIES_TO_MS		36
	define	TIME_MS_TO_JIFFIES		113
	define	TIME_S_TO_JIFFIES		222
end if

sysdef _clock
clock:
	ld	iy, (kthread_current)
	ld	hl, (iy+KERNEL_THREAD_TIME)
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
	jr	z, .__times_error
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
	ret
.__times_error:
	ld	hl, -EFAULT
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
	call	user_perm
	ret

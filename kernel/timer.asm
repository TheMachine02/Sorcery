define	SIGEV_NONE			0
define 	SIGEV_SIGNAL			1
define	SIGEV_THREAD			2

define	SIGEVENT_SIZE			12
define	SIGEVENT			$0
define	SIGEV_SIGNOTIFY			$0
define	SIGEV_SIGNO			$1
define	SIGEV_NOTIFY_FUNCTION		$2
define	SIGEV_NOTIFY_THREAD		$5
define	SIGEV_VALUE			$8
; uint8_t + prt

define	TIMER				$0
define	TIMER_FLAGS			$0
define	TIMER_NEXT			$1
define	TIMER_PREVIOUS			$4
define	TIMER_COUNT			$7
define	TIMER_SIGEVENT			$A
define	TIMER_EV_SIGNOTIFY		$A
define	TIMER_EV_SIGNO			$B
define	TIMER_EV_NOTIFY_FUNCTION	$C
define	TIMER_EV_NOTIFY_THREAD		$F
define	TIMER_EV_VALUE			$12
; uint8_t + prt
define	TIMER_SIZE			22

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
 
klocal_timer:

.init:
	di
	ld	hl, klocal_timer_queue
	ld	de, NULL
	ld	(hl), e
	inc	hl
	ld	(hl), de
	ret

; please note, timer_next is still valid per timer queue
.notify_default = kthread.resume

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
	lea	de, iy+TIMER_SIGEVENT
	ld	bc, SIGEVENT_SIZE
	ldir
	jr	.create_arm
.create_default:
; direct thread waking is the *faster* method than a costly SIGCONT
	ld	(iy+TIMER_EV_SIGNOTIFY), SIGEV_THREAD
	ld	hl, .notify_default
	ld	(iy+TIMER_EV_NOTIFY_FUNCTION), hl
.create_arm:
	ld	hl, klocal_timer_queue
	call	kqueue.insert_head
; will meet "or a, a" (line 23), so carry is null
	ei
	sbc	hl, hl
	ret
.create_failed:
	ei
	ld	(iy+KERNEL_THREAD_ERRNO), EINVAL
	scf
	sbc	hl, hl
	ret
	
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
	ld	hl, klocal_timer_queue
	call	kqueue.remove_head
; won't modify Carry
	sbc	hl, hl
	ld	(iy+TIMER_COUNT), hl
	ei
	ret
.reset_errno:
	ei
	ld	(iy+KERNEL_THREAD_ERRNO), EINVAL
	scf
	sbc	hl, hl
	ret
	
.itget:
	ld	iy, (kthread_current)
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	ret

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
	ld	(iy+TIMER_COUNT), hl
	ld	(iy+TIMER_EV_SIGNOTIFY), SIGEV_SIGNAL
	ld	(iy+TIMER_EV_SIGNO), SIGALRM
	ld	hl, klocal_timer_queue
	call	kqueue.insert_head
	pop	af
	ret	po
	ei
	ret
.alarm_disarm:
	ld	hl, klocal_timer_queue
	call	kqueue.remove_head
; carry wasn't modified
	sbc	hl, hl
	ld	(iy+TIMER_COUNT), hl
	pop	af
	ret	po
	ei
	ret

ktimer:
.crystal_wake:
; remove the timer from the queue
	ld	hl, klocal_timer_queue
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
	jp	(hl)


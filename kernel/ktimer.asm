define	SIGEV_NONE			0
define 	SIGEV_SIGNAL			1
define	SIGEV_THREAD			2

define	SIGEVENT			$0
define	SIGEVENT_SIZE			$8
define	SIGEV_SIGNOTIFY			$0
define	SIGEV_SIGNO			$1
define	SIGEV_NOTIFY_FUNCTION		$2
define	SIGEV_VALUE			$5

define	TIMER				$0
define	TIMER_COUNT			$0
define	TIMER_NEXT			$3
define	TIMER_PREVIOUS			$6
define	TIMER_OWNER			$9
define	TIMER_SIGEVENT			$C
define	TIMER_EV_SIGNOTIFY		$C
define	TIMER_EV_SIGNO			$D
define	TIMER_EV_NOTIFY_FUNCTION	$E
define	TIMER_EV_VALUE			$11
define	TIMER_SIZE			20

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

; timer queue
define	klocal_timer_queue		$D00300
define 	klocal_timer_size		$D00300
define	klocal_timer_current		$D00301
 
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

; it timer * attached to thread, used by sleep() and alarm() ;

.itset:
; will be better to actually create a structure, so multiple timer could be attached to a thread
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
	di
	ld	hl, (iy+TIMER_COUNT)
	ld	a, h
	or	a, l
	jr	nz, .itcreate_failed
	ld	(iy+TIMER_COUNT), de
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .itcreate_default
	lea	de, iy+TIMER_SIGEVENT
	ld	bc, SIGEVENT_SIZE
	ldir
	jr	.itcreate_arm
.itcreate_default:
; direct thread waking is the *faster* method than a costly SIGCONT
	ld	a, SIGEV_THREAD
	ld	(iy+TIMER_EV_SIGNOTIFY), a
	ld	hl, .notify_default
	ld	(iy+TIMER_EV_NOTIFY_FUNCTION), hl
.itcreate_arm:
	call	.insert
	ei
	or	a, a
	sbc	hl, hl
	ret
.itcreate_failed:
	ei
	ld	a, EINVAL
	ld	(iy+KERNEL_THREAD_ERRNO), a
	scf
	sbc	hl, hl
	ret
	
.itreset:
; delete (or disarm) the current timer of the thread
	ld	iy, (kthread_current)
	lea	iy, iy+KERNEL_THREAD_TIMER
	di
	ld	hl, (iy+TIMER_COUNT)
	ld	a, l
	or	a, h
	jr	z, .itreset_errno
	call	.remove
	ld	hl, NULL
	ld	(iy+TIMER_COUNT), hl
	ei
	ret
.itreset_errno:
	ei
	ld	a, EINVAL
	ld	(iy+KERNEL_THREAD_ERRNO), a
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
	di
	ld	de, (iy+TIMER_COUNT)
	ld	a, e
	or	a, d
	jr	nz, .alarm_disarm
; convert second to jiffies
	ld	e, TIME_S_TO_JIFFIES
	ld	d, l
	mlt	de
	ld	l, TIME_S_TO_JIFFIES
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
	ld	a, SIGEV_SIGNAL
	ld	(iy+TIMER_EV_SIGNOTIFY), a
	ld	a, SIGALRM
	ld	(iy+TIMER_EV_SIGNO), a
	call	.insert
	ei
	ret
.alarm_disarm:
	call	.remove
	ld	hl, NULL
	ld	(iy+TIMER_COUNT), hl
	ei
	ret
	
.insert:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; update queue_current to inserted node
; inplace insert of the node
	ld	hl, klocal_timer_queue
	ld	a, (hl)
	inc	(hl)
	or	a, a
	jr	z, .create_queue
	push	ix
	inc	hl
	ld	ix, (hl)
	ld	(hl), iy
	ld	hl, (ix+TIMER_NEXT)
	ld	(iy+TIMER_PREVIOUS), ix
	ld	(iy+TIMER_NEXT), hl
	ld	(ix+TIMER_NEXT), iy
	push	hl
	pop	ix
	ld	(ix+TIMER_PREVIOUS), iy
	pop	ix
	ret
.create_queue:
	inc	hl
	ld	(hl), iy
	ld	(iy+TIMER_PREVIOUS), iy
	ld	(iy+TIMER_NEXT), iy
	ret

; please, be sure of what you remove
.remove:
	ld	hl, klocal_timer_queue
; 	ld	a, (hl)
; 	or	a, a
; 	jr	z, .null_queue
	dec	(hl)
	jr	z, .null_queue
	push	iy
	push	ix
	ld	ix, (iy+TIMER_NEXT)
	ld	iy, (iy+TIMER_PREVIOUS)
	ld	(ix+TIMER_PREVIOUS), iy
	ld	(iy+TIMER_NEXT), ix
	inc	hl
	ld	(hl), iy
	pop	ix
	pop	iy
	ret
.null_queue:
	inc	hl
	ld	de, NULL
	ld	(hl), de
	ret

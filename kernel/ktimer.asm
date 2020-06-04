define	SIGEV_NONE		0
define 	SIGEV_SIGNAL		1
define	SIGEV_THREAD		2

define	SIGEVENT		$0
define	SIGEVENT_SIZE		$5
define	SIGEV_SIGNOTIFY		$0
define	SIGEV_SIGNO		$1
define	SIGEV_NOTIFY_FUNCTION	$2

; (div/32768)*1000*16
; (32768/div)/1000*256

if CONFIG_CRYSTAL_DIVISOR = 3
	define	TIME_JIFFIES_TO_MS		153
	define	TIME_MS_TO_JIFFIES		27
else if CONFIG_CRYSTAL_DIVISOR = 2
	define	TIME_JIFFIES_TO_MS		106
	define	TIME_MS_TO_JIFFIES		38
else if CONFIG_CRYSTAL_DIVISOR = 1
	define	TIME_JIFFIES_TO_MS		75
	define	TIME_MS_TO_JIFFIES		54
else
	define	TIME_JIFFIES_TO_MS		36
	define	TIME_JIFFIES_TO_MS		113
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

.create:
; create a timer attached to the current thread
; hl as a seig_ev structure (
; EV_SIGNOTIFY		$0
; EV_SIGNO		$1
; EV_NOTIFY_FUNCTION	$2
; pass NULL for default callback, ie resume thread
; de is timer count
	ld	iy, (kthread_current)
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), de
	add	hl, de
	or	a, a
	sbc	hl, de
	jr	z, .create_default
	lea	de, iy+KERNEL_THREAD_TIMER_SIGEVENT
	ld	bc, SIGEVENT_SIZE
	ldir
	jr	.create_arm
.create_default:
; direct thread waking is the *faster* method than a costly SIGCONT
	ld	a, SIGEV_THREAD
	ld	(iy+KERNEL_THREAD_TIMER_EV_SIGNOTIFY), a
	ld	hl, .notify_default
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION), hl
.create_arm:
	tstdi
	call	.insert
	tstei
	ret
	
.delete:
; delete (or disarm) the current timer of the thread
	ld	iy, (kthread_current)
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	ld	a, l
	or	a, h
	ret	z
	tstdi
	call	.remove
	tstei
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
	ld	hl, (ix+KERNEL_THREAD_TIMER_NEXT)
	ld	(iy+KERNEL_THREAD_TIMER_PREVIOUS), ix
	ld	(iy+KERNEL_THREAD_TIMER_NEXT), hl
	ld	(ix+KERNEL_THREAD_TIMER_NEXT), iy
	push	hl
	pop	ix
	ld	(ix+KERNEL_THREAD_TIMER_PREVIOUS), iy
	pop	ix
	ret
.create_queue:
	inc	hl
	ld	(hl), iy
	ld	(iy+KERNEL_THREAD_TIMER_PREVIOUS), iy
	ld	(iy+KERNEL_THREAD_TIMER_NEXT), iy
	ret

.remove:
	ld	hl, klocal_timer_queue
	ld	a, (hl)
	or	a, a
	jr	z, .null_queue
	dec	(hl)
	push	iy
	push	ix
	ld	ix, (iy+KERNEL_THREAD_TIMER_NEXT)
	ld	iy, (iy+KERNEL_THREAD_TIMER_PREVIOUS)
	ld	(ix+KERNEL_THREAD_TIMER_PREVIOUS), iy
	ld	(iy+KERNEL_THREAD_TIMER_NEXT), ix
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

task_add_timer:
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), hl
	ld	a, SIGEV_THREAD
	ld	(iy+KERNEL_THREAD_TIMER_EV_SIGNOTIFY), a
	ld	hl, klocal_timer.notify_default
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION), hl
	jr	klocal_timer.insert

task_delete_timer:
	ld	hl, (iy+KERNEL_THREAD_TIMER_COUNT)
	ld	a, l
	or	a, h
	ret	z	; can't disable, already disabled!
	jr	klocal_timer.remove

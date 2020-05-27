define	SIGEV_NONE			0
define 	SIGEV_SIGNAL			1
define	SIGEV_THREAD			2

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

.create:
	ld	iy, (kthread_current)
	ld	hl, .notify_default
	ld	(iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION), hl
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), a
	tstdi
	ld	hl, klocal_timer_queue
	call	.insert
	tstei
	ret
	
.delete:
	ld	iy, (kthread_current)
	ld	a, (iy+KERNEL_THREAD_TIMER_COUNT)
	or	a, a
	ret	z
	tstdi
	ld	hl, klocal_timer_queue
	call	.remove
	tstei
	ret

; please note, timer_next is still valid per timer queue
.notify_default = kthread.resume
	
; WITHIN kinterrupt.asm ;
; .local_timer_call:
; 	ld	hl, (iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION)
; 	jp	(hl)
; 	
; .local_timer:
; ; schedule jiffies timer first ;
; 	ld	hl, klocal_timer_queue
; 	ld	a, (hl)
; 	or	a, a
; 	jr	z, .schedule
; 	inc	hl
; ; this is first thread with a timer
; 	ld	iy, (hl)
; 	ld	b, a
; .local_timer_queue:
; 	dec	(iy+KERNEL_THREAD_TIMER_COUNT)
; 	call	z, .local_timer_call
; 	ld	iy, (iy+KERNEL_THREAD_TIMER_NEXT)
; 	djnz	.local_timer_queue

; STRICTLY THE SAME ROUTINE AS QUEUE, BUT WITH AN DIFFERENT OFFSET ;
; speed reason, todo, maybe optimize thos routine & make them accept varying offset ? ;

.insert:
; iy is node to insert
; hl is queue pointer (count, queue_current)
; update queue_current to inserted node
; inplace insert of the node
; return 
	ld	a, (hl)
	inc	(hl)
	or	a, a
	jr	z, .create_queue
	push	ix
; prev_node.next = new_node
; next_node.prev = new_node
; new_node.prev = prev_node
; new_node.next = next_node
; queue_current = iy
	inc	hl
	ld	ix, (hl)
	ld	(hl), iy
	dec	hl
; ix = prev_node
	push	hl
	ld	hl, (ix+KERNEL_THREAD_TIMER_NEXT)
; de = next_node
	ld	(iy+KERNEL_THREAD_TIMER_PREVIOUS), ix
	ld	(iy+KERNEL_THREAD_TIMER_NEXT), hl
	ld	(ix+KERNEL_THREAD_TIMER_NEXT), iy
; (de+KERNEL_THREAD_TIMER_PREVIOUS)=iy
	ex	(sp), hl
	pop	ix
	ld	(ix+KERNEL_THREAD_TIMER_PREVIOUS), iy
	pop	ix
	ret
.create_queue:
	inc	hl
	ld	(hl), iy
	dec	hl
	ld	(iy+KERNEL_THREAD_TIMER_PREVIOUS), iy
	ld	(iy+KERNEL_THREAD_TIMER_NEXT), iy
	ret

.remove:
; iy is node to remove
; update queue_current to NULL if count=0 or previous node of the removed node
; hl is queue pointer (count, queue_current)
	ld	a, (hl)
	or	a, a
	jr	z, .null_queue
	dec	(hl)
	push	iy
	push	ix
	ld	ix, (iy+KERNEL_THREAD_TIMER_NEXT)
	ld	iy, (iy+KERNEL_THREAD_TIMER_PREVIOUS)
; next_node.prev=prev_node
; prev_node.next=next_node
	ld	(ix+KERNEL_THREAD_TIMER_PREVIOUS), iy
	ld	(iy+KERNEL_THREAD_TIMER_NEXT), ix
	inc	hl
	ld	(hl), iy
	dec	hl
	pop	ix
	pop	iy
	ret
.null_queue:
	inc	hl
	ld	de, NULL
	ld	(hl), de
	dec	hl
	ret

; timer queue
define	klocal_timer_queue		0xD00300
define 	klocal_timer_size		0xD00300
define	klocal_timer_current		0xD00301
 
klocal_timer:

.init:
	ld	hl, klocal_timer_queue
	ld	de, NULL
	ld	(hl), e
	inc	hl
	ld	(hl), de
	ret

.create:
	tstdi
	ld	iy, (kthread_current)
	ld	hl, .callback_default
	ld	(iy+KERNEL_THREAD_TIMER_CALLBACK), hl
	ld	(iy+KERNEL_THREAD_TIMER_COUNT), a
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

.callback_default:
; please note, timer_next is still valid per timer queue
	ld	hl, klocal_timer_queue
	call	.remove
	jp	kthread.resume
	
; WITHIN kinterrupt.asm ;
; .local_timer_call:
; 	ld	hl, (iy+KERNEL_THREAD_TIMER_CALLBACK)
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
	inc	(hl)
	dec	(hl)
	jr	z, .create_queue
	inc	(hl)
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
	inc	(hl)
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
	dec	(hl)
	jr	z, .null_queue
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
	push	de
	inc	hl
	ld	de, NULL
	ld	(hl), de
	dec	hl
	pop	de
	ret

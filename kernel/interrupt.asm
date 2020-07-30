define	KERNEL_INTERRUPT_STATUS_RAW		$F00000
define	KERNEL_INTERRUPT_ENABLE_MASK		$F00004
define	KERNEL_INTERRUPT_ACKNOWLEDGE		$F00008
define	KERNEL_INTERRUPT_SIGNAL_LATCH		$F0000C
define	KERNEL_INTERRUPT_STATUS_MASKED		$F00014
define	KERNEL_INTERRUPT_REVISION		$F00050
define	KERNEL_INTERRUPT_REVISION_BASE		$010900
define	KERNEL_INTERRUPT_EARLY_SWITCH		$D177BA

define	KERNEL_INTERRUPT_ON			00000001b
define	KERNEL_INTERRUPT_TIMER1			00000010b
define	KERNEL_INTERRUPT_TIMER2			00000100b
define	KERNEL_INTERRUPT_TIMER3			00001000b
define	KERNEL_INTERRUPT_TIMER_OS		00010000b
define	KERNEL_INTERRUPT_KEYBOARD		00000100b
define	KERNEL_INTERRUPT_LCD			00001000b
define	KERNEL_INTERRUPT_RTC			00010000b
define	KERNEL_INTERRUPT_USB			00100000b

define	KERNEL_INTERRUPT_CACHE			$D00A00

kinterrupt:
.init:
	di
	im	1
	ld	de, KERNEL_INTERRUPT_TIMER_OS
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	(hl), de
	ld	l, KERNEL_INTERRUPT_SIGNAL_LATCH and $FF
; just use default
	ld	e, $19
	ld	(hl), de
; also reset handler table
	jp	kirq.init

.ret:
.rst10:
.rst18:
.rst20:
.rst28:
.rst30:
	ei
	ret

.service:
	pop	hl
; read interrupt sources
	ld	hl, KERNEL_INTERRUPT_STATUS_MASKED
	ld	bc, (hl)
	ld	l, KERNEL_INTERRUPT_ACKNOWLEDGE and $FF
	ld	(hl), bc
; check type of the interrupt : master source ?
	bit	4, c
	jp	nz, kscheduler.local_timer
.irq_acknowledge:
	ld	a, b
	rla
	rla
	and	a, $F0
	or	a, c
	rra
	call	c, irq_handler_001
	rra
	call	c, irq_handler_002
	rra
	call	c, irq_handler_004
	rra
	call	c, irq_handler_008
	rra
	call	c, irq_handler_016
	rra
	call	c, irq_handler_032
	rra
	call	c, irq_handler_064
	rra
	call	c, irq_handler_128
	rr	a	; final one to set zero flag
.irq_generic:
	jr	z, .irq_generic_exit
	ld	c, a
	ld	hl, kthread_queue_retire
	ld	a, (hl)
	or	a, a
; z = no thread to awake
	jr	z, .irq_generic_exit
	ld	b, a
	inc	hl
	ld	iy, (hl)
.irq_generic_loop:
	ld	a, (iy+KERNEL_THREAD_IRQ)
	and	a, c
	call	nz, kthread.resume_from_IRQ
	ld	iy, (iy+KERNEL_THREAD_NEXT)
	djnz	.irq_generic_loop
; reschedule if kthread_need_reschedule is set
; set by kthread.resume
.irq_generic_exit:
	ld	hl, kthread_need_reschedule
	sra	(hl)
	ld	(hl), l
	inc	hl
	ld	iy, (hl)
	jp	c, kscheduler.schedule
.resume:
	pop	iy
	pop	ix
	exx
	ex	af, af'
	ei
	ret
	
kscheduler:

.switch:
.yield:
	di
	ex	af, af'
	exx
	push	ix
	push	iy
	ld	hl, kthread_need_reschedule
	ld	(hl), l
	inc	hl
	ld	iy, (hl)
	lea	hl, iy+KERNEL_THREAD_STATUS
; hl =status
	ld	a, (hl)
	or	a, a
	jr	z, .schedule
	inc	hl
; hl = priority
	ld	a, (hl)
	sub	a, QUEUE_SIZE
	add	a, (iy+KERNEL_THREAD_NICE)
	cp	a, SCHED_PRIO_MIN
	jr	c, .schedule_clamp_prio
	rla
	sbc	a, a
	cpl
	and	a, SCHED_PRIO_MIN
.schedule_clamp_prio:
	ld	(hl), a
	inc	hl
	jr	.schedule_give_quanta
	
.local_timer:
; schedule jiffies timer first
	ld	hl, klocal_timer_queue
	ld	a, (hl)
	or	a, a
	jr	z, .local_timer_exit
	inc	hl
; this is first thread with a timer
	ld	iy, (hl)
	ld	b, a
.local_timer_queue:
	ld	hl, (iy+TIMER_COUNT)
	dec	hl
	ld	(iy+TIMER_COUNT), hl
	ld	a, h
	or	a, l
	call	z, .local_timer_process
	ld	iy, (iy+TIMER_NEXT)
	djnz	.local_timer_queue
.local_timer_exit:

.schedule_check_quanta:
; if we need to reschedule, skip this phase entirely ;
	ld	hl, kthread_need_reschedule
	sra	(hl)
	ld	(hl), l
	inc	hl
; load current thread ;
	ld	iy, (hl)
	jr	c, .schedule
; do we have idle thread ?
	lea	hl, iy+KERNEL_THREAD_STATUS
	ld	a, (hl)
	inc	a
	jr	z, .schedule
	inc	hl
	inc	hl
	dec	(hl)
	jr	nz, kinterrupt.resume
; lower thread priority and move queue
.schedule_unpromote:
	dec	hl
	ld	de, kthread_mqueue_active
	ld	e, (hl)
	ld	a, e
	add	a, QUEUE_SIZE
	add	a, (iy+KERNEL_THREAD_NICE)
	cp	a, SCHED_PRIO_MIN
	jr	c, .schedule_move_queue
	rla
	sbc	a, a
	cpl
	and	a, SCHED_PRIO_MIN
.schedule_move_queue:
	ld	(hl), a
	inc	hl
	ex	de, hl
; we are the head of our queue, since we were executing ;
	call	kqueue.remove_head
	ld	l, a
	call	kqueue.insert_tail
	ld	a, l
	ex	de, hl
.schedule_give_quanta:
; exponential quantum
	rrca
	rrca
	inc	a
	ld	b, a
	xor	a, a
	scf
	rla
	djnz	$-1
	ld	(hl), a
.schedule:
; reset watchdog
	ld	hl, KERNEL_WATCHDOG_COUNTER
	ld	bc, (hl)
	ld	l, KERNEL_WATCHDOG_RST and $FF
	ld	(hl), $B9
	inc	hl
	ld	(hl), $5A
; mark timing used (24 bits count)
	ld	hl, (iy+KERNEL_THREAD_TIME)
	or	a, a
	sbc	hl, bc
	ld	bc, KERNEL_WATCHDOG_HEARTBEAT+1
	add	hl, bc
; this is total time of the thread (@32768Hz, may overflow)
	ld	(iy+KERNEL_THREAD_TIME), hl
.dispatch:
	ld	bc, QUEUE_SIZE
	xor	a, a
	ld	hl, kthread_mqueue_active
	or	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	or	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	or	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	or	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	or	a, (hl)
	jp	z, nmi
; schedule the idle thread
	ld	de, KERNEL_THREAD_IDLE
	jr	.dispatch_thread
.dispatch_queue:
	inc	hl
if CONFIG_USE_DYNAMIC_CLOCK
	ld	a, $03
	out0	(KERNEL_POWER_CPU_CLOCK),a
	ld	(KERNEL_FLASH_CTRL),a
end if
	ld	de, (hl)
.dispatch_thread:
; iy is previous thread, ix is the new thread, let's switch them
; are they the same ?
	lea	hl, iy+0
	sbc	hl, de
	exx
	jr	z, .context_restore_minimal
; same one, just quit and restore fast
; save state of the current thread
	ex	af,af'
	push	hl
	push	bc
	push	de
	push	af
; change thread
	or	a, a
	sbc	hl, hl
	add	hl, sp
	ld	(iy+KERNEL_THREAD_STACK), hl
	exx
.context_restore:
	ex	de, hl
	ld	(kthread_current), hl	; mark new current
	ld	c, KERNEL_THREAD_STACK_LIMIT
	add	hl, bc
	ld	bc, $00033A
	otimr
	ld	hl, (hl)
	ld	sp, hl
	pop	af
	pop	de
	pop	bc
	pop	hl
	pop	iy
	pop	ix
; give back the execution
	ei
	ret
.context_restore_minimal:
	pop	iy
	pop	ix
	ex	af, af'
	ei
	ret

.local_timer_process:
; remove the timer from the queue
	ld	hl, klocal_timer_queue
	call	kqueue.remove_head
; switch based on what we should do
	ld	a, (iy+TIMER_EV_SIGNOTIFY)
	or	a, a
	ret	z
	dec	a
	jr	nz, .local_timer_thread
.local_timer_signal:
	ld	hl, (iy+TIMER_EV_NOTIFY_THREAD)
	ld	c, (hl)
	ld	a, (iy+TIMER_EV_SIGNO)
	jp	ksignal.kill
.local_timer_thread:
; callback
	push	iy
	push	bc
	pea	iy+TIMER_EV_VALUE	; push it on the stack	
	call	.local_timer_call
	pop	hl
	pop	bc
	pop	iy
	ret
.local_timer_call:
	ld	hl, (iy+TIMER_EV_NOTIFY_FUNCTION)
	ld	iy, (iy+TIMER_EV_NOTIFY_THREAD)
	jp	(hl)

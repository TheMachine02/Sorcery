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

kinterrupt:
.init:
	di
	im	1
	ld	de, KERNEL_INTERRUPT_TIMER_OS
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	(hl), de
	ld	l, KERNEL_INTERRUPT_SIGNAL_LATCH and $FF
	ld	(hl), de
; also reset handler table
	jp	kirq.init

.ret:
.rst10:
.rst18:
.rst20:
.rst28:
.rst30:
    ret
.nmi = knmi.service

.service:
	pop	hl
; read interrupt sources
	ld	hl, KERNEL_INTERRUPT_STATUS_MASKED
	ld	bc, (hl)
	ld	l, KERNEL_INTERRUPT_ACKNOWLEDGE and $FF
	ld	(hl), bc
; check type of the interrupt : master source ?
	bit	4, c
	jr	nz, kscheduler.local_timer
.irq_acknowledge:
	ld	a, b
	rla
	rla
	and	$F0
	or	a, c
	rra
	call	c, KERNEL_IRQ_HANDLER_001
	rra
	call	c, KERNEL_IRQ_HANDLER_002
	rra
	call	c, KERNEL_IRQ_HANDLER_004
	rra
	call	c, KERNEL_IRQ_HANDLER_008
	rra
	call	c, KERNEL_IRQ_HANDLER_016
	rra
	call	c, KERNEL_IRQ_HANDLER_032
	rra
	call	c, KERNEL_IRQ_HANDLER_064
	rra
	call	c, KERNEL_IRQ_HANDLER_128
	rra
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
	tst	a, c
	call	nz, kthread.resume_from_IRQ
	ld	iy, (iy+KERNEL_THREAD_NEXT)
	djnz	.irq_generic_loop
; reschedule if kthread_need_reschedule is set
; set by kthread.resume
.irq_generic_exit:
	ld	hl, kthread_need_reschedule
	ld	a, $FF
	xor	a, (hl)
	jr	z, kscheduler.schedule_entry
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
	jr	.schedule
	
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
	dec	(iy+KERNEL_THREAD_TIMER_COUNT)
	call	z, .local_timer_process
	ld	iy, (iy+KERNEL_THREAD_TIMER_NEXT)
	djnz	.local_timer_queue
.local_timer_exit:

if CONFIG_USE_DOWNCLOCKING
; proof-of-concept
.clock_state:
	ld	a, (kcstate_timer)
	inc	a
	cp	a, KERNEL_CSTATE_SAMPLING
	jr	nz, .clock_state_exit
	call	kcstate.idle_adjust
	ld	hl, 0
	ld	(KERNEL_THREAD+KERNEL_THREAD_TIME), hl
	xor	a, a
.clock_state_exit:
	ld	(kcstate_timer), a
end if

.schedule:
	ld	hl, kthread_need_reschedule
	xor	a, a
.schedule_entry:
	ld	(hl), a
	inc	hl
; read kthread_current
	ld	iy, (hl)
; reset watchdog
	ld	hl, KERNEL_WATCHDOG_COUNTER
	ld	de, (hl)
	ld	l, KERNEL_WATCHDOG_RST mod 256
	ld	(hl), $B9
	inc	hl
	ld	(hl), $5A
; mark timing used (24 bits count)
	ld	hl, KERNEL_WATCHDOG_MAX_TIME + 1
	sbc	hl, de
	ld	de, (iy+KERNEL_THREAD_TIME)
	add	hl, de
; this is total time of the thread (@32768Hz, may overflow)
	ld	(iy+KERNEL_THREAD_TIME), hl
; check if current thread is active : if yes, grab next_thread
; idle is marked as INTERRUPTIBLE, ie non active
; if not active, grab kthread_queue_active_current thread
; if queue empty, schedule idle thread
; schedule on the active list now ;
	ld	ix, (iy+KERNEL_THREAD_NEXT)
	or	a, (iy+KERNEL_THREAD_STATUS)
	jr	z, .dispatch
	ld	hl, kthread_queue_active
	ld	a, (hl)
	inc	hl
	ld	ix, (hl)
	or	a, a
	jr	nz, .dispatch
; schedule the idle thread
	inc	hl
	inc	hl
	inc	hl
	or	a, (hl)
; panic if NO thread
	jp	z, kinterrupt.nmi
	ld	ix, KERNEL_THREAD_IDLE
.dispatch:
; iy is previous thread, ix is the new thread, let's switch them
; are they the same ?
	lea	hl, iy+0
	lea	de, ix+0
	sbc	hl, de
	jr	z, .context_restore_minimal
; same one, just quit and restore fast
	ld	(kthread_current), de	; mark new current
; save state of the current thread
	exx
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
.context_restore:
	lea	hl, ix+KERNEL_THREAD_STACK_LIMIT
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
	exx
	ex	af, af'
	ei
	ret

.local_timer_process:
; don't touch bc and iy that's all
; remove the timer from the queue
	ld	hl, klocal_timer_queue
	call	klocal_timer.remove
; switch based on what we should do
	ld	a, (iy+KERNEL_THREAD_TIMER_EV_SIGNOTIFY)
	or	a, a
	ret	z
	dec	a
	jr	z, .local_timer_signal
	ld	hl, (iy+KERNEL_THREAD_TIMER_EV_NOTIFY_FUNCTION)
	jp	(hl)
.local_timer_signal:
	ld	c, (iy+KERNEL_THREAD_PID)
	ld	a, (iy+KERNEL_THREAD_TIMER_EV_SIGNO)
	jp	kill

define	KERNEL_INTERRUPT_ISRR			$F00000		; raw status
define	KERNEL_INTERRUPT_IMSC			$F00004		; enable mask
define	KERNEL_INTERRUPT_ICR			$F00008		; acknowledge
define	KERNEL_INTERRUPT_ISL			$F0000C		; signal latch
define	KERNEL_INTERRUPT_ISR			$F00014
define	KERNEL_INTERRUPT_REVISION		$F00050
define	KERNEL_INTERRUPT_REVISION_BASE		$010900

define	KERNEL_INTERRUPT_ON			00000001b
define	KERNEL_INTERRUPT_TIMER1			00000010b
define	KERNEL_INTERRUPT_TIMER2			00000100b
define	KERNEL_INTERRUPT_TIMER3			00001000b
define	KERNEL_INTERRUPT_TIMER_OS		00010000b
define	KERNEL_INTERRUPT_KEYBOARD		00000100b
define	KERNEL_INTERRUPT_LCD			00001000b
define	KERNEL_INTERRUPT_RTC			00010000b
define	KERNEL_INTERRUPT_USB			00100000b

define	KERNEL_IRQ_CLOCK			0
define	KERNEL_IRQ_POWER			1
define	KERNEL_IRQ_TIMER1			2
define	KERNEL_IRQ_TIMER2			4
define	KERNEL_IRQ_TIMER3			8
define	KERNEL_IRQ_KEYBOARD			16
define	KERNEL_IRQ_LCD				32
define	KERNEL_IRQ_RTC				64
define	KERNEL_IRQ_USB				128

kinterrupt:
 
.init:
	di
	im	1
	ld	de, KERNEL_INTERRUPT_TIMER_OS
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	(hl), de
	ld	l, KERNEL_INTERRUPT_ISL and $FF
; just use default (minus timer 3)
	ld	e, KERNEL_INTERRUPT_ON or KERNEL_INTERRUPT_TIMER_OS
	ld	(hl), de
; also reset handler table
; 	ld	hl, KERNEL_INTERRUPT_IPT
; 	ld	i, hl
	xor	a, a
	ld	(kinterrupt_irq_boot_ctx), a
	ld	(kinterrupt_lru_page), a
	ld	hl, .irq_context_return
	ld	(kinterrupt_irq_ret_ctx), hl
	ret

.irq_free:
; disable the IRQ then remove the handler
	call	.irq_disable
	call    .irq_extract_line
	ld	de, NULL
	ld	(hl), de
	ret

.irq_request:
; TODO : check if handler is not already taken
; TODO : check the interrupt routine is in *RAM*
; a = IRQ, hl = interrupt routine
	call	.irq_extract_line
	ld	(hl), de
; register the handler then enable the IRQ    

.irq_enable:
	push	hl
	push	bc
; enable a specific IRQ or a specific IRQ combinaison
	ld	c, a
	rra
	rra
	and	a, 00111100b
	ld	b, a
; this is the second byte for interrupt mask
	ld	a, c
	and	a, 00001111b
; critical section ;
	ld	c, a
	ld	a, i
	push	af
	di
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	a, (hl)
	or	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	or	a, b
	ld	(hl), a
	pop	af
	pop	bc
	pop	hl
	ret	po
	ei
	ret
    
.irq_disable:
	push	hl
	push	bc
; enable a specific IRQ
	ld	c, a
	rra
	rra
	cpl
	and	a, 00111100b
	ld	b, a
; this is the second byte for interrupt mask
	ld	a, c
	cpl
	and	a, 00001111b
	ld	c, a
; critical section ;
	ld	a, i
	push	af
	di
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	a, (hl)
	and	a, c
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	and	a, b
	ld	(hl), a
	pop	af
	pop	bc
	pop	hl
	ret	po
	ei
	ret

.irq_extract_line:
	push	af
	ex	de, hl
	ld	hl, (KERNEL_INTERRUPT_IPT_JP shr 2) - 1
.irq_extract_bit:
	inc	l
	rra
	jr	nc, .irq_extract_bit
	add	hl, hl
	add	hl, hl
	pop	af
	inc	hl
; hl = line, de = old hl, bc safe, af safe
	ret
	
;; C function : irqstate_t irq_save(void)
.irq_save:
	push	af
	ld	a, i
	di
	push	af
	pop	hl
	pop	af
	ret

; C function : void irq_restore(irqstate_t flags)
.irq_restore:
	pop	hl
	pop	af
	push	af
	push	hl
	ret	po
	ei
	ret

.irq_do_timer:
; if interval is not zero, reload the count value with interval value
	ld	hl, (iy+TIMER_INTERVAL)
	ld	a, l
	or	a, h
	jr	nz, .irq_process_timer
; remove the timer from the queue
	ld	hl, ktimer_queue
	call	kqueue.remove_head
	or	a, a
	sbc	hl, hl
.irq_process_timer:
	ld	(iy+TIMER_COUNT), l
	ld	(iy+TIMER_COUNT+1), h
; now we will read the sigev and switch based on it
	ld	ix, (iy+TIMER_SIGEV)
	ld	a, (ix+SIGEV_SIGNOTIFY)
	dec	a
	ret	m
	jr	nz, .irq_timer_thread
.irq_timer_signal:
	push	iy
	push	bc
	ld	l, (iy+TIMER_INTERNAL_THREAD)
	ld	e, (ix+SIGEV_SIGNO)
	call	signal.kill
	pop	bc
	pop	iy
	ret
.irq_timer_thread:
; callback
	push	iy
	push	bc
	ld	hl, (ix+SIGEV_VALUE)
	push	hl
	ld	hl, (ix+SIGEV_NOTIFY_FUNCTION)
	call	.irq_timer_thread_call
	pop	hl
	pop	bc
	pop	iy
	ret
.irq_timer_thread_call:
	jp	(hl)

.irq_handler:
	pop	hl
if	CONFIG_PERF_COUNTER
	ld	hl, (perf_interrupt)
	inc	hl
	ld	(perf_interrupt), hl
end	if
; read interrupt sources
	ld	hl, KERNEL_INTERRUPT_ISR
; IRQ 0 master
	bit	4, (hl)
	jr	nz, .irq_trampoline_crystal
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	ld	l, (KERNEL_INTERRUPT_ICR+1) and $FF
	or	a, a
	jr	nz, .irq_trampoline
	ld	a, c
	ccf
	adc	a, a
	add	a, a
	dec	l
.irq_trampoline:
	ex	de, hl
; and now, for some black magic
	ld	(kinterrupt_irq_stack_ctx), sp
	ld	sp, kinterrupt_irq_stack_isr
	ld	hl, KERNEL_INTERRUPT_IPT
	ld	l, a
	ldi
	ld	l, (hl)
	jp	(hl)
.irq_context_return:
; restore context stack
	pop	hl
	ld	sp, hl
; check if we need to reschedule for fast response
	ld	hl, KERNEL_INTERRUPT_IPT
	sla	(hl)
	inc	hl
	ld	iy, (hl)
	jp	c, kscheduler.do_schedule
.irq_context_restore:
; check here for pending signal
; NOTE : if we happen to be in kernel space (check for syscall mainly), then we don't process signal right now
; the signal processing will happen at the syscall end (however, if the thread was interruptible, it is proprely waked up and syscall need to take this into account)
	ld	hl, 6
	add	hl, sp
	ld	hl, (hl)
	ld	de, KERNEL_MM_GFP_RAM
	sbc	hl, de
	jr	c, .irq_frame
	ld	a, (iy+KERNEL_THREAD_SIGNAL_CURRENT)
	or	a, a
	jr	nz, .irq_do_signal
.irq_frame:
	pop	iy
	pop	ix
	exx
	ex	af, af'
	ei
	ret

.irq_do_signal:
; here, we are just before context switch
; shadow hold correct registers
; stack have iy and ix, so actually we are already in a kernel stack frame
; push down user stack the handler adress (and the sigreturn syscall)
; after the signal is processed, we re-enter interrupt like state and do an irq_context_restore to check for *more* pending signal (every signal should be processed after that, also we can be preempted whenever we want)
	exx
	ex	af, af'
	push	de
	push	bc
	push	af
	push	hl
	ld	a, (iy+KERNEL_THREAD_SIGNAL_CURRENT)
	ld	(iy+KERNEL_THREAD_SIGNAL_CURRENT), 0
; C param
	or	a, a
	sbc	hl, hl
	ld	l, a
	push	hl
	ld	c, a
; mask operation destroy b but not c
	call	signal.mask_operation
; ; save the signal status (0 is blocked, 1 is unblocked)
; 	ld	b, a
; 	and	a, (hl)
; 	ld	(iy+KERNEL_THREAD_SIGNAL_SAVE), a
; 	ld	a, b
	cpl
; block current signal
	and	a, (hl)
	ld	(hl), a
	ld	hl, signal.return
	push	hl
	ld	a, c
	ld	hl, (iy+KERNEL_THREAD_SIGNAL_VECTOR)
; we are in a slab 128/256 bytes aligned, so this is valid
	add	a, a
	add	a, a
	add	a, l
	ld	l, a
	ei
	ld	a, (hl)
	inc	a
	ret	z
; directly jump into the vector table
; NOTE : we leak register and kernel adresses here
; however, pass down iy as current thread for ease of mind
	jp	(hl)

.irq_trampoline_crystal:
; this is the master clock IRQ handler
	ld	l, KERNEL_INTERRUPT_ICR and $FF
	set	4, (hl)
.irq_crystal_lru:
	ld	hl, kinterrupt_lru_page
	inc	(hl)
.irq_crystal_clock:
; update timer queue first, then check if we need to reschedule
	ld	hl, ktimer_queue
	ld	b, (hl)
	inc	b
	jr	z, .irq_crystal_resume
	inc	hl
; this is first timer
	ld	iy, (hl)
.irq_crystal_timers:
	dec	(iy+TIMER_COUNT)
	jr	nz, .irq_crystal_next
	dec	(iy+TIMER_COUNT+1)
	call	z, .irq_do_timer
.irq_crystal_next:
	ld	iy, (iy+TIMER_NEXT)
	djnz	.irq_crystal_timers
.irq_crystal_resume:

kscheduler:
.schedule_check_quanta:
; load current thread
	ld	hl, KERNEL_INTERRUPT_IPT
	sla	(hl)
	inc	hl
	ld	iy, (hl)
; do we have idle thread ?
	lea	hl, iy+KERNEL_THREAD_STATUS
	ld	a, (hl)
	inc	a
; this is idle, just schedule
	jr	z, .do_schedule
; perform the thread profiling
	bit	THREAD_PROFIL_BIT, (iy+KERNEL_THREAD_ATTRIBUTE)
	call	nz, profil.scheduler
; we still have carry from that sla (hl), so if carry is set, we need to reschedule
	jr	c, .do_schedule
	inc	hl
	inc	hl
	dec	(hl)
	jp	nz, kinterrupt.irq_context_restore
; lower thread priority and move queue since we reached our quantum
.schedule_unpromote:
	dec	hl
	ld	de, kthread_mqueue_active
	ld	e, (hl)
	ld	a, (iy+KERNEL_THREAD_NICE)
	sra	a
	add	a, QUEUE_SIZE
	add	a, e
	cp	a, SCHED_PRIO_MIN
	jr	c, .schedule_move_queue
	rla
	sbc	a, a
	cpl
.schedule_move_queue:
	and	a, SCHED_PRIO_MIN
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
.do_schedule:
; reset watchdog
	ld	hl, KERNEL_WATCHDOG_COUNTER
	ld	bc, (hl)
	ld	l, KERNEL_WATCHDOG_RST and $FF
	ld	(hl), $B9
	inc	hl
	ld	(hl), $5A
; mark timing used (24 bits count)
	ld	hl, (iy+KERNEL_THREAD_TIME)
	xor	a, a
	sbc	hl, bc
	ld	bc, KERNEL_WATCHDOG_HEARTBEAT+1
	add	hl, bc
; this is total time of the thread (@32768Hz, may overflow)
	ld	(iy+KERNEL_THREAD_TIME), hl
	ld	bc, QUEUE_SIZE
	ld	hl, kthread_mqueue_active
	dec	a
	cp	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	cp	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	cp	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	cp	a, (hl)
	jr	nz, .dispatch_queue
	add	hl, bc
	cp	a, (hl)
	jp	z, nmi
.dispatch_idle:
; schedule the idle thread
	add	hl, bc
.dispatch_queue:
	inc	hl
	ld	de, (hl)
; iy is previous thread, de is the new thread, let's switch them
; are they the same ?
	lea	hl, iy+0
	sbc	hl, de
	jp	z, kinterrupt.irq_context_restore
.context_switch:
; put the new thread in iy
	exx
; save state of the current thread
	ex	af,af'
	push	de
	push	bc
	push	af
	push	hl
if	CONFIG_PERF_COUNTER	
	ld	hl, (perf_context_switch)
	inc	hl
	ld	(perf_context_switch), hl
end	if
; change thread
	sbc	hl, hl
	adc	hl, sp
	ld	(iy+KERNEL_THREAD_STACK), hl
	exx
	ld	iy, 0
	add	iy, de
	ex	de, hl
	ld	(kthread_current), hl
	ld	c, KERNEL_THREAD_STACK_LIMIT
	add	hl, bc
	ld	bc, $00033A
	otimr
	ld	hl, (hl)
	ld	sp, hl
	pop	hl
	pop	af
	pop	bc
	pop	de
	exx
	ex	af, af'
	jp	kinterrupt.irq_context_restore

sysdef _schedule
.schedule:
	di
	ex	af, af'
	exx
	push	ix
	push	iy
	ld	iy, (kthread_current)
	jp	.do_schedule

sysdef _yield
.yield:
; NOTE : yield boost priority of I/O bound thread, so boost priority if status is not TASK_READY
	di
	ex	af, af'
	exx
	push	ix
	push	iy
	ld	iy, (kthread_current)
	lea	hl, iy+KERNEL_THREAD_STATUS
	ld	a, (hl)
	or	a, a
	jp	z, .do_schedule
	inc	hl
	ld	a, (iy+KERNEL_THREAD_NICE)
	sra	a
	sub	a, QUEUE_SIZE
	add	a, (hl)
	cp	a, SCHED_PRIO_MIN
	jr	c, .schedule_clamp_prio
	rla
	sbc	a, a
	cpl
.schedule_clamp_prio:
	and	a, SCHED_PRIO_MIN
	ld	(hl), a
	inc	hl
	jp	.schedule_give_quanta

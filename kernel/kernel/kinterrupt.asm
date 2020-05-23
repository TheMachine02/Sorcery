define	KERNEL_INTERRUPT_STATUS_RAW		0xF00000
define	KERNEL_INTERRUPT_ENABLE_MASK		0xF00004
define	KERNEL_INTERRUPT_ACKNOWLEDGE		0xF00008
define	KERNEL_INTERRUPT_SIGNAL_LATCH		0xF0000C
define	KERNEL_INTERRUPT_STATUS_MASKED		0xF00014
define	KERNEL_INTERRUPT_REVISION		0xF00050
define	KERNEL_INTERRUPT_REVISION_BASE		0x010900
define	KERNEL_INTERRUPT_EARLY_SWITCH		0xD177BA

define	KERNEL_INTERRUPT_ON			00000001b
define	KERNEL_INTERRUPT_TIMER1			00000010b
define	KERNEL_INTERRUPT_TIMER2			00000100b
define	KERNEL_INTERRUPT_TIMER3			00001000b
define	KERNEL_INTERRUPT_TIMER_OS		00010000b
define	KERNEL_INTERRUPT_KEYBOARD		00000100b
define	KERNEL_INTERRUPT_LCD			00001000b
define	KERNEL_INTERRUPT_RTC			00010000b
define	KERNEL_INTERRUPT_USB			00100000b

define	KERNEL_INTERRUPT_TIME			0xF16000
define	KERNEL_INTERRUPT_MAX_TIME		0x020000

define	KERNEL_TIME_JIFFIES_TO_MS		75		; (154/32768)*1000*16
define	KERNEL_TIME_MS_TO_JIFFIES		54		; (32768/154)/1000*256

kinterrupt:
.init:
	tstdi
	im	1
	ld	hl, KERNEL_INTERRUPT_ENABLE_MASK
	ld	(hl), KERNEL_INTERRUPT_TIMER_OS
	inc	hl
	ld	(hl), 0
	ld	hl, KERNEL_INTERRUPT_SIGNAL_LATCH
	ld	(hl), KERNEL_INTERRUPT_TIMER_OS
	inc	hl
	ld	(hl), 0
; also reset handler table
	call	kirq.init
	retei
.ret:
.rst10:
.rst18:
.rst20:
.rst28:
.rst30:
    ret
.nmi = kpanic.nmi

.service:
	pop	hl
; read interrupt sources
	ld	hl, KERNEL_INTERRUPT_STATUS_MASKED
	ld	bc, (hl)
	ld	l, KERNEL_INTERRUPT_ACKNOWLEDGE and 0xFF
	ld	(hl), c
	inc	hl
	ld	(hl), b
; check type of the interrupt : master source ?
	bit	4, c
	jr	nz, kscheduler.local_timer
	ld	a, b
	rla
	rla
	and	0xF0
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
; reschedule if kthread_need_reschedule is set
; set by kthread.resume
	ld	c, a
	ld	hl, kthread_queue_retire
	ld	a, (hl)
	or	a, a
; z = no thread to awake
	jr	z, .irq_exit
	ld	b, a
; c = irq where we need to resume thread
	ld	a, c
	or	a, a
	jr	z, .irq_exit
	inc	hl
	ld	iy, (hl)
.irq_resume_loop:
	ld	c, (iy+KERNEL_THREAD_IRQ)
	tst	a, c
	jr	z, .irq_skip
	ld	hl, (iy+KERNEL_THREAD_PREVIOUS)
	push	hl
	ld	(iy+KERNEL_THREAD_IRQ), 0
	call	kthread.resume
; reload the current retire queue (previous node of the retired node)
	pop	iy
.irq_skip:
	ld	iy, (iy+KERNEL_THREAD_NEXT)
	djnz	.irq_resume_loop
.irq_exit:	
	ld	a, (kthread_need_reschedule)
	or	a, a
	jr	nz, kscheduler.schedule
.resume:
	pop	iy
	pop	ix
	exx
	ex	af, af'
	ei
	reti
	
kscheduler:

.switch:
.yield:
	di
	ex	af, af'
	exx
	push	ix
	push	iy
	jr	.schedule

.local_timer_call:
; don't touch bc and iy that's all
	ld	hl, (iy+KERNEL_THREAD_TIMER_CALLBACK)
	jp	(hl)
	
.local_timer:
; schedule jiffies timer first
; super fast loooop
	ld	hl, klocal_timer_queue
	ld	a, (hl)
	or	a, a
	jr	z, .clock_state
	inc	hl
; this is first thread with a timer
	ld	iy, (hl)
	ld	b, a
.local_timer_queue:
	dec	(iy+KERNEL_THREAD_TIMER_COUNT)
	call	z, .local_timer_call
	ld	iy, (iy+KERNEL_THREAD_TIMER_NEXT)
	djnz	.local_timer_queue
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
.schedule:
	ld	hl, kthread_need_reschedule
	xor	a, a
	ld	(hl), a
	inc	hl
	ld	iy, (hl)
; reset watchdog
	ld	hl, KERNEL_WATCHDOG_COUNTER
	ld	de, (hl)
	ld	l, KERNEL_WATCHDOG_RST mod 256
	ld	(hl), 0xB9
	inc	hl
	ld	(hl), 0x5A
; mark timing used (24 bits count)
	ld	hl, KERNEL_INTERRUPT_MAX_TIME + 1
	sbc	hl, de
	ld	de, (iy+KERNEL_THREAD_TIME)
	add	hl, de
; this is total time of the thread (@32768Hz, may overflow)
	ld	(iy+KERNEL_THREAD_TIME), hl
; check if current thread is active : if yes, grab next_thread
; idle is marked as NOT ACTIVE, NULL is NOT ACTIVE
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
	ld	a, (kthread_queue_retire_size)
	or	a, a
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
	ld	a, (hl)
	inc	hl
	out0	(0x3A), a
	ld	a, (hl)
	inc	hl
	out0	(0x3B), a
	ld	a, (hl)
	inc	hl
	out0	(0x3C), a
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
	reti
.context_restore_minimal:
	pop	iy
	pop	ix
	exx
	ex	af, af'
	ei
	reti
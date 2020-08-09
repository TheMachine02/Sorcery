define	KERNEL_INTERRUPT_ISRR			$F00000		; raw status
define	KERNEL_INTERRUPT_IMSC			$F00004		; enable mask
define	KERNEL_INTERRUPT_ICR			$F00008		; acknowledge
define	KERNEL_INTERRUPT_ISL			$F0000C		; signal latch
define	KERNEL_INTERRUPT_ISR			$F00014
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

define	KERNEL_IRQ_POWER			1
define	KERNEL_IRQ_TIMER1			2
define	KERNEL_IRQ_TIMER2			4
define	KERNEL_IRQ_TIMER3			8
define	KERNEL_IRQ_KEYBOARD			16
define	KERNEL_IRQ_LCD				32
define	KERNEL_IRQ_RTC				64
define	KERNEL_IRQ_USB				128

define	irq_vector   				$D00140
define	irq_vector_power			$D00140
define	irq_vector_timer1			$D00144
define	irq_vector_timer2			$D00148
define	irq_vector_timer3			$D0014C
define	irq_vector_keyboard			$D00150
define	irq_vector_lcd				$D00154
define	irq_vector_rtc				$D00158
define	irq_vector_usb				$D0015C

kinterrupt:

.init:
	di
	im	1
	ld	de, KERNEL_INTERRUPT_TIMER_OS
	ld	hl, KERNEL_INTERRUPT_IMSC
	ld	(hl), de
	ld	l, KERNEL_INTERRUPT_ISL and $FF
; just use default
	ld	e, $19
	ld	(hl), de
; also reset handler table
	ld	hl, irq_vector
	ld 	de, 4
	ld	b, 8
	ld	a, $C9
.init_vector:
	ld	(hl), a
	add	hl, de
	djnz	.init_vector
	ret

.irq_free:
; disable the IRQ then remove the handler
	call	.irq_disable
	push	de
	call    .irq_extract_line
	ld	a, $C9
	ld	(hl), a
	ex	de, hl
	pop	de
	ret
        
.irq_extract_line:
	push	bc
	push	af
	ld	b, $FF
.irq_extract_bit:
	inc	b
	rra
	jr	nc, .irq_extract_bit
	ld	a, b
	ex	de, hl
	add	a, a
	add	a, a
	sbc	hl, hl
	ld	l, a
	ld	bc, irq_vector
	add	hl, bc
	pop	af
	pop	bc
; hl = line, de = old hl, bc safe, af safe
	ret

.irq_request:
; a = IRQ, hl = interrupt routine
; check the interrupt routine is in *RAM*
	push	de
	call	.irq_extract_line
	ld	(hl), $C3
	inc	hl
	ld	(hl), de
	ex	de, hl
	pop	de
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
	ld	hl, i
	push	af
	di
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_IMSC
	or	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	or	a, b
	ld	(hl), a
	pop	af
	ld	a, c
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
; critical section ;
	ld	hl, i
	push	af
	di
; this is the first byte
	ld	hl, KERNEL_INTERRUPT_IMSC
	and	a, (hl)
	ld	(hl), a
	inc	hl
	ld	a, (hl)
	and	a, b
	ld	(hl), a
	pop	af
	ld	a, c
	pop	bc
	pop	hl
	ret	po
	ei
	ret

.irq_handler:
	pop	hl
; read interrupt sources
	ld	hl, KERNEL_INTERRUPT_ISR
	ld	bc, (hl)
	ld	l, KERNEL_INTERRUPT_ICR and $FF
	ld	(hl), bc
; check type of the interrupt : master source ?
	bit	4, c
	jr	nz, .irq_vector_crystal
.irq_acknowledge:
	ld	a, b
	rla
	rla
	and	a, $F0
	or	a, c
	rra
	call	c, irq_vector_power
	rra
	call	c, irq_vector_timer1
	rra
	call	c, irq_vector_timer2
	rra
	call	c, irq_vector_timer3
	rra
	call	c, irq_vector_keyboard
	rra
	call	c, irq_vector_lcd
	rra
	call	c, irq_vector_rtc
	rra
	call	c, irq_vector_usb
	ld	hl, kthread_need_reschedule
	sra	(hl)
	ld	(hl), l
	inc	hl
	ld	iy, (hl)
	jr	c, kscheduler.schedule
.irq_resume:
	pop	iy
	pop	ix
	exx
	ex	af, af'
	ei
	ret

.irq_vector_crystal:
; schedule jiffies timer first
	ld	hl, klocal_timer_queue
	ld	a, (hl)
	or	a, a
	jr	z, kscheduler.schedule_check_quanta
	inc	hl
; this is first thread with a timer
	ld	iy, (hl)
	ld	b, a
.irq_crystal_queue:
	ld	hl, (iy+TIMER_COUNT)
	dec	hl
	ld	(iy+TIMER_COUNT), hl
	ld	a, h
	or	a, l
	call	z, ktimer.crystal_wake
	ld	iy, (iy+TIMER_NEXT)
	djnz	.irq_crystal_queue

kscheduler:
.schedule_check_quanta:
; if we need to reschedule, skip this phase entirely ;
	ld	hl, kthread_need_reschedule
	sra	(hl)
	ld	(hl), l
	inc	hl
; ; load current thread ;
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
	jr	nz, kinterrupt.irq_resume
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
	xor	a, a
	sbc	hl, bc
	ld	bc, KERNEL_WATCHDOG_HEARTBEAT+1
	add	hl, bc
; this is total time of the thread (@32768Hz, may overflow)
	ld	(iy+KERNEL_THREAD_TIME), hl
	ld	bc, QUEUE_SIZE
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
	ld	(kthread_current), hl
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
	jp	z, .schedule
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
	jp	.schedule_give_quanta

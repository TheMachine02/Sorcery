define	KERNEL_INTERRUPT_ISRR			$F00000		; raw status
define	KERNEL_INTERRUPT_IMSC			$F00004		; enable mask
define	KERNEL_INTERRUPT_ICR			$F00008		; acknowledge
define	KERNEL_INTERRUPT_ISL			$F0000C		; signal latch
define	KERNEL_INTERRUPT_ISR			$F00014
define	KERNEL_INTERRUPT_REVISION		$F00050
define	KERNEL_INTERRUPT_REVISION_BASE		$010900
define	KERNEL_INTERRUPT_BOOT_HANDLER		$D177BA

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

define	KERNEL_IRQ_CLOCK			0
define	KERNEL_IRQ_POWER			1
define	KERNEL_IRQ_TIMER1			2
define	KERNEL_IRQ_TIMER2			4
define	KERNEL_IRQ_TIMER3			8
define	KERNEL_IRQ_KEYBOARD			16
define	KERNEL_IRQ_LCD				32
define	KERNEL_IRQ_RTC				64
define	KERNEL_IRQ_USB				128

define	KERNEL_INTERRUPT_IPT			$D00600
define	KERNEL_INTERRUPT_IPT_SIZE		4
define	KERNEL_INTERRUPT_IPT_LP			$D00610
define	KERNEL_INTERRUPT_IPT_HP			$D00620
define	KERNEL_INTERRUPT_IPT_JP			$D00640

kinterrupt:

.IPT_PAGE:
; IRQ priority : keyboard > lcd > usb > rtc > hrtr1 > hrtr2 > hrtr3 > power
.IPT_LP:
 db	$00, $00	; 0000
 db	$04, $50	; 0001
 db	$08, $54	; 0010
 db	$04, $50	; 0011
 db	$10, $58	; 0100
 db	$04, $50	; 0101
 db	$08, $54	; 0110
 db	$04, $50	; 0111
 db	$20, $5C	; 1000
 db	$04, $50	; 1001
 db	$08, $54	; 1010
 db	$04, $50	; 1011
 db	$20, $5C	; 1100
 db	$04, $50	; 1101
 db	$08, $54	; 1110
 db	$04, $50	; 1111
.IPT_HP:
 db	$00, $00	; 0000
 db	$01, $40	; 0001
 db	$02, $44	; 0010
 db	$02, $44	; 0011
 db	$04, $48	; 0100
 db	$04, $48	; 0101
 db	$02, $44	; 0110
 db	$02, $44	; 0111
 db	$08, $4C	; 1000
 db	$08, $4C	; 1001
 db	$02, $44	; 1010
 db	$02, $44	; 1011
 db	$04, $48	; 1100
 db	$04, $48	; 1101
 db	$02, $44	; 1110
 db	$02, $44	; 1111
.IPT_JP:
 jp	.irq_resume	; default for power IRQ
 jp	$0
 jp	$0
 jp	$0
 jp	$0
 jp	$0
 jp	$0
 jp	$0
 
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
	ld	hl, KERNEL_INTERRUPT_IPT
	ld	i, hl
	ex	de, hl
	ld	hl, .IPT_PAGE
	ld	bc, 96
	ldir
	xor	a, a
	ld	(KERNEL_INTERRUPT_BOOT_HANDLER), a
	ret

.irq_free:
; disable the IRQ then remove the handler
	call	.irq_disable
	call    .irq_extract_line
	ld	de, NULL
	ld	(hl), de
	ret

.irq_request:
; a = IRQ, hl = interrupt routine
; check the interrupt routine is in *RAM*
	call	.irq_extract_line
	ld	(hl), de
; register the handler then enable the IRQ    

.irq_enable:
	push	hl
	push	bc
	ld	hl, i
	push	af
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
	pop	bc
	pop	hl
	ret	po
	ei
	ret
    
.irq_disable:
	push	hl
	push	bc
	ld	hl, i
	push	af
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
	pop	bc
	pop	hl
	ret	po
	ei
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
	add	a, a
	add	a, a
	ex	de, hl
	sbc	hl, hl
	ld	l, a
	ld	bc, KERNEL_INTERRUPT_IPT_JP
	add	hl, bc
	pop	af
	pop	bc
	inc	hl
; hl = line, de = old hl, bc safe, af safe
	ret

; C helper function (broken, btw)
.irq_save:
	ld	hl, i
	di
; push af & hl to the stack
	pop	de
	push	af
	push	hl
	ex	de, hl
	jp	(hl)
	
.irq_restore:
	pop	de
	pop	hl
	ld	i, hl
	pop	af
	ex	de, hl
	jp	po, $+5
	ei
	jp	(hl)

.irq_handler:
	pop	hl
; read interrupt sources
	ld	hl, KERNEL_INTERRUPT_ISR
; IRQ 0 master
	bit	4, (hl)
	jr	nz, .irq_trampoline_crystal
	ld	c, (hl)
	inc	hl
	ld	a, (hl)
	ld	l, (KERNEL_INTERRUPT_ICR+1) and $FF
	srl	a
	jr	nz, .irq_trampoline_generic
	ld	a, c
	add	a, a
	dec	l
	or	a, KERNEL_INTERRUPT_IPT_HP and $FF
.irq_trampoline_generic:
; it is up to the irq_handler to clean up with return to irq_resume
	ex	de, hl
; and now, for some black magic
	ld	hl, i
	ld	l, a
	ldi
	ld	l, (hl)
	jp	(hl)
.irq_resume_thread:
; check if we need to reschedule for fast response
	ld	hl, kthread_irq_reschedule
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
	
.irq_trampoline_crystal:
; this is the master clock IRQ handler
	ld	l, KERNEL_INTERRUPT_ICR and $FF
	set	4, (hl)
.irq_crystal_clock:
; update timer queue first, then check if we need to reschedule
	ld	hl, ktimer_queue
	ld	a, (hl)
	or	a, a
	jr	z, .irq_crystal_resume
	inc	hl
; this is first thread with a timer
	ld	iy, (hl)
	ld	b, a
.irq_crystal_timers:
	ld	hl, (iy+TIMER_COUNT)
	dec	hl
	ld	(iy+TIMER_COUNT), hl
	ld	a, h
	or	a, l
	call	z, ktimer.trigger
	ld	iy, (iy+TIMER_NEXT)
	djnz	.irq_crystal_timers
.irq_crystal_resume:

kscheduler:
.schedule_check_quanta:
; if we need to reschedule, skip this phase entirely ;
	ld	hl, kthread_irq_reschedule
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
	ld	hl, kthread_irq_reschedule
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

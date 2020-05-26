;include 'include/kernel.inc'

define	DRIVER_HRTIMER1_COUNTER			0xF20000
define	DRIVER_HRTIMER1_RST			0xF20004
define	DRIVER_HRTIMER1_MATCH1			0xF20008
define	DRIVER_HRTIMER1_MATCH2			0xF2000C
define	DRIVER_HRTIMER1_CTRL			0xF20030
define	DRIVER_HRTIMER1_ISCR			0xF20034
define	DRIVER_HRTIMER1_ISR			0xD000F1
define	DRIVER_HRTIMER1_IRQ			00000010b
define	DRIVER_HRTIMER1_IRQ_LOCK_THREAD		0xD000F2
define	DRIVER_HRTIMER1_IRQ_LOCK		0xD000F5
define	DRIVER_HRTIMER1_IRQ_LOCK_SET		0

ktimer:
	db	3
.jump:
	jp	.init
	jp	.irq_handler
	jp	.irq_lock
	jp	.irq_unlock
	jp	.wait

.init:
	tstdi
; todo : enable the timer 1 with default paramater

; reset lock
	call	.irq_lock_reset
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	pop	af
	ld	a, DRIVER_HRTIMER1_IRQ
	jp	po, kirq.request
	ei
	jp	kirq.request

.irq_handler:
	push	af
	ld	hl, DRIVER_HRTIMER1_ISCR
	ld	a, (hl)
	ld	(DRIVER_HRTIMER1_ISR), a
	ld	(hl), 0x03
	pop	af
	ld	hl, DRIVER_HRTIMER1_IRQ_LOCK
	bit	DRIVER_HRTIMER1_IRQ_LOCK_SET, (hl)
	ret	z
	ld	iy, (DRIVER_HRTIMER1_IRQ_LOCK_THREAD)
	call	kthread.resume_from_IRQ
	ccf
	ret
	
.irq_lock:
	di
	ld	hl, DRIVER_HRTIMER1_IRQ_LOCK
	sra	(hl)
	jr	nc, .irq_lock_acquire
	call	kthread.yield
	jr	.irq_lock
.irq_lock_acquire:
	ld	hl, (kthread_current)
	ld	(DRIVER_HRTIMER1_IRQ_LOCK_THREAD), hl
	ei
	ret

.irq_unlock:
; does we own it ?
	ld	hl, (kthread_current)
	ld	de, (DRIVER_HRTIMER1_IRQ_LOCK_THREAD)
	or	a, a
	sbc	hl, de
; nope, bail out
	ret	nz
.irq_lock_reset:
; set them freeeeee
	ld	hl, DRIVER_HRTIMER1_IRQ_LOCK
	ld	(hl), KERNEL_MUTEX_MAGIC
	inc	hl
	ld	de, NULL
	ld	(hl), de
	ret
	
.wait:
	ld	a, DRIVER_HRTIMER1_IRQ
	jp	kthread.wait_on_IRQ

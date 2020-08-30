;include 'include/kernel.inc'

define	DRIVER_HRTIMER1_COUNTER			0xF20000
define	DRIVER_HRTIMER1_RST			0xF20004
define	DRIVER_HRTIMER1_MATCH1			0xF20008
define	DRIVER_HRTIMER1_MATCH2			0xF2000C
define	DRIVER_HRTIMER1_CTRL			0xF20030
define	DRIVER_HRTIMER1_ISCR			0xF20034
define	DRIVER_HRTIMER1_ISR			KERNEL_INTERRUPT_ISR_DATA_HRTIMER1 + 4
define	DRIVER_HRTIMER1_IRQ			00000010b
define	DRIVER_HRTIMER1_IRQ_LOCK_THREAD		KERNEL_INTERRUPT_ISR_DATA_HRTIMER1 + 1
define	DRIVER_HRTIMER1_IRQ_LOCK		KERNEL_INTERRUPT_ISR_DATA_HRTIMER1
define	DRIVER_HRTIMER1_IRQ_LOCK_SET		0

timer:

.init:
	di
; todo : enable the timer 1 with default paramater

; reset lock
	call	.irq_lock_reset
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	ld	a, DRIVER_HRTIMER1_IRQ
	jp	kinterrupt.irq_request

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
	jp	kthread.irq_resume
	
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
	jp	kthread.wait

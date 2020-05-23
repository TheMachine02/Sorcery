;include 'include/kernel.inc'

define DRIVER_RTC_COUNTER_SECOND   0xF30000
define DRIVER_RTC_COUNTER_MINUTE   0xF30004
define DRIVER_RTC_COUNTER_HOUR     0xF30008
define DRIVER_RTC_COUNTER_DAY      0xF3000C
define DRIVER_RTC_ALARM_SECOND     0xF30010
define	DRIVER_RTC_ALARM_MINUTE     0xF30014
define	DRIVER_RTC_ALARM_HOUR       0xF30018
define	DRIVER_RTC_CTRL             0xF30020
define	DRIVER_RTC_WRITE_SECOND     0xF30024
define	DRIVER_RTC_WRITE_MINUTE     0xF30028
define	DRIVER_RTC_WRITE_HOUR       0xF3002C
define	DRIVER_RTC_WRITE_DAY        0xF30030
define	DRIVER_RTC_ISCR             0xF30034
define	DRIVER_RTC_DEFAULT          01001111b

define	DRIVER_RTC_SECOND_MASK       1
define	DRIVER_RTC_MINUTE_MASK       2
define	DRIVER_RTC_HOUR_MASK         4
define	DRIVER_RTC_DAY_MASK          8
define	DRIVER_RTC_ALARM_MASK        16
define	DRIVER_RTC_LOAD_MASK         32

define	DRIVER_RTC_ISR			0xD000F6
define	DRIVER_RTC_IRQ			01000000b
define	DRIVER_RTC_IRQ_LOCK_THREAD	0xD000F7
define	DRIVER_RTC_IRQ_LOCK		0xD000FA
define	DRIVER_RTC_IRQ_LOCK_SET		0

krtc:
	db	11
.jump:
	jp	.init
	jp	.irq_handler
	jp	.irq_lock
	jp	.irq_unlock
	jp	.wait_bit
	jp	.wait_second
	jp	.wait_minute
	jp	.wait_hour
	jp	.wait_day
	jp	.set_time
	jp	.get_time
	jp	.set_alarm
	jp	.wait_alarm

.init:
	tstdi
	xor	a, a
	ld	(DRIVER_RTC_WRITE_SECOND), a
	ld	(DRIVER_RTC_WRITE_MINUTE), a
	ld	(DRIVER_RTC_WRITE_HOUR), a
	sbc	hl, hl
	ld	(DRIVER_RTC_WRITE_DAY), hl
	ld	hl, DRIVER_RTC_CTRL
	ld	(hl), DRIVER_RTC_DEFAULT
; reset lock
	call	.irq_lock_reset
; enable IRQ handler & enable IRQ
	ld	hl, .irq_handler
	ld	a, DRIVER_RTC_IRQ
	call	kirq.request
	retei

.irq_handler:
	push	af
	ld	hl, DRIVER_RTC_ISCR
	ld	a, (hl)
	ld	(DRIVER_RTC_ISR), a
	ld	(hl), 0xFF
	pop	af
	ld	hl, DRIVER_RTC_IRQ_LOCK
	bit	DRIVER_RTC_IRQ_LOCK_SET, (hl)
	ret	z
	ld	iy, (DRIVER_RTC_IRQ_LOCK_THREAD)
	push	af
	ld	a, (iy+KERNEL_THREAD_IRQ)
	or	a, a
	ld	(iy+KERNEL_THREAD_IRQ), 0
	call	nz, kthread.resume
	pop	af
	ccf
	ret	
	
.irq_lock:
	ld	hl, DRIVER_RTC_IRQ_LOCK
	sra	(hl)
	jr	nc, .irq_lock_acquire
	call	kthread.yield
	jr	.irq_lock
.irq_lock_acquire:
	ld	hl, (kthread_current)
	ld	(DRIVER_RTC_IRQ_LOCK_THREAD), hl
	ret

.irq_unlock:
; does we own it ?
	ld	hl, (kthread_current)
	ld	de, (DRIVER_RTC_IRQ_LOCK_THREAD)
	or	a, a
	sbc	hl, de
; nope, bail out
	ret	nz
.irq_lock_reset:
; set them freeeeee
	ld	hl, DRIVER_RTC_IRQ_LOCK_THREAD
	ld	de, NULL
	ld	(hl), de
	dec	hl
	ld	(hl), KERNEL_MUTEX_MAGIC
	ret
	    
.wait_alarm:
	ld	a, DRIVER_RTC_ALARM_MASK
	jr	.wait_bit
    
.wait_minute:
	ld	a, DRIVER_RTC_MINUTE_MASK
	jr	.wait_bit

.wait_hour:
	ld	a, DRIVER_RTC_HOUR_MASK
	jr	.wait_bit

.wait_day:
	ld	a, DRIVER_RTC_DAY_MASK
	jr	.wait_bit

.wait_second:
	ld	a, DRIVER_RTC_SECOND_MASK

.wait_bit:
	push	af
	ld	a, DRIVER_RTC_IRQ
	call	kthread.wait_on_IRQ
	ld	hl, DRIVER_RTC_ISR
	pop	af
	tst	a, (hl)
	jr	z, .wait_bit
	ret

.set_time:
	ret

.get_time:
	ret

.up_time:
; those read aren't atomic, so up_time isn't precise... but fast
	or	a, a
	sbc	hl, hl
	ld	a, (DRIVER_RTC_COUNTER_SECOND)
	ld	l, a
	ld	a, (DRIVER_RTC_COUNTER_MINUTE)
	ld	e, a
	ld	d, 60
	mlt	de
	add	hl, de
	ld	a, (DRIVER_RTC_COUNTER_HOUR)
	ld	e, a
	ld	d, 60
	mlt	de
	ld	b, 60
	ld	c, e
	mlt	bc
	add	hl, bc
	ld	e, 60
	mlt	de
	ex	de, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, de
	ret
	
.set_alarm:
	ret